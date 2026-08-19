# Open Questions and Research Targets

This file contains unresolved observations and hypotheses. Items here should not be described as confirmed vulnerabilities until they are reproduced and the full call path is understood.

## 1. TDVS fail-open behavior

### Confirmed behavior

`TDVS:is_user_product_owned()` returns `true` when TDVS is unavailable.

`TDVS:begin_ticket_session()` also treats specific "cannot reach server" states as a valid result.

The current condition for `cannot_reach_server` is:

```text
error == 2
or
HTTP status == 404
```

### Questions

- What exactly does `error == 2` mean in `Distribution:make_http_request()`?
- Can transient DNS, TLS, timeout, or routing failures enter the same state?
- Is `cannot_reach_server` global for the entire process?
- Once set, what clears it?
- Does inability to reach TDVS affect matchmaking connectivity in a way that makes the fail-open path irrelevant?
- Can two peers disagree about TDVS availability while otherwise remaining connected?

### Security relevance

This is a classic availability-versus-enforcement tradeoff. The client is explicitly designed to avoid rejecting ownership when the validation service is unavailable.

Whether this becomes a practical weakness depends on the surrounding networking behavior and is not established by static analysis alone.

---

## 2. Ownership state while validation is pending

### Confirmed behavior

When validation begins:

```text
pending_owned_dlc = true
owned_dlc = {}
```

`NetworkPeer` sets:

```text
_ticket_wait_response = true
```

and `set_outfit_string()` does not call `verify_outfit()` while this flag is set.

After successful validation:

```text
on_verify_ticket()
    -> verify_outfit()
```

### Questions

- Can outfit data change multiple times while `_ticket_wait_response` is set?
- Is only the latest outfit validated when the callback completes?
- Are there any network messages that use unverified outfit state before validation finishes?
- What is the maximum observed delay between join and ownership enforcement?
- Does the UI or gameplay temporarily instantiate content before the validation callback?

This may explain reports of delayed CHEATER marking without implying a bypass.

---

## 3. Duplicate `begin_ticket_session()` calls

### Confirmed behavior

`TDVS:begin_ticket_session()` contains:

```lua
if Global.TDVS.peer_tickets[account_id]
   and Global.TDVS.peer_tickets[account_id].pending_owned_dlc then
    return true
end
```

A duplicate call while validation is already pending returns success without attaching the new caller's callback to the existing request.

### Questions

- Can this path occur naturally during reconnect/retry?
- If it occurs, which `NetworkPeer` instance owns the original callback?
- Could a later peer object remain with `_ticket_wait_response` set?
- Are peer objects ever recreated while keeping the same account ID during an in-flight validation?

This is mainly a state-machine correctness question.

---

## 4. Global availability state

`Global.TDVS.cannot_reach_server` is global rather than per request or per peer.

Questions:

- Can a single failed request disable TDVS checks for every peer in the process?
- When is this value reset after a later successful request?
- Do local-ticket and remote-token requests overwrite the same availability state?
- Can a failure in local ticket acquisition influence verification of already-connected peers?

---

## 5. Ownership cache lifetime and invalidation

### Confirmed cleanup path

```text
NetworkPeer:end_ticket_session()
    -> TDVS:end_ticket_session(account_id)
    -> Global.TDVS.peer_tickets[account_id] = nil
```

Questions:

- Are all disconnect/error paths guaranteed to call `end_ticket_session()`?
- What happens during host migration or session reconstruction?
- Can a stale `peer_data` survive a network-peer object replacement?
- Can platform account type or ownership data change during a long session?
- Are TDVS tokens refreshed for existing peers before expiration?

---

## 6. Client-side JWT parsing

The client decodes JWT payload fields before `/validate_token` has returned.

It uses the decoded payload for:

```text
user_id
account_type
owned_dlc
exp (for the local ticket)
```

For remote peer ownership, `owned_dlc` is copied only in the HTTP-200 validation callback.

Questions:

- Does `/validate_token` validate signature, expiry, issuer, audience, account binding, and platform binding?
- Does it return HTTP 200 with `valid = false` for all invalid-token cases?
- Are there cases where a structurally valid but semantically invalid payload affects state before validation completes?
- Is `jwt.owned_dlc` guaranteed to be an array? What happens with malformed claim types?

Backend behavior cannot be established from the client archive alone.

---

## 7. `external = true` coverage

### Confirmed behavior

`NetworkPeer:_verify_item_data()` checks DLC ownership only when:

```text
not dlc_data.external
```

Many entries populated by `dlcmanagerentitlementdata.lua` use:

```text
entitlement_id = ...
external = true
```

Questions:

- Which exact item categories reference external DLC records?
- Is external ownership verified by another network subsystem?
- Are external records intentionally excluded because they are promotional/community content?
- Do any normal gameplay items depend exclusively on entitlement-backed external records?
- Are there cases where a local entitlement-controlled item is serialized into a network outfit but has no equivalent remote validation?

A complete answer requires building a cross-reference from all `tweak_data` content to DLC records.

---

## 8. Item-to-DLC mapping is local to the verifier

A remote peer does not send "this attachment belongs to DLC X" as the authority. The receiving client uses its own:

```text
item_data.dlc
item_data.global_value
item_data.dlc_list
Global.dlc_manager.all_dlc_data
```

Questions:

- What happens when peers run different game builds?
- Can legitimate version skew create false CHEATER reports?
- How do mods that alter `tweak_data` affect verification?
- Are unknown future items rejected before DLC mapping?
- Are duplicate aliases mapped consistently between platform product IDs?

This boundary is relevant to false positives and compatibility even without malicious behavior.

---

## 9. `skip_cheat_verification` and unlockable flags

`NetworkPeer:_verify_content()` immediately accepts items marked:

```text
unlocked
is_a_unlockable
is_an_unlockable
skip_cheat_verification
```

Questions:

- Which content entries use these flags?
- Are any DLC-backed items intentionally marked this way?
- Are these flags generated consistently across weapon, mask, melee, and cosmetic categories?
- Do mods commonly change them?

This should be documented as an explicit verification exemption list, not automatically as a vulnerability.

---

## 10. Outfit coverage

`_verify_outfit_data()` directly verifies:

```text
masks and mask customization
primary/secondary weapons
non-default weapon parts
weapon color skins
melee weapons
```

Other serialized fields exist:

```text
armor
armor skin
player style
suit variation
gloves
character
grenade
deployables
skills
```

Some are handled by separate functions, but the complete coverage map is not yet documented.

Next task:

```text
for every outfit field:
    identify serializer
    identify network receiver
    identify verifier
    identify DLC ownership source
    identify enforcement reason
```

This should become a table in `06-outfit-verification.md`.

---

## 11. Tradable inventory verification is a separate subsystem

`NetworkPeer:tradable_verify_outfit()` calls:

```text
managers.network.account:inventory_outfit_verify(...)
```

for tradable cosmetics.

Questions:

- Which items are covered by this inventory signature path?
- How does it interact with TDVS?
- Can a weapon skin be accepted by one verifier and rejected by the other?
- How are outfit versions used to prevent stale verification callbacks?

This appears conceptually separate from DLC product ownership.

---

## 12. Local entitlement status filtering

`Entitlement:SetDLCEntitlements()` forwards unique `itemId` values from the entitlement result and does not inspect `status`, `clazz`, `type`, or similar fields at this stage.

Questions:

- Does the Nebula endpoint return only active usable entitlements?
- Can revoked/consumed/expired records appear in this response?
- Is filtering performed by `SerializeJsonString()` elsewhere?
- Is the absence of local status filtering intentional?

This cannot be classified without observing real API responses under different entitlement states.

---

## 13. Entitlement pagination

The observed query begins with:

```text
offset=0
limit=100
```

Questions:

- Is there pagination logic elsewhere?
- Can an account legitimately have more than 100 PD2 entitlement records?
- Does `SerializeJsonString()` or the response structure trigger another query?
- Could entitlements after the first page be omitted?

This is worth checking because it could create false missing-DLC states for accounts with large entitlement histories.

---

## 14. Decompiler artifacts

Any suspicious branch should be validated against bytecode or runtime behavior before being treated as exact source semantics.

Particularly important areas:

- duplicated list operations in `_verify_item_data()`;
- callback/state-machine branches;
- HTTP error-code handling;
- nil/boolean coercion.

For security-sensitive conclusions, static Lua decompilation should be combined with runtime logging or debugger traces.

---

## Suggested next analysis order

1. Build a complete caller graph for `NetworkPeer:begin_ticket_session()`.
2. Trace all assignments to `Global.TDVS.cannot_reach_server`.
3. Trace every call to `TDVS:is_user_product_owned()`.
4. Build a table of every `NetworkPeer` content verifier.
5. Cross-reference `external = true` DLC records against actual BlackMarket items.
6. Inspect all entries using `skip_cheat_verification`.
7. Trace tradable inventory verification.
8. Test TDVS failure modes in a controlled environment without attempting to falsify ownership.
9. Compare behavior between Steam matchmaking and Epic matchmaking.
10. Verify critical static findings against runtime logs.
