# TDVS Multiplayer Ownership Validation

## Overview

Update 247 contains a second DLC-validation subsystem named in the code as:

```text
Ticket DLC Validation System
```

The implementation is located primarily in:

```text
lib/utils/tdvshelper.lua
lib/network/base/networkpeer.lua
```

TDVS is used when:

```lua
function TDVS:should_use()
    return IS_EPIC_MM
end
```

Therefore the observed TDVS path is specifically tied to Epic matchmaking, even when the underlying platform account is Steam.

Source: `lib/utils/tdvshelper.lua`, approximately lines 28-30.

## Local TDVS ticket acquisition

`TDVS:local_ticket(callback)` first reuses a cached TDVS ticket if it has more than 300 seconds remaining before expiry.

Otherwise it obtains a platform secure ticket:

```lua
Distribution:create_secure_ticket_for_services("tdvs", platform_ticket_callback)
```

It then sends that ticket to one of:

```text
POST https://p2wapi.paydaythegame.com/tdvs/v1/get_token_steam
POST https://p2wapi.paydaythegame.com/tdvs/v1/get_token_epic
```

For Epic, the current sandbox identifier is added.

A successful response contains:

```text
resp.token
```

which is stored as:

```text
Global.TDVS.local_ticket
```

The client decodes the JWT payload locally only to read fields such as `exp`; local decoding is not itself treated as cryptographic validation.

Source: `lib/utils/tdvshelper.lua`, approximately lines 44-100.

## Ticket transport

TDVS tickets can be long. The implementation uses a chunk size of:

```text
1000 bytes
```

If a ticket is at least that large, it is split and sent through:

```text
join_request_auth_chunk
join_request_reply_auth_chunk
```

The network-session code reassembles the chunks before beginning ticket validation.

Relevant files:

```text
lib/utils/tdvshelper.lua
lib/network/base/clientnetworksession.lua
lib/network/base/hostnetworksession.lua
lib/network/base/handlers/connectionnetworkhandler.lua
lib/network/base/session_states/hoststateinlobby.lua
lib/network/base/session_states/hoststateingame.lua
```

## Beginning a remote ticket session

`NetworkPeer:begin_ticket_session(ticket)` routes TDVS tickets to:

```text
TDVS:begin_ticket_session(account_id, ticket, callback)
```

It sets:

```text
_ticket_wait_response = true
_begin_ticket_session_called = true
```

while validation is active.

Source: `lib/network/base/networkpeer.lua`, approximately lines 133-162.

## Client-side structural checks before server validation

`TDVS:begin_ticket_session()` decodes the JWT payload and checks:

1. that the token has a decodable JWT-like payload;
2. that the network peer's `account_id` equals `jwt.user_id`.

If either check fails, validation stops immediately.

```text
account_id == jwt.user_id
```

is therefore an explicit identity-binding check before the TDVS validation request.

Source: `lib/utils/tdvshelper.lua`, approximately lines 102-118.

## Peer ownership cache

Before contacting the validation endpoint, TDVS creates:

```text
Global.TDVS.peer_tickets[account_id]
```

with:

```text
account_type
pending_owned_dlc = true
owned_dlc = {}
```

Source: `lib/utils/tdvshelper.lua`, approximately lines 120-131.

This table becomes the local cache used when validating that remote peer's DLC-backed content.

## Server validation

The peer's token is sent to:

```text
POST https://p2wapi.paydaythegame.com/tdvs/v1/validate_token
```

with:

```text
token=<ticket>
```

On an HTTP 200 response:

```lua
valid = resp.valid
```

and the client copies product IDs from the JWT payload:

```lua
for _, id in ipairs(jwt.owned_dlc) do
    peer_data.owned_dlc[tostring(id)] = true
end
```

This produces a set:

```text
peer_data.owned_dlc[product_id] = true
```

Source: `lib/utils/tdvshelper.lua`, approximately lines 133-168.

### Important architectural observation

The validation endpoint supplies the `valid` decision, but after successful validation the client populates the ownership cache from the `owned_dlc` claim in the ticket it already received.

The expected security model is therefore:

```text
token contents are trusted only after /validate_token confirms the token
```

The client itself does not appear to verify the token's signature locally.

## Ownership lookup

`TDVS:is_user_product_owned(account_id, dlc_data)`:

1. retrieves `peer_data` by account ID;
2. chooses a product ID based on `peer_data.account_type`;
3. looks up the product ID in `peer_data.owned_dlc`.

Platform mapping:

```text
STEAM -> dlc_data.app_id
EPIC  -> dlc_data.epic_id
```

Source: `lib/utils/tdvshelper.lua`, approximately lines 180-205.

## Fail-open behavior observed in the client

Several TDVS branches are explicitly permissive when the validation service cannot be reached.

`TDVS:available()` is:

```lua
return not Global.TDVS.cannot_reach_server
```

`cannot_reach_server` is set when:

```text
error == 2
or
status_code == 404
```

`TDVS:is_user_product_owned()` returns `true` when TDVS is unavailable:

```lua
if not TDVS:available() then
    return true
end
```

It also returns `true` if no peer ticket/ownership table exists:

```lua
if not peer_data or not peer_data.owned_dlc then
    return true
end
```

Source: `lib/utils/tdvshelper.lua`, approximately lines 32-34 and 180-191.

Likewise, `validate_callback()` initializes:

```lua
local valid = Global.TDVS.cannot_reach_server
```

and explicitly treats an unreachable TDVS service as a successful ticket result.

Source: `lib/utils/tdvshelper.lua`, approximately lines 133-161.

This is a genuine **availability-over-enforcement** design choice in the client. It should be described as fail-open behavior, not automatically as an exploitable vulnerability. Exploitability would depend on whether an attacker can intentionally cause only the relevant verifier to enter this state without preventing the multiplayer session itself from functioning.

## Validation timing

The outfit is deliberately not verified while ticket authentication is pending.

`NetworkPeer:set_outfit_string()` performs:

```lua
if not self._ticket_wait_response then
    self:verify_outfit()
end
```

Source: `lib/network/base/networkpeer.lua`, approximately lines 1355-1364.

After ticket validation succeeds, `NetworkPeer:on_verify_ticket()` calls:

```text
verify_outfit()
verify_character()
verify_job(...)
```

Source: `lib/network/base/networkpeer.lua`, approximately lines 164-190.

Therefore the intended sequence is:

```text
receive/set outfit
        |
        +--> ticket pending -> defer DLC verification
        |
        v
ticket validation completes
        |
        v
on_verify_ticket(success)
        |
        v
verify_outfit()
```

This explains why ownership enforcement can occur after a peer has already joined or after its outfit is already visible.

## Failed ticket behavior

If validation fails, `NetworkPeer:on_verify_ticket()` removes the peer.

On a server:

```text
send_to_peers("kick_peer", peer_id, 2)
on_peer_kicked(...)
```

There is a timing guard involving `_begin_ticket_session_called`, so removal can be deferred until the surrounding ticket-session call has unwound.

## Session cleanup

`NetworkPeer:end_ticket_session()` calls:

```text
TDVS:end_ticket_session(account_id)
```

which deletes:

```text
Global.TDVS.peer_tickets[account_id]
```

Source:

```text
lib/network/base/networkpeer.lua
lib/utils/tdvshelper.lua
```

This is the primary ownership-cache invalidation path found so far.

## Security boundary summary

TDVS moves multiplayer ownership verification away from trusting a peer's local `dlc_data.verified`.

The remote verifier instead trusts:

1. the platform identity associated with the network peer;
2. the TDVS token after backend validation;
3. the `owned_dlc` product list contained in the validated token;
4. its own local item-to-DLC mapping;
5. its own cached `Global.TDVS.peer_tickets` state.

This is substantially stronger than relying only on the joining client's local DLC manager, but it still contains client-side state and fail-open behavior that deserve further study.
