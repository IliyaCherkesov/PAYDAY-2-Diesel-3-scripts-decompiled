# Diesel 3.0 `.crate` Format

## Status

This document describes the format observed in PAYDAY 2 Update 247 `scripts.crate`.

The format was derived empirically by inspecting the archive, identifying entry boundaries, and validating the interpretation by successfully decompressing every archive entry.

Test archive:

```text
Magic:        YAOI
Version:      1
Entries:      1645
Archive size: 12,244,512 bytes
Extracted:    1645
Failed:       0
```

## Header

The archive starts with a 16-byte header.

| Offset | Size | Type | Description |
|---|---:|---|---|
| `0x00` | 4 | `char[4]` | Magic: `YAOI` |
| `0x04` | 4 | `uint32` LE | Format version |
| `0x08` | 8 | `uint64` LE | Entry count |

Observed version:

```text
1
```

## Entry table

Immediately after the header is an array of fixed-size 48-byte records.

Observed layout:

| Offset | Size | Type | Field |
|---|---:|---|---|
| `0x00` | 8 | `uint64` LE | `type_hash` |
| `0x08` | 8 | `uint64` LE | `name_hash` |
| `0x10` | 8 | `uint64` LE | `data_offset` |
| `0x18` | 8 | `uint64` LE | `unpacked_size` |
| `0x20` | 8 | `uint64` LE | `packed_size` |
| `0x28` | 8 | `uint64` LE | `flags` |

Pseudo-structure:

```c
struct CrateHeader {
    char     magic[4];      // "YAOI"
    uint32_t version;       // 1
    uint64_t entry_count;
};

struct CrateEntry {
    uint64_t type_hash;
    uint64_t name_hash;
    uint64_t data_offset;
    uint64_t unpacked_size;
    uint64_t packed_size;
    uint64_t flags;
};
```

## Payload compression

All tested entries in `scripts.crate` were successfully decompressed using zlib.

The extractor performs the equivalent of:

```python
archive.seek(entry.data_offset)
packed = archive.read(entry.packed_size)
data = zlib.decompress(packed)
```

The resulting length is checked against `unpacked_size`.

## Path recovery

The entry table itself provides hashes rather than plaintext filenames. However, LuaJIT bytecode chunks retain their original chunk names. For scripts, these names contain paths such as:

```text
lib/managers/dlcmanager.lua
lib/network/base/networkpeer.lua
core/lib/...
```

This makes it possible to reconstruct the script tree without a separate hash list.

The extractor searches the beginning of each decompressed LuaJIT chunk for a path matching forms such as:

```text
lib/.../*.lua
core/.../*.lua
```

If no path is found, a hash-based fallback filename can be used.

## Observations

- `type_hash` was constant for the tested script entries.
- `flags` was observed as zero for the tested archive.
- payload offsets appear aligned, but the precise alignment rule has not yet been formally verified;
- this document currently describes `scripts.crate`, not every `.crate` category in the game;
- other crate types may use different payload formats even if they share the same outer container.

## Extractor

The repository includes `pd2_crate_extract.py`.

Example:

```cmd
python pd2_crate_extract.py "C:\Path\To\PAYDAY 2\assets\scripts.crate" -o "C:\PD2_scripts"
```

Expected result for the tested Update 247 archive:

```text
Magic: YAOI
Version: 1
Entries: 1645
Archive size: 12,244,512 bytes

Extracted: 1645
Failed:    0
```

## Remaining format questions

- meaning and hash algorithm of `type_hash`;
- meaning and hash algorithm of `name_hash`;
- exact payload alignment rule;
- whether non-script crates use the same compression flags;
- interpretation of non-zero `flags`, if such entries exist;
- whether any crate contains uncompressed or differently compressed entries.
