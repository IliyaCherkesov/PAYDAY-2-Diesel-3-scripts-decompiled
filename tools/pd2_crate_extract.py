#!/usr/bin/env python3
import argparse
import re
import struct
import sys
import zlib
from pathlib import Path

MAGIC = b"YAOI"
HEADER_SIZE = 16
ENTRY_SIZE = 48

def safe_output_path(root: Path, rel: str) -> Path:
    rel = rel.replace("\\", "/").lstrip("/")
    out = (root / rel).resolve()
    root_resolved = root.resolve()
    if root_resolved not in out.parents and out != root_resolved:
        raise ValueError(f"Unsafe path in chunk name: {rel}")
    return out

def extract_chunk_name(blob: bytes) -> str | None:
    # Diesel's LuaJIT bytecode keeps the original chunk name near the start.
    # All scripts in scripts.crate observed so far contain a path ending in .lua.
    head = blob[:1024]

    patterns = (
        rb'((?:lib|core)/[A-Za-z0-9_./-]+\.lua)',
        rb'([A-Za-z0-9_./-]{3,}\.lua)',
    )
    for pat in patterns:
        m = re.search(pat, head)
        if m:
            return m.group(1).decode("ascii", errors="strict")
    return None

def main():
    ap = argparse.ArgumentParser(
        description="Extract PAYDAY 2 Diesel 3.0 scripts.crate (YAOI v1)."
    )
    ap.add_argument("crate", type=Path, help="Path to scripts.crate")
    ap.add_argument("-o", "--output", type=Path, default=Path("scripts_extracted"),
                    help="Output directory (default: scripts_extracted)")
    ap.add_argument("--fallback-hash-names", action="store_true",
                    help="If a Lua chunk name cannot be found, save it as _unknown/<hash>.lua")
    args = ap.parse_args()

    data = args.crate.read_bytes()
    if len(data) < HEADER_SIZE:
        raise SystemExit("File is too small.")

    if data[:4] != MAGIC:
        raise SystemExit(f"Unexpected magic {data[:4]!r}; expected {MAGIC!r}")

    version = struct.unpack_from("<I", data, 4)[0]
    count = struct.unpack_from("<Q", data, 8)[0]

    table_end = HEADER_SIZE + count * ENTRY_SIZE
    if table_end > len(data):
        raise SystemExit("Entry table extends past end of file.")

    print(f"Magic: {data[:4].decode('ascii')}")
    print(f"Version: {version}")
    print(f"Entries: {count}")
    print(f"Archive size: {len(data):,} bytes")

    args.output.mkdir(parents=True, exist_ok=True)

    extracted = 0
    failed = 0

    for i in range(count):
        base = HEADER_SIZE + i * ENTRY_SIZE

        type_hash = struct.unpack_from("<Q", data, base)[0]
        name_hash = struct.unpack_from("<Q", data, base + 8)[0]
        offset, unpacked_size, packed_size, flags = struct.unpack_from(
            "<QQQQ", data, base + 16
        )

        if offset + packed_size > len(data):
            print(f"[{i}] invalid range: offset={offset} packed={packed_size}", file=sys.stderr)
            failed += 1
            continue

        packed = data[offset:offset + packed_size]

        try:
            unpacked = zlib.decompress(packed)
        except zlib.error as e:
            print(f"[{i}] zlib error: {e}", file=sys.stderr)
            failed += 1
            continue

        if len(unpacked) != unpacked_size:
            print(
                f"[{i}] size mismatch: expected {unpacked_size}, got {len(unpacked)}",
                file=sys.stderr,
            )
            failed += 1
            continue

        rel = extract_chunk_name(unpacked)
        if rel is None:
            if not args.fallback_hash_names:
                print(f"[{i}] no Lua chunk name, name_hash={name_hash:016x}", file=sys.stderr)
                failed += 1
                continue
            rel = f"_unknown/{name_hash:016x}.lua"

        try:
            out = safe_output_path(args.output, rel)
        except ValueError as e:
            print(f"[{i}] {e}", file=sys.stderr)
            failed += 1
            continue

        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(unpacked)
        extracted += 1

    print()
    print(f"Extracted: {extracted}")
    print(f"Failed:    {failed}")
    print(f"Output:    {args.output.resolve()}")

if __name__ == "__main__":
    main()
