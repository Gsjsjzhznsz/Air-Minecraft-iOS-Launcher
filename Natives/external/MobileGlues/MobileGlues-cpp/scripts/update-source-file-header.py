#!/usr/bin/env python3
import os
import sys
import pathlib
from glob import glob

try:
    import colorama
    colorama.init()
    CYAN = colorama.Fore.CYAN + colorama.Style.BRIGHT
    GREEN = colorama.Fore.GREEN
    YELLOW = colorama.Fore.YELLOW
    RED = colorama.Fore.RED
    RESET = colorama.Style.RESET_ALL
except ImportError:
    CYAN = GREEN = YELLOW = RED = RESET = ''

OK = "✔"
FAIL = "✖"
ARROW = "╰─>"
SIMPLE_ARROW = "─>"

HEADER_TEMPLATE = """// MobileGlues - {file_path}
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header
"""

HEADER_MARKER = """End of Source File Header
"""

SCRIPT_DIR = pathlib.Path(__file__).parent.resolve()
TARGET_DIR = SCRIPT_DIR / ".."
FILE_PATTERNS = ["*.h", "*.hpp", "*.cpp", "*.cc", "*.c", "*.comp"]
EXCLUDE_DIRS = {"build", "out", "3rdparty", "include", ".cache", "external"}
SKIP_PREFIXES = ("cJSON",)
SKIP_FILENAMES = {"gles3.h", "gl.h", "glcorearb.h", "glext.h"}

if not TARGET_DIR.exists():
    print(f"{YELLOW}Target directory '{TARGET_DIR}' does not exist.{RESET}")
    sys.exit(1)

def find_source_files():
    candidates = []
    for root, dirs, files in os.walk(TARGET_DIR):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for pattern in FILE_PATTERNS:
            for f in glob(os.path.join(root, pattern)):
                candidates.append(f)
    return candidates

def ensure_endswith_newline(s: str) -> str:
    return s if s.endswith("\n") else s + "\n"

def replace_leading_comment_block(lines, start_index, new_header):
    """
    Replace consecutive lines starting at start_index that begin with '//' (allow leading whitespace)
    with new_header. lines is a list from splitlines(keepends=True).
    Returns joined string.
    """
    n = len(lines)
    i = start_index
    while i < n and lines[i].lstrip().startswith("//"):
        i += 1
    # i is first index after comment block
    prefix = "".join(lines[:start_index])  # keep any lines before start_index (usually empty)
    suffix = "".join(lines[i:]) if i < n else ""
    return prefix + new_header + suffix

candidates = find_source_files()
total = len(candidates)
print(f"{YELLOW}Found {total} candidate(s).{RESET}")

if total == 0:
    sys.exit(0)

def draw_progress(current, total, width=36):
    percent = int(current * 100 / total) if total else 0
    filled = int(current * width / total) if total else 0
    empty = width - filled
    bar = "█" * filled + "░" * empty
    print(f"\r{CYAN}Progress{RESET} [{current}/{total}] {percent:3d}% |{bar}|", end='')

processed = 0
skipped = 0
for idx, file_path in enumerate(candidates, start=1):
    draw_progress(idx, total)
    base = os.path.basename(file_path)

    if any(base.startswith(p) for p in SKIP_PREFIXES) or base in SKIP_FILENAMES:
        skipped += 1
        continue

    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        rel_path = os.path.relpath(file_path, SCRIPT_DIR.parent)
        new_header = HEADER_TEMPLATE.format(file_path=rel_path.replace("\\", "/"))
        new_header = ensure_endswith_newline(new_header)

        # if file already contains the exact header marker, preserve current behavior (replace from marker)
        if HEADER_MARKER in content:
            if file_path.endswith(".comp"):
                # For .comp, preserve first line, replace from marker in the whole content but keep first line intact.
                lines = content.splitlines(keepends=True)
                first_line = lines[0] if lines else ""
                rest = "".join(lines[1:]) if len(lines) > 1 else ""
                # replace from marker in rest
                if HEADER_MARKER in rest:
                    rest_after = rest.split(HEADER_MARKER, 1)[1]
                    new_content = ensure_endswith_newline(first_line) + new_header + rest_after
                else:
                    new_content = ensure_endswith_newline(first_line) + new_header + rest
            else:
                rest = content.split(HEADER_MARKER, 1)[1]
                new_content = new_header + rest
        else:
            # no marker present: handle leading '//' comment replacement or insertion
            lines = content.splitlines(keepends=True)
            if file_path.endswith(".comp"):
                # preserve first line, operate from second line
                first_line = lines[0] if lines else ""
                # ensure first_line ends with newline
                first_line = ensure_endswith_newline(first_line)
                rest_lines = lines[1:] if len(lines) > 1 else []
                if rest_lines:
                    # if rest has leading comment block, replace it; else insert header before rest
                    if rest_lines[0].lstrip().startswith("//"):
                        new_rest = replace_leading_comment_block(rest_lines, 0, new_header)
                    else:
                        new_rest = new_header + "".join(rest_lines)
                else:
                    new_rest = new_header
                new_content = first_line + new_rest
            else:
                # normal files: check from file start
                if lines and lines[0].lstrip().startswith("//"):
                    new_content = replace_leading_comment_block(lines, 0, new_header)
                else:
                    new_content = new_header + content

        if new_content != content:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(new_content)
            processed += 1
            print(f"\n{CYAN}Processing{RESET} {SIMPLE_ARROW} {file_path}\n   {ARROW} {GREEN}{OK}{RESET} Updated")
        else:
            skipped += 1
            print(f"\n{CYAN}Processing{RESET} {SIMPLE_ARROW} {file_path}\n   {ARROW} {GREEN}{OK}{RESET} {YELLOW}No changes{RESET}")

    except Exception as e:
        print(f"\n{CYAN}Processing{RESET} {SIMPLE_ARROW} {file_path}\n   {ARROW} {RED}{FAIL}{RESET} {e}")

print(f"\n{GREEN}All done!{RESET} Processed: {processed}, Skipped: {skipped}, Total: {total}")
