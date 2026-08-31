#!/usr/bin/env bash
# Re-signs a Mach-O ad-hoc using codesign, preserving any entitlements already
# embedded in the binary (or applying the file given as the 2nd argument).
#
# The repo previously used `ldid -S` here, but the Homebrew ldid build produces
# CodeDirectories without the CS_ADHOC flag (flags=0x0), which Apple's tooling
# reports as "not signed at all" and strict dlopen paths on device reject.
# codesign -f -s - sets the proper adhoc flag.
set -euo pipefail

FILE="${1:?usage: resign_adhoc.sh <file> [entitlements.xml]}"
ENTS_FILE="${2:-}"

tmp_ents=""
cleanup() { [ -n "$tmp_ents" ] && rm -f "$tmp_ents" || true; }
trap cleanup EXIT

if [ -z "$ENTS_FILE" ]; then
    # Preserve entitlements already embedded in the existing signature, if any.
    tmp_ents="$(mktemp -t amethyst-ents.XXXXXX)"
    if codesign -d --entitlements :"$tmp_ents" "$FILE" >/dev/null 2>&1 && [ -s "$tmp_ents" ]; then
        ENTS_FILE="$tmp_ents"
    else
        rm -f "$tmp_ents"
        tmp_ents=""
    fi
fi

codesign --force --sign - ${ENTS_FILE:+--entitlements "$ENTS_FILE"} "$FILE"
