#!/usr/bin/env python3
"""Task99: 对 JavaLauncher.m 的 ame99 段做独立语法门（g++，模拟 verify_task85 D1 的变换编译）"""
import re, subprocess, tempfile, os

src = open('Natives/JavaLauncher.m', encoding='utf-8').read()
seg = src[src.index('// Task 99（修复 A）'):src.index('int launchJVM(NSString')]

# ObjC→C++ 变换
seg = seg.replace('NSLog(@"', 'printf("')
seg = re.sub(r'@"((?:[^"\\]|\\.)*)"', r'"\1"', seg)
seg = seg = re.sub(r'return @"";', r'return (NSString *)0;', seg)
seg = re.sub(r'return "";', r'return (NSString *)0;', seg)
seg = seg.replace('return @[];', 'return (NSArray *)0;')
# @selector(x) → 桩（语法门只验 C 语义结构，选择子真实性由 verify_task99 C 区文本断言覆盖）
seg = re.sub(r'@selector\(([^)]+)\)', r'((SEL)1)', seg)
# dispatch block 字面量 → lambda（同 verify_task85 D1 变换）
seg = seg.replace('dispatch_once(&once, ^{', 'dispatch_once(&once, [&]() {')
# 本段内的 ObjC 头包含改为 harness 桩（Linux 无 objc/runtime.h）
seg = seg.replace('#include <objc/runtime.h>', '')
seg = seg.replace('#include <objc/message.h>', '')

header = '''
#include <stdint.h>
#include <stddef.h>
#include <cstdio>
#define nil ((id)0)
#define NO 0
#define YES 1
typedef long dispatch_once_t;
typedef void *id; typedef void *NSArray; typedef void *NSString;
typedef void *Class; typedef void *SEL; typedef void *IMP;
typedef int BOOL; typedef long NSInteger;
static id objc_getClass(const char *n) { (void)n; return (id)0; }
static Class objc_allocateClassPair(Class s, const char *n, size_t e) { (void)s;(void)n;(void)e; return (Class)0; }
static Class object_getClass(id o) { (void)o; return (Class)0; }
static BOOL class_addMethod(Class c, SEL s, IMP m, const char *t) { (void)c;(void)s;(void)m;(void)t; return 1; }
static void objc_registerClassPair(Class c) { (void)c; }
static id class_createInstance(Class c, size_t e) { (void)c;(void)e; return (id)0; }
static const char *sel_getName(SEL s) { (void)s; return ""; }
static const char *class_getName(Class c) { (void)c; return ""; }
template <typename F> static void dispatch_once(void *t, F b) { (void)t; b(); }
'''
harness = header + seg + '''
int main(void){ ame99_installAppKitMenuStubs(); ame99_installAppKitMenuStubs(); return 0; }
'''
with tempfile.NamedTemporaryFile('w', suffix='.cpp', delete=False) as f:
    f.write(harness)
    tmp = f.name
r = subprocess.run(['g++', '-fsyntax-only', '-std=gnu++17', '-Wall', '-Wno-unused-variable', tmp],
                   capture_output=True, text=True)
print("g++ syntax (ame99 段):", "OK" if r.returncode == 0 else "FAIL")
out = (r.stdout + r.stderr)[:2000]
if out.strip():
    print(out)
os.unlink(tmp)
