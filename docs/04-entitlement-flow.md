# Starbreeze / Nebula Entitlement Flow

## Purpose

This document describes the entitlement path implemented in:

```text
lib/utils/accelbyte/loginentitlement.lua
```

This subsystem is distinct from TDVS multiplayer ownership validation.

Its result feeds the local DLC manager.

## Configuration

The decompiled script contains:

```text
BaseUrl             = https://nebula.starbreeze.com
Namespace           = PD2
PublisherNamespace  = starbreeze
Steam platform      = steam
Epic platform       = epicgames
```

It also defines platform OAuth URLs derived from the Nebula base URL.

Source: `lib/utils/accelbyte/loginentitlement.lua`, approximately lines 3-19.

## Steam login path

For Steam, `CheckAndVerifyUserEntitlement()` obtains a secure platform ticket:

```lua
Distribution:create_secure_ticket_for_services(
    "steam_ticket",
    get_steamticket_callback
)
```

The callback prefixes it with:

```text
steam_ticket:
```

and passes it to:

```text
Login:LoginWithSteamToken()
```

`LoginWithSteamToken()` performs a POST to the Steam platform OAuth endpoint with:

```text
platform_token=<ticket>
Authorization: Basic <client credentials>
```

On success, the returned account/session data is stored in `Login.player_session`, including:

```text
access_token
platform_user_id
user_id
refresh_token
```

Source: `lib/utils/accelbyte/loginentitlement.lua`, approximately lines 168-205 and 841-855.

## Epic login path

The Epic path is structurally similar:

```text
secure Epic ticket
    |
    v
LoginWithEpicToken()
    |
    v
Nebula Epic OAuth endpoint
    |
    v
Login.player_session
```

Source: `lib/utils/accelbyte/loginentitlement.lua`, approximately lines 134-166 and 855-866.

## Linked-account check

If the cached `Login.player_session.platform_user_id` does not already match the current platform player ID, the code first obtains client credentials and checks whether that platform identity is linked to a Starbreeze account.

The relevant call chain is:

```text
CheckAndVerifyUserEntitlement()
    |
    +--> LoginWithClientCredentials()
    |
    +--> CheckPlatformIdForExistingAccount()
    |
    +--> platform secure ticket
    |
    +--> LoginWithSteamToken() / LoginWithEpicToken()
```

If no linked Starbreeze account is found, `SetDLCEntitlements()` is still called, but with the current result set, which is normally empty at that point.

## Entitlement query

Once an authenticated player session exists, the code queries:

```text
/platform/public/namespaces/PD2/users/<user_id>/entitlements
```

with query parameters:

```text
offset=<offset>
limit=<limit>
```

and:

```text
Authorization: Bearer <access_token>
```

Source: `lib/utils/accelbyte/loginentitlement.lua`, approximately lines 611-642.

The first observed call uses:

```text
offset = 0
limit  = 100
```

## Serialization

The response is parsed into `Entitlement.result.data`.

The serializer preserves fields such as:

```text
id
clazz
type
status
appId
itemId
source
namespace
```

The complete object contains substantially more metadata than the DLC manager later consumes.

Source: `lib/utils/accelbyte/loginentitlement.lua`, approximately lines 908 onward.

## Conversion into DLC entitlements

`Entitlement:SetDLCEntitlements()` creates a unique list of `itemId` values:

```lua
for _, entitlement_data in ipairs(Entitlement.result.data) do
    if not table.contains(dlc_entitlements, entitlement_data.itemId) then
        table.insert(dlc_entitlements, entitlement_data.itemId)
    end
end
```

It then calls:

```lua
managers.dlc:set_entitlements(dlc_entitlements)
```

Source: `lib/utils/accelbyte/loginentitlement.lua`, approximately lines 596-608.

### Important observation

Although the entitlement response contains fields for status, class, type, application ID, source, and other metadata, `SetDLCEntitlements()` does not locally filter those records by these fields. It forwards unique `itemId` values.

This does **not** prove invalid/revoked entitlements are accepted, because the server query may already filter what it returns. It only shows that this particular client-side conversion step does not perform additional status filtering.

## Mapping item IDs to DLC records

`lib/managers/dlc/dlcmanagerentitlementdata.lua` assigns entitlement IDs to DLC records.

Examples include records with:

```lua
entitlement_id = "<32 hex chars>"
external = true
```

Many newer records also have:

```lua
no_install = true
```

Several DLC aliases may share one entitlement ID.

Example architecture:

```text
Nebula entitlement itemId
        |
        v
Global.dlc_manager.entitlements[itemId] = true
        |
        v
dlcmanagerentitlementdata.lua
maps DLC record -> entitlement_id
        |
        v
WinSteamDLCManager:_check_dlc_data()
        |
        v
dlc_data.verified
```

## Trigger points

The entitlement refresh is invoked from more than one startup/account path.

Observed callers include:

```text
lib/states/menutitlescreenstate.lua
lib/network/matchmaking/networkaccountsteam.lua
```

Both invoke:

```text
Entitlement:CheckAndVerifyUserEntitlement()
```

This indicates entitlement acquisition is tied to account/menu initialization rather than only to DLC manager construction.

## Separation from TDVS

The Nebula entitlement path answers:

> What content should this local client consider available?

TDVS answers:

> Does a remote network peer own the platform product associated with the content it is presenting?

These systems use different identifiers and different state:

```text
Nebula entitlement:
    entitlement itemId
    -> Global.dlc_manager.entitlements
    -> dlc_data.verified

TDVS:
    platform product IDs in owned_dlc
    -> Global.TDVS.peer_tickets[account_id].owned_dlc
    -> NetworkPeer verification
```

This separation is one of the most important architectural findings in Update 247.
