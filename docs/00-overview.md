# PAYDAY 2 Update 247 Reverse Engineering Overview

## Scope

This repository documents reverse-engineering work on PAYDAY 2 after the Update 247 / Diesel 3.0 content-system changes.

The current research covers four connected areas:

1. the new `YAOI` / `.crate` script container;
2. extraction and LuaJIT decompilation of `scripts.crate`;
3. local DLC and entitlement state;
4. multiplayer DLC validation through TDVS and `NetworkPeer` outfit verification.

The goal is to document architecture, data flow, trust boundaries, and implementation behavior. This repository does not provide DLC unlockers, ownership spoofing, anti-cheat bypasses, or instructions for evading multiplayer validation.

## Research basis

The analysis is based on a decompiled Update 247 `scripts.crate` containing 1,644 Lua files after extraction/decompilation. The original archive contained 1,645 entries; one entry is not represented as a normal decompiled `.lua` source file.

Important source files:

- `lib/managers/dlcmanager.lua`
- `lib/managers/dlc/dlcmanagerentitlementdata.lua`
- `lib/utils/accelbyte/loginentitlement.lua`
- `lib/utils/tdvshelper.lua`
- `lib/network/base/networkpeer.lua`
- `lib/network/base/clientnetworksession.lua`
- `lib/network/base/hostnetworksession.lua`
- `lib/network/base/session_states/hoststateinlobby.lua`
- `lib/network/base/session_states/hoststateingame.lua`
- `lib/network/base/handlers/connectionnetworkhandler.lua`
- `lib/managers/blackmarketmanager.lua`
- `lib/managers/votemanager.lua`

Because these files were reconstructed from LuaJIT bytecode, names and control flow should be treated as decompiler output rather than canonical source. Obvious misspellings such as `verfify_*` are preserved when they exist in the decompiled output.

## High-level architecture

Update 247 contains two distinct ownership domains.

### Local content ownership

The local client builds DLC availability from platform ownership and Starbreeze/Nebula entitlement data.

```text
Steam / Epic platform identity
        |
        v
Starbreeze / Nebula login
        |
        v
user entitlement query
        |
        v
Entitlement:SetDLCEntitlements()
        |
        v
WINDLCManager:set_entitlements()
        |
        v
Global.dlc_manager.entitlements
        |
        v
WinSteamDLCManager:_check_dlc_data()
        |
        v
dlc_data.verified
        |
        v
GenericDLCManager:is_dlc_unlocked()
```

This state controls whether the local game considers DLC content available.

### Multiplayer ownership validation

Multiplayer validation has a separate path. Under Epic matchmaking (`IS_EPIC_MM`), the game uses TDVS, the Ticket DLC Validation System.

```text
platform secure ticket
        |
        v
TDVS get_token_steam / get_token_epic
        |
        v
TDVS token
        |
        v
peer sends authentication ticket
        |
        v
TDVS validate_token
        |
        v
peer_data.owned_dlc
        |
        v
NetworkPeer:_verify_outfit_data()
        |
        v
NetworkPeer:_verify_content()
        |
        v
NetworkPeer:_verify_item_data()
        |
        v
TDVS:is_user_product_owned()
        |
        +--> accepted
        |
        +--> mark_cheater() / optional autokick
```

The important architectural consequence is that making content appear unlocked locally does not automatically make a remote peer consider that content owned.

## Main findings

### 1. `.crate` is a simple indexed compressed container

`scripts.crate` begins with the magic `YAOI`, version `1`, and a 64-bit entry count. Entries are fixed-size 48-byte records containing two hashes, offset, unpacked size, packed size, and flags. Script payloads tested so far are zlib-compressed.

See [01-crate-format.md](01-crate-format.md).

### 2. Local DLC state is mutable Lua state

`WINDLCManager:set_entitlements()` converts the entitlement list into a Lua set and then recalculates `dlc_data.verified`.

`GenericDLCManager:has_dlc()` and `is_dlc_unlocked()` ultimately consume this local state.

See [03-dlc-ownership-local.md](03-dlc-ownership-local.md).

### 3. Starbreeze/Nebula provides entitlement IDs

`loginentitlement.lua` authenticates the current platform user, queries the PD2 entitlement endpoint, extracts `itemId` values, and forwards them to `managers.dlc:set_entitlements()`.

See [04-entitlement-flow.md](04-entitlement-flow.md).

### 4. TDVS introduces a separate remote-peer ownership database

`tdvshelper.lua` obtains a TDVS token using a secure Steam/Epic platform ticket. For a remote peer, the token is sent to `/tdvs/v1/validate_token`. After successful validation, product IDs from the token's `owned_dlc` claim are copied into `Global.TDVS.peer_tickets[account_id].owned_dlc`.

See [05-tdvs-network-validation.md](05-tdvs-network-validation.md).

### 5. Outfit validation maps received items back to DLC products

`NetworkPeer:_verify_outfit_data()` validates masks, mask customization, primary and secondary weapons, non-default weapon parts, weapon color skins, and melee weapons.

For DLC-backed items, `_verify_item_data()` maps the item to one or more DLC records and checks ownership for the remote account.

See [06-outfit-verification.md](06-outfit-verification.md).

## Important trust boundaries

The architecture contains several different forms of trust:

- the local client trusts mutable Lua tables for local availability;
- Nebula is trusted to return entitlement data for the authenticated account;
- TDVS is trusted to validate the multiplayer ownership token;
- the receiving peer trusts its own `tweak_data` to map a received item to a DLC;
- `NetworkPeer` trusts cached `peer_data.owned_dlc` after ticket validation;
- multiplayer enforcement remains peer-hosted rather than being enforced by a dedicated authoritative game server.

These boundaries are useful research targets even when the cryptographic/platform ticket itself is secure.

## Documentation map

- [01-crate-format.md](01-crate-format.md) — `YAOI` container format
- [02-luajit-pipeline.md](02-luajit-pipeline.md) — extraction and decompilation workflow
- [03-dlc-ownership-local.md](03-dlc-ownership-local.md) — local DLC state
- [04-entitlement-flow.md](04-entitlement-flow.md) — Starbreeze/Nebula entitlement flow
- [05-tdvs-network-validation.md](05-tdvs-network-validation.md) — multiplayer ownership tickets
- [06-outfit-verification.md](06-outfit-verification.md) — received outfit validation
- [07-open-questions.md](07-open-questions.md) — unresolved questions and research hypotheses
