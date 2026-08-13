# Network Outfit Verification

## Overview

The primary remote-content validation logic is in:

```text
lib/network/base/networkpeer.lua
```

It is separate from the local `BlackMarketManager` checks.

The network path verifies what another peer claims to have equipped.

## Entry points

### After ticket authentication

After successful ticket validation:

```text
NetworkPeer:on_verify_ticket()
    |
    +--> verify_outfit()
    +--> verify_character()
    +--> verify_job()
```

### When a peer changes its outfit

`NetworkPeer:set_outfit_string()` stores the received outfit string and immediately calls:

```text
verify_outfit()
```

unless:

```text
_ticket_wait_response
```

is set.

This prevents ownership checks from running before ticket-based ownership state is ready.

Source: `lib/network/base/networkpeer.lua`, approximately lines 1355-1388.

## Outfit deserialization

The network peer obtains a parsed outfit through:

```text
self:blackmarket_outfit()
```

The corresponding BlackMarket serialization format contains fields for:

```text
mask
mask material
mask pattern
mask colors
armor / current armor
armor skin
player style
suit variation
gloves
character
primary weapon
primary blueprint
secondary weapon
secondary blueprint
deployables
melee
grenade
skills
weapon cosmetics
```

See `BlackMarketManager:outfit_string()` and `unpack_outfit_from_string()` in:

```text
lib/managers/blackmarketmanager.lua
```

Not every serialized field is checked by `_verify_outfit_data()` itself; some are validated by separate `NetworkPeer` functions or other systems.

## `_verify_outfit_data()`

The function currently validates these categories directly.

### Masks

It verifies:

```text
mask ID
material
pattern
color A
color B
color C
```

Default blueprint parts are exempted from additional ownership verification.

Failure reason:

```text
VoteManager.REASON.invalid_mask
```

### Primary and secondary weapons

For each weapon:

1. `factory_id` is converted to a weapon ID;
2. the base weapon is validated;
3. a `safe_blueprint` is built from:
   - skin-provided parts;
   - the weapon's default blueprint;
4. every remaining blueprint part is checked as a `weapon_mods` item.

This is particularly important because it means DLC ownership can be checked at individual attachment level.

Pseudo-flow:

```text
received weapon
    |
    v
factory_id -> weapon_id
    |
    v
_verify_content("weapon", weapon_id)
    |
    v
build safe blueprint
    |
    v
for every non-default/non-skin part:
    _verify_content("weapon_mods", part_id)
```

Failure reason:

```text
VoteManager.REASON.invalid_weapon
```

Source: `lib/network/base/networkpeer.lua`, approximately lines 313-338.

### Weapon color skins

If cosmetics are a color skin, the underlying cosmetics tweak is sent directly to:

```text
_verify_item_data()
```

Failure reason:

```text
VoteManager.REASON.invalid_weapon_color
```

### Melee weapons

Melee IDs are checked through:

```text
_verify_content("melee_weapons", item)
```

Failure reason:

```text
VoteManager.REASON.invalid_weapon
```

## `_verify_content()`

`_verify_content(item_type, item_id)` loads the relevant `tweak_data`.

For regular weapons:

```text
tweak_data.weapon[item_id]
```

For BlackMarket content:

```text
tweak_data.blackmarket[item_type][item_id]
```

It rejects:

- unknown item IDs;
- items marked `unatainable`;
- the special cheat-error mask.

It accepts without further DLC validation if the item has one of:

```text
unlocked
is_a_unlockable
is_an_unlockable
skip_cheat_verification
```

Otherwise it calls:

```text
_verify_item_data(item_data)
```

Source: `lib/network/base/networkpeer.lua`, approximately lines 371-403.

## `_verify_item_data()`

This is the main DLC mapping function.

It derives one or more DLC names from:

```text
item_data.dlc
item_data.global_value -> managers.dlc:global_value_to_dlc(...)
item_data.dlc_list
```

Then, for every DLC record:

```text
Global.dlc_manager.all_dlc_data[dlc]
```

it performs ownership verification if the record exists and is **not** marked:

```text
external = true
```

Source: `lib/network/base/networkpeer.lua`, approximately lines 405-430.

### TDVS path

When TDVS should be used:

```lua
if TDVS:available()
   and not TDVS:is_user_product_owned(self._account_id, dlc_data) then
    return false
end
```

### Legacy Steam path

Without TDVS:

```lua
Steam:is_user_product_owned(self._account_id, dlc_data.app_id)
```

is used.

## Meaning of `external`

The network item validator contains:

```lua
if dlc_data and not dlc_data.external then
    ...
end
```

Therefore `external = true` DLC records are not checked through this particular platform-product ownership path.

Many entitlement-backed entries in:

```text
lib/managers/dlc/dlcmanagerentitlementdata.lua
```

are marked `external = true`.

This is a significant coverage boundary. It does **not** prove external content is unvalidated overall; it means `_verify_item_data()` intentionally excludes it from this specific check.

No equivalent remote entitlement-ID verification was identified in this function.

## Cheated-item deduplication

`_verify_cheated_outfit()` records:

```text
<item_type>_<item_id>
```

in:

```text
self._cheated_items
```

If the same invalid item has already been seen, the function returns without producing the same result again.

This avoids repeatedly reporting the identical offending item.

## Marking a peer

`verify_outfit()` receives a reason from `_verify_outfit_data()` and calls:

```text
mark_cheater(reason, Network:is_server())
```

`mark_cheater()`:

1. sets `self._cheater = true`;
2. prints a localized system message;
3. if this peer is being evaluated by the server and autokick is enabled, calls:
   ```text
   managers.vote:kick_auto(...)
   ```
4. otherwise marks the peer visually in the HUD.

Source: `lib/network/base/networkpeer.lua`, approximately lines 270-275 and 526-542.

## Autokick

`VoteManager:kick_auto()` on the server sends:

```text
kick_peer
```

and removes the peer from the network session.

It also broadcasts an `instant_kick` voting event to the other peers.

Source: `lib/managers/votemanager.lua`, approximately lines 47-60.

Relevant DLC/content reasons include:

```text
invalid_job
invalid_mask
invalid_weapon
invalid_character
invalid_player_style
invalid_glove_id
invalid_weapon_color
```

## Separate character and job checks

Not all ownership validation is inside `_verify_outfit_data()`.

### `verify_character()`

For the host character, DLC ownership is checked separately through TDVS/Steam.

### `verify_job()`

If the current job has DLC, ownership can also be checked separately.

Both use the same basic platform-product lookup mechanism.

Source: `lib/network/base/networkpeer.lua`, approximately lines 214-268.

## Relationship to local BlackMarket verification

The local BlackMarket performs similar item/DLC checks when equipping content, but that does not replace network validation.

The two systems use related content metadata but different ownership state:

```text
LOCAL
item -> DLC
    -> managers.dlc:is_dlc_unlocked()
    -> dlc_data.verified

REMOTE
received item -> DLC
    -> TDVS:is_user_product_owned(remote_account, dlc_data)
    -> peer_data.owned_dlc
```

This is why an item being accepted by the sender's local inventory is not sufficient for a remote host to accept it.
