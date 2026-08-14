# TDVS Outfit Enforcement State-Ordering Flaw

## Summary

A state-ordering flaw exists in PAYDAY 2's host-side TDVS outfit enforcement path.

When TDVS authentication succeeds, the game validates the remote player's stored outfit from inside the TDVS completion callback. At that moment, `NetworkPeer._begin_ticket_session_called` is still `true`.

If the outfit contains DLC content that the remote account does not own:

1. outfit validation returns a cheat reason;
2. `NetworkPeer:mark_cheater(reason, true)` is called;
3. `mark_cheater()` forwards `_begin_ticket_session_called` to `VoteManager:kick_auto()` as the `loading` argument;
4. `kick_auto()` suppresses the real kick while `loading` is truthy;
5. the invalid item has already been recorded as previously detected;
6. subsequent outfit validations no longer emit the same cheat reason after `_begin_ticket_session_called` is cleared.

The result is a persistent "cheater" state and visible cheat warning without the automatic kick being applied.

## Severity

**Suggested severity: Medium**

This is primarily an enforcement/state-management defect rather than an authentication failure. TDVS ownership validation itself still detects the unowned content correctly. The weakness is that the punishment path can be skipped because of state ordering.

## Affected path

Observed on the TDVS path used by Epic matchmaking. In the tested configuration:

```text
Matchmaking: Epic
Platform: Steam
```

The relevant path is:

```text
NetworkPeer:begin_ticket_session()
    ↓
TDVS:begin_ticket_session()
    ↓
TDVS callback
    ↓
NetworkPeer:on_verify_ticket()
    ↓
NetworkPeer:verify_outfit()
    ↓
NetworkPeer:_verify_outfit_data()
    ↓
NetworkPeer:_verify_content()
    ↓
NetworkPeer:_verify_item_data()
    ↓
TDVS:is_user_product_owned()
    ↓
NetworkPeer:mark_cheater()
    ↓
VoteManager:kick_auto()
```

## Root cause

### 1. Ticket state remains set during outfit verification

The TDVS branch sets `_begin_ticket_session_called` before starting asynchronous validation.

Conceptually, the code behaves like:

```lua
self._ticket_wait_response = true
self._begin_ticket_session_called = true

local function ticket_callback(result, reason)
    self:on_verify_ticket(result, reason)
    self._begin_ticket_session_called = nil
end
```

The important ordering is:

```text
_begin_ticket_session_called = true
        ↓
TDVS callback
        ↓
on_verify_ticket()
        ↓
verify_outfit()
        ↓
mark_cheater()
        ↓
callback returns
        ↓
_begin_ticket_session_called = nil
```

Therefore all enforcement triggered synchronously by `on_verify_ticket()` still sees `_begin_ticket_session_called == true`.

### 2. `mark_cheater()` passes this state directly into `kick_auto()`

The relevant logic is effectively:

```lua
if auto_kick and Global.game_settings.auto_kick then
    managers.vote:kick_auto(
        reason,
        self,
        self._begin_ticket_session_called
    )
end
```

The third parameter becomes the `loading` argument.

### 3. `kick_auto()` suppresses the actual kick while `loading` is true

The enforcement code only performs the real peer removal when `loading` is false/nil:

```lua
if not loading then
    managers.network:session():send_to_peers(
        "kick_peer",
        peer:id(),
        0
    )

    managers.network:session():on_peer_kicked(
        peer,
        peer:id(),
        0
    )
end
```

So when outfit verification happens inside the TDVS completion callback:

```text
_begin_ticket_session_called = true
        ↓
kick_auto(..., loading=true)
        ↓
if not loading
        ↓
false
        ↓
no on_peer_kicked()
```

### 4. The item is suppressed from later duplicate reporting

The outfit verification path tracks previously detected invalid items.

Conceptually:

```lua
self._cheated_items = self._cheated_items or {}

local item = tostring(item_type) .. "_" .. tostring(item_id)

if self._cheated_items[item] then
    return
end

self._cheated_items[item] = true

return result
```

This creates the second half of the flaw:

```text
first validation:
    invalid item
    ↓
    item recorded in _cheated_items
    ↓
    reason returned
    ↓
    kick suppressed because loading=true

later validation:
    same invalid item
    ↓
    already present in _cheated_items
    ↓
    no reason returned
    ↓
    mark_cheater() is not called again
    ↓
    no second opportunity to kick
```

## Runtime evidence

A clean host received a remote peer's TDVS ticket while the peer had no cached ownership state:

```text
AUTH BEGIN
TDVS BEGIN
TDVS state: pending=true, owned=0
```

The host then sent the join reply and loading state before TDVS validation completed:

```text
HOST SEND rpc=join_request_reply
HOST SEND rpc=set_loading_state
```

The remote outfit arrived while TDVS was still pending.

After the TDVS callback completed successfully, the host had five owned products cached for the remote account and immediately entered outfit validation.

The invalid content detected in this run was:

```text
category=melee_weapons
item=kabar
dlc=gage_pack_lmg
app_id=275590
```

Ownership resolution failed:

```text
OWNERSHIP ... app_id=275590 ... returns={1=nil}
ITEM DATA ... returns={1=false}
CONTENT ... melee_weapons / kabar ... returns={1=false}
OUTFIT DATA ... returns={1=9}
```

The host then called:

```text
CHEATER ... reason=9 auto_kick=true
```

but `_begin_ticket_session_called` was still true.

The peer was marked:

```text
cheater=true
```

yet no `end_ticket_session()` or peer removal followed.

Several seconds later, the same peer continued sending outfit updates while still connected:

```text
peer=2 ... cheater=true
```

Repeated validation again found the same DLC item invalid, but `_verify_outfit_data()` returned no cheat reason and no second `mark_cheater()` call occurred.

## Contrast with delayed test

An earlier controlled timing test artificially delayed `on_verify_ticket()`.

During that test, `_begin_ticket_session_called` became `nil` before outfit enforcement ran.

The same class of ownership failure then produced:

```text
mark_cheater(... auto_kick=true)
    ↓
end_ticket_session()
    ↓
peer removed
```

This contrast is important because it isolates the difference to state ordering rather than TDVS ownership resolution.

## State machine

```text
                  ┌─────────────────────────────┐
                  │ begin_ticket_session_called │
                  │            = true           │
                  └──────────────┬──────────────┘
                                 │
                           TDVS request
                                 │
                         backend success
                                 │
                          TDVS callback
                                 │
                       on_verify_ticket()
                                 │
                         verify_outfit()
                                 │
                     unowned DLC detected
                                 │
                      _cheated_items set
                                 │
                           reason = 9
                                 │
                    mark_cheater(9, true)
                                 │
            kick_auto(9, peer, loading=true)
                                 │
                      if not loading
                                 │
                              false
                                 │
                        NO REAL KICK
                                 │
                        callback returns
                                 │
                  _begin_ticket_session_called
                              = nil
                                 │
                       next outfit update
                                 │
                    same item still invalid
                                 │
                    already in _cheated_items
                                 │
                         no reason returned
                                 │
                     no second mark_cheater
                                 │
                         no second kick
```

## Why this is a state-ordering bug

Each individual behavior is understandable in isolation:

- avoid kicking a peer while it is still in a loading/authentication-sensitive phase;
- avoid repeatedly reporting the same invalid item;
- validate a stored outfit immediately after ticket verification succeeds.

The failure appears only when these rules interact.

The TDVS completion callback performs the first authoritative outfit check before the loading/authentication marker is cleared. The first violation is therefore consumed while kicking is disabled, and duplicate suppression prevents enforcement from being retried afterward.

## Security properties that still work

This finding does **not** show that TDVS ownership verification can be forged.

The following behavior was confirmed to work:

- the host independently checks remote outfit DLC ownership;
- unowned DLC content is detected;
- the correct DLC/app mapping is resolved;
- the peer is marked as a cheater;
- a user-visible cheat message is generated.

The defect is specifically in the transition from **detection** to **automatic removal**.

## Recommended fixes

Several fixes would remove the state-ordering dependency.

### Option A — clear the loading marker before enforcement

Move the state transition before the call that can trigger outfit verification:

```lua
local function ticket_callback(result, reason)
    self._begin_ticket_session_called = nil
    self:on_verify_ticket(result, reason)
end
```

This is the smallest conceptual change, but the wider lifecycle meaning of `_begin_ticket_session_called` should be audited before changing it.

### Option B — do not overload `_begin_ticket_session_called` as `kick_auto()`'s loading state

Use an explicit state indicating whether removal is unsafe at that exact moment.

For example:

```text
ticket request pending
ticket verified
peer loading
peer admitted
peer enforceable
```

This avoids using one boolean for multiple lifecycle meanings.

### Option C — defer the kick rather than discard it

If a peer is detected while `loading=true`, queue the enforcement action and execute it as soon as the peer becomes enforceable.

Conceptually:

```text
violation detected while loading
    ↓
pending_auto_kick = reason
    ↓
loading state ends
    ↓
execute queued kick
```

### Option D — do not consume duplicate-suppression state until enforcement succeeds

Instead of immediately recording the invalid item as handled, only suppress future reports once the relevant enforcement action has actually completed.

## Suggested regression tests

A fixed implementation should cover at least these cases:

1. unowned DLC detected after TDVS verification when the outfit arrived before authentication completed;
2. unowned DLC detected from a later outfit update;
3. the same invalid item repeated several times;
4. multiple distinct invalid DLC items in one outfit;
5. TDVS success followed by immediate outfit validation;
6. TDVS failure / unavailable backend paths;
7. peer disconnect during the asynchronous TDVS request.

Expected invariant:

> If host-side ownership validation returns an invalid-DLC cheat reason with auto-kick enabled, the peer must either be removed immediately or have a deterministic pending kick that executes once removal becomes safe.

## Controlled reproduction

Environment:

```text
Machine A: clean host
Machine B: separate test client
Matchmaking: Epic
Platform: Steam
Host auto-kick: enabled
```

Instrumentation recorded:

```text
NetworkPeer:begin_ticket_session
TDVS:begin_ticket_session
NetworkPeer:on_verify_ticket
NetworkPeer:set_outfit_string
NetworkPeer:verify_outfit
NetworkPeer:_verify_outfit_data
NetworkPeer:_verify_content
NetworkPeer:_verify_item_data
TDVS:is_user_product_owned
NetworkPeer:mark_cheater
NetworkPeer:end_ticket_session
```

Observed sequence:

```text
1. remote peer starts TDVS authentication
2. host sends join reply while TDVS is pending
3. outfit arrives and is stored
4. TDVS succeeds
5. host validates stored outfit
6. DLC ownership fails
7. outfit validation returns reason 9
8. mark_cheater(reason=9, auto_kick=true)
9. peer becomes cheater=true
10. no kick occurs
11. peer remains connected
12. later validation suppresses the same item as already reported
```

## Status

**Confirmed in controlled runtime testing.**

The observed runtime behavior matches the decompiled state transitions and was reproduced in both normal and artificially delayed callback timing, with the delayed run acting as a useful control case.
