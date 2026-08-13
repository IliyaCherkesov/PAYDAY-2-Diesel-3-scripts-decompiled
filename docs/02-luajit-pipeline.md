# LuaJIT Extraction and Decompilation Pipeline

## Overview

Extracting `scripts.crate` does not directly produce human-readable Lua.

The pipeline has two separate stages:

```text
scripts.crate
    |
    |  pd2_crate_extract.py
    v
LuaJIT bytecode files
    |
    |  luajit-decompiler-v2
    v
decompiled Lua source
```

This distinction is important: `.crate` compression and LuaJIT bytecode are two independent layers.

## Stage 1: extract the crate

Requirements:

- Python 3
- `pd2_crate_extract.py`

Example:

```cmd
python pd2_crate_extract.py "C:\Path\To\PAYDAY 2\assets\scripts.crate" -o "C:\PD2_scripts"
```

The resulting directory preserves paths recovered from LuaJIT chunk names.

Example:

```text
C:\PD2_scripts\
├── core\
│   └── lib\
└── lib\
    ├── managers\
    ├── network\
    ├── states\
    └── utils\
```

These `.lua` files are still binary LuaJIT chunks. Editors such as VS Code may display them as binary or report unsupported text encoding.

## Stage 2: decompile LuaJIT bytecode

The tested decompiler is:

```text
marsinator358/luajit-decompiler-v2
```

Create the destination directory first:

```cmd
mkdir C:\PD2_decompiled
```

Then run the decompiler from the directory containing the executable:

```cmd
luajit-decompiler-v2.exe "C:\PD2_scripts" -o "C:\PD2_decompiled" -e lua -s
```

After completion, `C:\PD2_decompiled` contains searchable Lua source.

## Why bulk decompilation matters

The ownership system spans many files and subsystems. Looking at one script at a time hides the relationships between:

- entitlement acquisition;
- DLC state calculation;
- network authentication;
- TDVS ticket validation;
- outfit serialization;
- received outfit validation;
- cheater marking and autokick.

Bulk decompilation makes cross-file searches possible.

Useful search terms include:

```text
set_entitlements
has_entitlement
is_dlc_unlocked
TDVS
owned_dlc
begin_ticket_session
verify_outfit
_verify_content
_verify_item_data
is_user_product_owned
mark_cheater
kick_auto
```

## Important source paths

### Local DLC logic

```text
lib/managers/dlcmanager.lua
lib/managers/dlc/dlcmanagerentitlementdata.lua
lib/managers/dlc/dlcmanagergenerateddata.lua
lib/managers/dlc/dlcmanagerwin32data.lua
```

### Starbreeze/Nebula account and entitlement logic

```text
lib/utils/accelbyte/loginentitlement.lua
```

### Multiplayer ticket validation

```text
lib/utils/tdvshelper.lua
```

### Network ownership enforcement

```text
lib/network/base/networkpeer.lua
lib/network/base/clientnetworksession.lua
lib/network/base/hostnetworksession.lua
lib/network/base/session_states/hoststateinlobby.lua
lib/network/base/session_states/hoststateingame.lua
lib/network/base/handlers/connectionnetworkhandler.lua
```

### Local inventory / item mapping

```text
lib/managers/blackmarketmanager.lua
```

### Enforcement reasons and autokick

```text
lib/managers/votemanager.lua
```

## Decompiler caveats

Decompiled output is not equivalent to the original source code.

Potential artifacts include:

- reconstructed local variable names;
- changed formatting;
- duplicated or awkward expressions;
- spelling that may originate from either the original code or the decompiler;
- control flow that is semantically correct but not identical to source;
- loss of comments.

For example, the decompiled BlackMarket code contains names such as:

```text
_verfify_equipped
verfify_crew_loadout
verfify_recived_crew_loadout
```

These names should not be silently corrected when documenting call chains unless explicitly labeled as normalized names.

## Reproducibility

For research notes, record at least:

- PAYDAY 2 update/build;
- `scripts.crate` size;
- archive entry count;
- extractor revision;
- decompiler build/revision;
- number of successfully extracted entries;
- number of successfully decompiled files.

For the tested archive:

```text
Update:         247
Archive:        scripts.crate
Magic:          YAOI
Version:        1
Entries:        1645
Extracted:      1645
Decompiled Lua: 1644 files
```

The difference between archive entries and normal `.lua` files should be investigated rather than assumed to be an extraction failure.
