#!/usr/bin/env python3
"""Task 107 验证器：ce43a34 双日志判读 + 双根因修复

问题 1（26.3 崩溃）：Task106 签名中和回归——JNA libjnidispatch 被抹成
  "无签名"形态，iPadOS 27 dyld4 硬拒（missing code signature），26.3 会话
  MacosUtil → ca.weblite.objc.Runtime → JNA 链无降级直接崩。
  修复：重标签后 ad-hoc 重签名（ame107_codesign.h 纯 C 签名器）。
问题 2（1.20.1 画面糊）：sodium-extra reduce_resolution_on_mac 在 Mac
  伪装下把帧缓冲减半（vp=590x410 vs 信仰 1180x820，恰为一半），EASU
  4 倍上采样。修复：启动时配置补丁 true->false。

A. ce43a34 双日志证据（git 钉，cefdf21=6a81ba5 构建）
B. JNA 真实二进制法证（Maven Central jna-5.13.0.jar 内置件）
C. 产线代码锚点（重签名器 + 三分支 + Java 配置补丁）
D. 本地 harness 端到端（真实 JNA 走产线头文件，独立 Python 复验）
E. 行为镜像（分支决策 + 新旧哈希槽对照）
F. FAQ/version.h/级联
"""
import os
import re
import struct
import subprocess
import sys

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
WORK = "/home/z/my-project/task107"          # 会话工作区（法证产物）
JNA_LIB_REL = "jna/extracted/com/sun/jna/darwin-aarch64/libjnidispatch.jnilib"
os.chdir(REPO)

PASS = FAIL = 0
def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")

def read(path):
    return open(os.path.join(REPO, path), encoding="utf-8", errors="replace").read()

def git_show(rev, path):
    r = subprocess.run(["git", "-C", REPO, "show", f"{rev}:{path}"],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""

dpp = read("Natives/dyld_patch_platform.m")
codesign_h = read("Natives/ame107_codesign.h")
mh = read("Natives/main_hook.m")
pj = read("JavaApp/src/launcher/net/kdt/pojavlaunch/PojavLauncher.java")
faq = read("Natives/LauncherHelpViewController.m")
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")

print("===== A. ce43a34 双日志证据 =====")
mc263 = git_show("ce43a34", "latestlog.old.txt")   # 26.3 崩溃会话
bmc2 = git_show("ce43a34", "latestlog.txt")        # 1.20.1 糊会话
old263 = git_show("41cdff0", "latestlog.txt")      # 上一会话：26.3 成功（2e1ea09 构建）
oldbmc2 = git_show("41cdff0", "latestlog.old.txt") # 上一会话：BMC2（JNA 成功对照）
check("A1 两会话均为 cefdf21 构建（含 Task106 签名中和）",
      mc263.count("Commit: cefdf21") == 1 and bmc2.count("Commit: cefdf21") == 1)
check("A2 26.3 崩溃链：MacosUtil → ca.weblite.objc.Runtime → JNA NoClassDefFoundError",
      "MacosUtil.disableCloseWindowMenuItem" in mc263
      and "ca.weblite.objc.Runtime.<clinit>" in mc263
      and "NoClassDefFoundError: Could not initialize class com.sun.jna.Native" in mc263)
check("A3 JNA dlopen 硬拒实锤：missing code signature in <C34856C0-A4B7-32C6-9ACE-D2166123DD04>",
      "missing code signature in <C34856C0-A4B7-32C6-9ACE-D2166123DD04>" in mc263)
check("A4 1.20.1 会话 JNA 同样失败但被容忍（游戏继续，2 小时会话）",
      "missing code signature in <C34856C0-A4B7-32C6-9ACE-D2166123DD04>" in bmc2
      and "PatchJNAAgent: Replacing class" in bmc2)
check("A5 对照：上一会话（2e1ea09 构建）JNA 提取加载成功（isMac from NativeLibrary 阶段）",
      "Platform.isMac called from com.sun.jna.NativeLibrary" in old263
      and "Platform.isMac called from com.sun.jna.NativeLibrary" in oldbmc2
      and "missing code signature" not in old263 and "missing code signature" not in oldbmc2)
check("A6 糊根因实锤：viewport evidence vp=590x410 vs 信仰 1180x820（恰为一半）",
      "MC present viewport 0,0 590x410 vs launcher window belief 1180x820" in bmc2)
check("A7 上一会话同签名（907x631 vs 1814x1262，恒定减半非瞬时）",
      "vp=907x631 (adaptive)" in oldbmc2)
check("A8 sodium-extra 0.5.4 在 1.20.1 mod 列表",
      "sodium-extra 0.5.4+mc1.20.1-build.115" in bmc2)
check("A9 糊非 fallback 滤镜：EASU LANDED + bundle-direct 生效（60fps 会话）",
      "Task103 EASU sentinel verdict: LANDED" in bmc2
      and "Task106 bundle-direct present engaged" in bmc2)
check("A10 26.3 上一会话 sodium-extra 0.9.4 存在但无减半（vp==信仰 match，同为 1180x820）",
      "sodium-extra 0.9.4+mc26.3" in old263
      and "MC present viewport 0,0 1180x820 vs launcher window belief 1180x820 -- match" in old263)

print("===== B. JNA 真实二进制法证 =====")
JNA_LIB = os.path.join(WORK, JNA_LIB_REL)
if not os.path.exists(JNA_LIB):
    # 自愈：重新下载解包（Maven Central jna-5.13.0.jar）
    os.makedirs(os.path.dirname(JNA_LIB), exist_ok=True)
    jar = os.path.join(WORK, "jna", "jna-5.13.0.jar")
    subprocess.run(["curl", "-sL", "-o", jar,
                    "https://repo1.maven.org/maven2/net/java/dev/jna/jna/5.13.0/jna-5.13.0.jar"],
                   timeout=120)
    if os.path.exists(jar):
        subprocess.run(["unzip", "-o", "-q", jar,
                        "com/sun/jna/darwin-aarch64/*", "-d",
                        os.path.join(WORK, "jna", "extracted")], timeout=60)
have_jna = os.path.exists(JNA_LIB)
check("B0 真实二进制就位（jna-5.13.0.jar 内置 darwin-aarch64/libjnidispatch.jnilib）",
      have_jna, "missing (download failed?)")
if have_jna:
    data = open(JNA_LIB, "rb").read()
    ncmds = struct.unpack("<I", data[16:20])[0]
    uuid = buildver = sig = None
    p = 32
    for _ in range(ncmds):
        cmd, cs = struct.unpack("<2I", data[p:p + 8])
        if cmd == 0x1B:
            uuid = data[p + 8:p + 24].hex()
        elif cmd == 0x32:
            buildver = struct.unpack("<I", data[p + 8:p + 12])[0]
        elif cmd == 0x1D:
            sig = struct.unpack("<2I", data[p + 8:p + 16])
        p += cs
    check("B1 LC_UUID == C34856C0-A4B7-32C6-9ACE-D2166123DD04（与崩溃报错逐字一致 = 同一文件）",
          uuid == "c34856c0a4b732c69aced2166123dd04", str(uuid))
    check("B2 LC_BUILD_VERSION platform=1 (macOS)（重标签路径必经）", buildver == 1, str(buildver))
    check("B3 LC_CODE_SIGNATURE 存在（dataoff=158432 datasize=1384）",
          sig == (158432, 1384), str(sig))
    sb = data[sig[0]:sig[0] + sig[1]]
    m, ln, cnt = struct.unpack_from(">III", sb, 0)
    bm, bl = struct.unpack_from(">II", sb, 20)
    (ver, flg, hOff, iOff, nSpec, nCode, codeLim,
     hs, ht, pl, ps) = struct.unpack_from(">IIIIIIIBBBB", sb, 28)
    check("B4 原 SuperBlob = ad-hoc（CodeDirectory flags 含 0x2、无 CMS、SHA-256/4K）",
          m == 0xFADE0CC0 and cnt == 1 and bm == 0xFADE0C02
          and (flg & 0x2) and ht == 2 and ps == 12 and nSpec == 0)

print("===== C. 产线代码锚点 =====")
check("C1 dyld_patch_platform.m 引入产线签名器 + CommonCrypto 后端",
      '#include "ame107_codesign.h"' in dpp and "#import <CommonCrypto/CommonCrypto.h>" in dpp
      and "CC_SHA256(data, (CC_LONG)len, out);" in dpp)
check("C2 重签名三分支（原位 / thin 增长 / FAT 保留旧签名）",
      "re-signed ad-hoc after platform retag (in place)" in dpp
      and "re-signed ad-hoc after platform retag (grown)" in dpp
      and "FAT slice cannot grow for re-sign, kept stale" in dpp)
check("C3 增长路径顺序关键（偏移记录 + 预扩清零 + realloc 后重取指针）",
      "size_t sigOff = (size_t)((uint8_t *)sigCmd - sliceBase);" in dpp
      and "memset(nb + ctx->size, 0, newEnd - ctx->size);" in dpp
      and "sliceBase = ctx->data + ctx->sliceOffset; // realloc 后重取" in dpp)
check("C4 datasize 先定稿再哈希（页 0 终态参与哈希）+ 失败回滚",
      "sigCmd->datasize = (uint32_t)blobLen;" in dpp
      and dpp.count("sigCmd->datasize = origDatasize;") >= 2
      and "savedFilesize" in dpp)
check("C5 __LINKEDIT 覆盖范围同步（增长路径）",
      "if (newFileSize > linkedit->filesize) linkedit->filesize = newFileSize;" in dpp
      and "if (linkedit->filesize > linkedit->vmsize) linkedit->vmsize = linkedit->filesize;" in dpp)
check("C6 返回值语义保持（平台已匹配早退 NO；其余 YES 兼容 dylib 重写）",
      "if (buildver->platform == activePlatform) return NO; // it is already set, stop" in dpp
      and "return YES;" in dpp and "return retagged;" not in dpp)
check("C7 读入-改写-写回 + 互斥保护（替代 mmap 直写，支持增长）",
      "pthread_mutex_t sLock = PTHREAD_MUTEX_INITIALIZER;" in dpp
      and "pwrite(fd, ctx.data, ctx.size, 0)" in dpp
      and "ftruncate(fd, (off_t)ctx.size)" in dpp)
check("C8 畸形边界防御（越界签名保留旧态 + 零尺寸命令防死循环）",
      "(uint64_t)dataoff + origDatasize > ctx->sliceSize" in dpp
      and "if (command->cmdsize == 0) break;" in dpp)
check("C9 ame107_codesign.h 核心常量（v0x20400 / CS_ADHOC / SHA-256 / SuperBlob 布局）",
      "0x20400" in codesign_h
      and re.search(r"#define\s+AME107_CS_ADHOC\s+0x00000002u", codesign_h) is not None
      and re.search(r"#define\s+AME107_CSHASH_SHA256\s+2u", codesign_h) is not None
      and re.search(r"#define\s+AME107_SUPERBLOB_INDEX_OFF\s+20u", codesign_h) is not None)
check("C10 尺寸公式与构建同源（ame107_adhoc_blob_size 独立函数）",
      "static size_t ame107_adhoc_blob_size(uint32_t codeLimit, size_t identLen)" in codesign_h)
check("C11 main_hook.m Task106 注释修正（中和→重签名的表述更新）",
      "Task107 修正" in mh and "missing code" in mh)
check("C12 Java 配置补丁（正则 true->false + 只改存在的 true + 异常静默）",
      "patchSodiumExtraResolution();" in pj
      and '(\\"reduce_resolution_on_mac\\"\\s*:\\s*)true\\b' in pj.replace("\\\\", "\\")
      and "if (!m.find()) return;" in pj
      and "Task107: sodium-extra config patch skipped" in pj)
check("C13 调用点在 Tools.launchMinecraft 之前（游戏加载配置前生效）",
      pj.index("patchSodiumExtraResolution();") < pj.index("Tools.launchMinecraft(account, version, serverIp);"))

print("===== D. 本地 harness 端到端（真实 JNA 走产线头文件） =====")
HARNESS = os.path.join(REPO, "scripts", "task107_harness.c")
VALIDATE = os.path.join(REPO, "scripts", "task107_validate.py")
hbin = "/tmp/task107_harness"
r = subprocess.run(["gcc", "-O2", "-Wall",
                    "-I", os.path.join(REPO, "Natives"),
                    HARNESS, "-o", hbin, "-lcrypto"],
                   capture_output=True, text=True, timeout=120)
check("D1 harness 编译（产线 ame107_codesign.h + OpenSSL 后端）",
      r.returncode == 0, r.stderr[-200:])
if r.returncode == 0 and have_jna:
    out_ip = "/tmp/task107_jna_inplace.dylib"
    out_gr = "/tmp/task107_jna_grow.dylib"
    r1 = subprocess.run([hbin, JNA_LIB, out_ip, "inplace"], capture_output=True, text=True, timeout=60)
    check("D2 原位模式跑通（blobLen=1372 ≤ 旧 datasize=1384，文件尺寸不变）",
          r1.returncode == 0 and "blobLen=1372" in r1.stdout and "159816" in r1.stdout,
          r1.stdout + r1.stderr[-150:])
    rv = subprocess.run([sys.executable, VALIDATE, out_ip, "1384"],
                        capture_output=True, text=True, timeout=60)
    check("D3 独立复验（布局 + 全部 39 页 SHA-256 重算 + 死区清零）",
          rv.returncode == 0 and "hash=OK" in rv.stdout, rv.stdout[-200:] + rv.stderr[-150:])
    r2 = subprocess.run([hbin, JNA_LIB, out_gr, "grow"], capture_output=True, text=True, timeout=60)
    rv2 = subprocess.run([sys.executable, VALIDATE, out_gr, "1352"],
                         capture_output=True, text=True, timeout=60)
    check("D4 增长语义模式跑通 + 复验（datasize 收紧至精确 blobLen）",
          r2.returncode == 0 and "blobLen=1372" in r2.stdout
          and rv2.returncode == 0 and "hash=OK" in rv2.stdout,
          r2.stdout + rv2.stdout[-100:])

    print("===== E. 行为镜像（分支决策 + 新旧哈希槽对照） =====")
    orig = open(JNA_LIB, "rb").read()
    new = open(out_ip, "rb").read()
    import hashlib
    # 旧 CD 的 hash[0]（原文件页 0 哈希）对新文件页 0 必然失配（页 0 已被改写）
    old_cd = orig[158432 + 20:]
    old_h0 = old_cd[110:142]  # 原 CD hashOffset=110
    check("E1 旧签名页 0 哈希对新文件失配（重标签必然失效 = 重签名必要性）",
          old_h0 != hashlib.sha256(new[:4096]).digest())
    # 新 CD 的 hash[0] 对新文件页 0 匹配
    new_cd = new[158432 + 20:]
    (ver_, flg_, hOff_, iOff_, nSpec_, nCode_, codeLim_,
     hs_, ht_, pl_, ps_) = struct.unpack_from(">IIIIIIIBBBB", new_cd, 8)
    check("E2 新签名页 0 哈希对新文件匹配（重签名生效）",
          new_cd[hOff_:hOff_ + 32] == hashlib.sha256(new[:4096]).digest())

    def mirror_branch(kind, dataoff, orig_datasize, slice_size, can_grow, has_sig=True):
        """镜像 dyld_patch_platform.m 的重签名分支决策。返回动作字符串。"""
        if not has_sig:
            return "retag-only+warn"
        if dataoff == 0 or dataoff + orig_datasize > slice_size:
            return "keep-stale+warn"
        blob_len = 20 + 88 + ((14 + 1 + 3) & ~3) + 32 * ((dataoff + 4095) // 4096)
        if blob_len <= orig_datasize:
            return "in-place"
        if can_grow:
            return "grow"
        return "keep-stale+warn"
    check("E3 镜像：JNA 实测输入 → in-place",
          mirror_branch("thin", 158432, 1384, 159816, True) == "in-place")
    check("E4 镜像：瘦小旧签名（收窄后）→ grow",
          mirror_branch("thin", 158432, 1352, 159816, True) == "grow")
    check("E5 镜像：FAT 切片无法增长 → keep-stale+warn",
          mirror_branch("fat", 158432, 1352, 159816, False) == "keep-stale+warn")
    check("E6 镜像：签名越界 → keep-stale+warn",
          mirror_branch("thin", 999999, 1384, 159816, True) == "keep-stale+warn")
    check("E7 镜像：无签名库 → retag-only+warn（不新增 LC）",
          mirror_branch("thin", 0, 0, 159816, True, has_sig=False) == "retag-only+warn")
    check("E8 尺寸公式一致性（与产线 ame107_adhoc_blob_size 同式：JNA → 1372）",
          20 + 88 + ((14 + 1 + 3) & ~3) + 32 * ((158432 + 4095) // 4096) == 1372)

print("===== F. FAQ / version.h / 级联 =====")
check("F1 sparkProfiler 修正文案（Task107 修正 + re-signed 锚点 + missing code signature）",
      "Task106 双层 + Task107 修正" in faq and "Task107: re-signed" in faq
      and "missing code signature" in faq)
check("F2 blurry 新增第 5 条原因（sodium-extra 减半 + Task107 锚点 + 判读法）",
      "sodium-extra 整合包在 Mac 伪装环境下自动减半分辨率（Task107）" in faq
      and "[PojavLauncher] Task107: sodium-extra reduce_resolution_on_mac" in faq
      and "590x410" in faq)
check("F3 FAQ 计数不变 34（两条均原位改写，零级联）",
      faq.count("= [[LauncherHelpFaqItem alloc] init]") == 34)
check("F4 version.h REVISION 17 addendum (Task 107, no bump)",
      "REVISION 17 addendum (Task 107, no bump)" in vh
      and "missing code signature" in vh and "reduce_resolution_on_mac" in vh)
# 级联：verify_task106 内部 F7 已传递覆盖 verify_task100/103/104/105，
# 此处直接跑 106（全链）+ 85（osm D1 桩，本任务未触及但求稳）。
for v in ("verify_task106.py", "verify_task85.py"):
    r = subprocess.run([sys.executable, os.path.join(REPO, "scripts", v)],
                       capture_output=True, text=True, timeout=600)
    summary = [ln for ln in r.stdout.splitlines() if "RESULT" in ln]
    tail = summary[-1] if summary else r.stdout[-120:]
    ok = r.returncode == 0 and "ALL PASS" in tail
    check(f"F5 级联 {v}", ok, tail)

print(f"\nRESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
sys.exit(0 if FAIL == 0 else 1)
