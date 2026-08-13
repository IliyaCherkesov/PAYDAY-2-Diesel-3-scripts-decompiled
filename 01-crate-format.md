# Diesel 3.0 .crate Format

Tested against PAYDAY 2 Update 247 `scripts.crate`.

## Header

| Offset | Size | Type | Description |
|---|---:|---|---|
| 0x00 | 4 | char[4] | Magic: `YAOI` |
| 0x04 | 4 | uint32 | Version |
| 0x08 | 8 | uint64 | Entry count |

Observed:
- Version: 1
- Entries: 1645

## Entry structure

Each entry is 48 bytes.

| Offset | Size | Field |
|---|---:|---|
| 0x00 | 8 | type_hash |
| 0x08 | 8 | name_hash |
| 0x10 | 8 | data_offset |
| 0x18 | 8 | unpacked_size |
| 0x20 | 8 | packed_size |
| 0x28 | 8 | flags |

Payloads in `scripts.crate` are zlib-compressed.

