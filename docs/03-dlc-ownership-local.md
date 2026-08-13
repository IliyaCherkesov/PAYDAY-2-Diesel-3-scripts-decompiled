# Local DLC Ownership

## Purpose

This document describes how the local PAYDAY 2 client decides whether DLC content is available after Update 247.

The main source is:

```text
lib/managers/dlcmanager.lua
```

Entitlement metadata is added by:

```text
lib/managers/dlc/dlcmanagerentitlementdata.lua
```

## Local DLC data model

`WINDLCManager:init()` initializes:

```lua
Global.dlc_manager = {}
Global.dlc_manager.all_dlc_data = {}
Global.dlc_manager.entitlements = {}
```

It then calls:

```text
init_dlc_data()
init_generated()
init_entitlements()
_chk_blocked()
```

Source: `lib/managers/dlcmanager.lua`, approximately lines 1071-1095.

This means the final DLC database is assembled from multiple generated/platform-specific sources before verification occurs.

## `verified` is the local availability state

The important per-DLC state is:

```text
Global.dlc_manager.all_dlc_data[dlc].verified
```

`WINDLCManager:_verify_dlcs()` iterates every DLC record and sets `verified = true` when `_check_dlc_data()` succeeds.

```lua
for dlc_name, dlc_data in pairs(Global.dlc_manager.all_dlc_data) do
    if not dlc_data.verified and self:_check_dlc_data(dlc_data) then
        dlc_data.verified = true
    end
end
```

Source: `lib/managers/dlcmanager.lua`, approximately lines 1193-1199.

## Entitlement set

`WINDLCManager:set_entitlements()` converts an entitlement list into a Lua set:

```lua
Global.dlc_manager.entitlements = table.list_to_set(entitlements or {})
Global.dlc_manager.received_entitlements = true
self:chk_content_updated()
```

`has_entitlement()` is then only a table lookup:

```lua
return Global.dlc_manager.entitlements[entitlement_id]
```

Source: `lib/managers/dlcmanager.lua`, approximately lines 1228-1236.

This is a useful architectural distinction:

- acquisition of entitlement data can be server-backed;
- consumption of that entitlement data is local mutable Lua state.

## DLC verification sources

`WinSteamDLCManager:_check_dlc_data()` can verify a DLC using multiple mechanisms.

### Platform product ownership / installation

If a record has `app_id` or `epic_id`, it selects the product ID for the active distribution platform.

For `no_install` DLC:

```text
Distribution:is_product_owned(app_id)
```

Otherwise:

```text
Distribution:is_product_installed(dlc_data.app_id)
```

### Steam source membership

If `source_id` is present on Steam:

```text
Steam:is_user_in_source(Steam:userid(), dlc_data.source_id)
```

### Starbreeze entitlement

If `entitlement_id` exists:

```text
self:has_entitlement(dlc_data.entitlement_id)
```

### `verify_all`

The `verify_all` field changes the logic from "any configured verification source can succeed" to a stricter aggregate behavior.

Source: `lib/managers/dlcmanager.lua`, approximately lines 1283-1348.

## Content refresh

`chk_content_updated()` differs from `_verify_dlcs()` because it recalculates every record and can move `verified` in either direction:

```lua
has_content = self:_check_dlc_data(dlc_data)
content_updated = content_updated or has_content ~= dlc_data.verified
dlc_data.verified = has_content
```

If the result changes while the game is in the main menu:

```text
give_dlc_and_verify_blackmarket()
```

is called immediately.

Otherwise:

```text
Global.dlc_manager.verify_content_update = true
```

defers the refresh until a suitable state.

Source: `lib/managers/dlcmanager.lua`, approximately lines 1209-1260.

## Save/load behavior

The entitlement set is persisted:

```lua
data.dlc_entitlements = Global.dlc_manager.entitlements
```

On load, cached entitlements are accepted only if a fresh entitlement response has not already been received:

```lua
if data.dlc_entitlements and not Global.dlc_manager.received_entitlements then
    Global.dlc_manager.entitlements = data.dlc_entitlements
    self:chk_content_updated()
end
```

This appears to provide startup/offline continuity while allowing fresh server data to replace the cache.

Source: `lib/managers/dlcmanager.lua`, approximately lines 1239-1252.

## Consumer path

The commonly used public check is:

```text
managers.dlc:is_dlc_unlocked(dlc)
```

For ordinary DLC entries, the chain is approximately:

```text
is_dlc_unlocked(dlc)
    |
    v
has_dlc(dlc)
    |
    v
Global.dlc_manager.all_dlc_data[dlc].verified
```

There are special-case DLC records that route through a DLC-specific function instead of directly reading `verified`.

## BlackMarket interaction

The BlackMarket manager repeatedly consumes `is_dlc_unlocked()` when deciding whether local content can be equipped or retained.

Examples include:

- weapon part DLC checks;
- weapon cosmetics;
- character DLC;
- masks;
- player styles;
- suit variations;
- gloves;
- grenades;
- melee weapons.

One particularly clear example is `weapon_unlocked_by_crafted()`:

```lua
for part_id, dlc in pairs(crafted.global_values or {}) do
    if ... and not managers.dlc:is_dlc_unlocked(dlc) then
        return false, dlc
    end
end
```

Source: `lib/managers/blackmarketmanager.lua`, approximately lines 544-557.

## Relationship to multiplayer validation

Local availability and remote-peer validation are not the same system.

A local client can consider an item available because its own `dlc_data.verified` is true. A remote peer under TDVS does not simply trust that boolean. It reconstructs the received outfit, maps items to DLC records using its own data, and checks the remote account's TDVS ownership set.

Therefore:

```text
local "unlocked" != remote "ownership validated"
```

See [05-tdvs-network-validation.md](05-tdvs-network-validation.md) and [06-outfit-verification.md](06-outfit-verification.md).
