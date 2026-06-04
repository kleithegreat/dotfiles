#!/usr/bin/env python3
"""Patch Discord's Linux Krisp module for Nix-packaged Discord."""

import mmap
import sys
from bisect import bisect_right
from pathlib import Path

import lief


ELF_SIG = b"\x66\x0f\xd7\xc0\x3d\xff\xff\x00\x00"
RETURN_TRUE = b"\xb8\x01\x00\x00\x00\xc3"
LINUX_EXTERNAL_INIT_PATCH = b"\x31\xc0\xc3"

INIT_CALL = "KrispModule._initialize(initializationParams);"
INIT_GUARD = "process.env.NIXPKGS_KRISP_INITIALIZED"
INIT_PATCH = f"""if ({INIT_GUARD} !== "1") {{
    {INIT_CALL}
    {INIT_GUARD} = "1";
}}"""


def unique_match(mm: mmap.mmap, needle: bytes, start: int, end: int) -> int:
    idx = mm.find(needle, start, end)
    if idx == -1 or mm.find(needle, idx + 1, end) != -1:
        raise SystemExit("expected exactly one Krisp signature-check match")
    return idx


def patch_signature(path: Path) -> None:
    binary = lief.ELF.parse(str(path))
    text = binary.get_section(".text")
    if text is None:
        raise SystemExit("could not find .text in discord_krisp.node")

    text_off = text.file_offset
    text_end = text_off + text.size
    text_delta = text.virtual_address - text_off
    functions = tuple(sorted(f.address for f in binary.functions if f.address))
    if not functions:
        raise SystemExit("could not find function starts in discord_krisp.node")

    with path.open("r+b") as f, mmap.mmap(f.fileno(), 0) as mm:
        sig_off = unique_match(mm, ELF_SIG, text_off, text_end)
        sig_vaddr = sig_off + text_delta
        func_idx = bisect_right(functions, sig_vaddr) - 1
        if func_idx < 0:
            raise SystemExit("could not locate Krisp signature-check function")
        func_off = functions[func_idx] - text_delta
        state = "already patched" if mm[func_off : func_off + len(RETURN_TRUE)] == RETURN_TRUE else "patched"
        mm[func_off : func_off + len(RETURN_TRUE)] = RETURN_TRUE
        print(f"[discord-krisp] signature check {state}")


def patch_external_init(path: Path) -> None:
    binary = lief.parse(str(path))
    symbol = binary.get_dynamic_symbol("KrispInitializeExternal")
    if symbol is None:
        raise SystemExit("could not find KrispInitializeExternal")

    offset = binary.virtual_address_to_offset(symbol.value)
    data = bytearray(path.read_bytes())
    end = offset + len(LINUX_EXTERNAL_INIT_PATCH)
    if end > len(data):
        raise SystemExit("KrispInitializeExternal patch is outside the binary")
    data[offset:end] = LINUX_EXTERNAL_INIT_PATCH
    path.write_bytes(data)
    print("[discord-krisp] external init patched")


def patch_index(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if INIT_GUARD in text:
        return
    if INIT_CALL not in text:
        raise SystemExit(f"could not find Krisp initialize call in {path}")
    path.write_text(text.replace(INIT_CALL, INIT_PATCH), encoding="utf-8")
    print("[discord-krisp] index.js init guard patched")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <discord_krisp module dir>")

    module_dir = Path(sys.argv[1])
    node = module_dir / "discord_krisp.node"
    patch_signature(node)
    patch_external_init(node)
    patch_index(module_dir / "index.js")


if __name__ == "__main__":
    main()
