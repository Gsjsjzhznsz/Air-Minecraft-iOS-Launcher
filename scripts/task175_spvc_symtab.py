#!/usr/bin/env python3
"""Task175 forensics B: parse LC_SYMTAB nlist entries of the spirv-cross impl.

The export-trie walk proved unreliable (see task175_spvc_exports.py history);
the symbol table is a plain array of nlist64 and answers the real question:
are the new-API and/or old-API spvc option functions DEFINED GLOBALS here?
"""
import struct
import sys

PATH = "Natives/resources/Frameworks/libspirv-cross-c-shared.0.impl.dylib"
WANT = [
    "spvc_context_create_compile_options",
    "spvc_compile_options_set_option",
    "spvc_compiler_set_compile_options",
    "spvc_compiler_create_compiler_options",
    "spvc_compiler_options_set_bool",
    "spvc_compiler_options_set_uint",
    "spvc_compiler_install_compiler_options",
    "spvc_context_parse_spirv",
    "spvc_context_create_compiler",
    "spvc_compiler_compile",
    "spvc_context_destroy",
]

data = open(PATH, "rb").read()
ncmds = struct.unpack_from("<I", data, 16)[0]
off = 32
symoff = nsyms = stroff = strsize = None
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from("<II", data, off)
    if cmd == 0x2:  # LC_SYMTAB
        symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, off + 8)
        break
    off += cmdsize

print(f"symtab: symoff={symoff} nsyms={nsyms} stroff={stroff} strsize={strsize}")

N_EXT = 0x01
N_TYPE = 0x0E  # mask over n_type low bits (N_SECT=0xE is type field value)


def symname(idx):
    end = data.index(b"\x00", stroff + idx)
    return data[stroff + idx:end].decode("utf-8", "replace")


globals_defined = {}
for i in range(nsyms):
    e = symoff + i * 16
    n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", data, e)
    if n_strx == 0:
        continue
    name = symname(n_strx)
    if name.startswith("_") and (n_type & N_EXT) and (n_type & N_TYPE) != 0:
        globals_defined[name[1:]] = (n_type, n_value)

print(f"defined globals: {len(globals_defined)}")
for w in WANT:
    present = w in globals_defined
    extra = f" (type=0x{globals_defined[w][0]:02x} value=0x{globals_defined[w][1]:x})" if present else ""
    print(("OK      " if present else "MISSING ") + w + extra)

spvc_all = sorted(k for k in globals_defined if k.startswith("spvc"))
print(f"\nspvc_* defined globals total: {len(spvc_all)}")
