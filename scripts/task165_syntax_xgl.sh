#!/usr/bin/env bash
# Task165 syntax gate: stub-compile the new xglGetProcAddress body extracted
# from egl.cpp (the full TU needs macOS/MG headers we do not have on Linux;
# the bracket-balance gate already covers the rest of the file).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - << 'PY'
import re
src = open("Natives/external/MobileGlues/MobileGlues-cpp/egl/egl.cpp", encoding="utf-8").read()
m = re.search(
    r"(EGL_API EGLAPI __eglMustCastToProperFunctionPointerType EGLAPIENTRY xglGetProcAddress\(const char\* procname\) \{.*?\n    \})",
    src, re.S)
assert m, "xglGetProcAddress body not found"
body = m.group(1)
stub = r'''
#include <cstdlib>
#include <cstring>
#include <cstdio>
typedef void* __eglMustCastToProperFunctionPointerType;
#define EGL_API __attribute__((visibility("default")))
#define EGLAPI
#define EGLAPIENTRY
#define LOG_I(...) do { printf(__VA_ARGS__); printf("\n"); } while (0)
static __eglMustCastToProperFunctionPointerType eglGetProcAddress(const char*) { return nullptr; }
''' + body + r'''
int main() {
    return xglGetProcAddress("glDrawArrays") == nullptr ? 0 : 0;
}
'''
open("/tmp/task165_xgl_stub.cpp", "w").write(stub)
print("[task165] stub written:", len(stub), "bytes")
PY

g++ -Wall -Wextra -Werror -std=c++17 -fsyntax-only /tmp/task165_xgl_stub.cpp
echo "[task165] xglGetProcAddress stub compile: OK"
