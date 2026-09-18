#!/usr/bin/env python3
"""Task 106 验证器：41cdff0 双日志判读 + 双根因修复

A. 崩溃日志证据（git 钉 41cdff0，2e1ea09 构建）
B. spark 原生库法证（真实 Modrinth jar 的 Mach-O 属性 + 补丁逻辑 Python 镜像）
C. 代码锚点（main_hook.m 拦截 + dyld_patch_platform.m 签名中和）
D. osm_bridge bundle-direct + 相位计时锚点
E. 行为镜像（bundle-direct 状态机 + 哨兵位置数学 + 签名中和不变量）
F. FAQ/version.h/级联
"""
import os
import re
import struct
import subprocess
import sys
import tempfile

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
SCRIPTS = os.path.join(REPO, "scripts")
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

mh = read("Natives/main_hook.m")
dpp = read("Natives/dyld_patch_platform.m")
ob = read("Natives/ctxbridges/osm_bridge.mm")
faq = read("Natives/LauncherHelpViewController.m")
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")

print("===== A. 崩溃日志证据（git 钉 41cdff0） =====")
bmc2 = git_show("41cdff0", "latestlog.old.txt")
mc263 = git_show("41cdff0", "latestlog.txt")
check("A1 BMC2 会话最后一行 = [Amethyst] Patching spark libasyncProfiler.so.tmp（静默死亡现场）",
      bmc2.rstrip().endswith("[Amethyst] Patching /private/var/mobile/Containers/Data/Application/"
                             "C0D59969-9D27-4DAF-A08D-7CE2679E371F/Documents/Data/Application/"
                             "65C83894-2D46-40D5-B73D-C604E4874D67/Documents/instances/default/"
                             "custom_gamedir/modrinth_D1CC78A5-1CEB-42FE-8C52-C1941E528C0E/"
                             "config/spark/tmp/spark-60a9b3ffb0cd-libasyncProfiler.so.tmp"),
      bmc2.rstrip()[-160:])
check("A2 死亡前一刻是 spark 'Starting background profiler...'（首次世界创建触发）",
      "Starting background profiler..." in bmc2[-2000:])
check("A3 无 exit/hs_err/SIGSEGV 尾迹（SIGKILL 静默特征）",
      not re.search(r"exit\(|hs_err|SIGSEGV|fatal trace", bmc2[-1500:]))
check("A4 崩溃前内存已 5.1GB 且为会话峰值攀升段（排除内存不足为第一嫌疑的时序依据：早前曾存活 5982MB）",
      "mem=5155MB" in bmc2 and "mem=5982MB" in bmc2)
check("A5 历史会话从未触发过重标签路径（本设备首次 = 机制首次暴露）",
      git_show("c947464", "latestlog.txt").count("[Amethyst] Patching") == 0
      and git_show("c947464", "latestlog.old.txt").count("[Amethyst] Patching") == 0
      and git_show("341c110", "latestlog.old.txt").count("[Amethyst] Patching") == 0
      and mc263.count("[Amethyst] Patching") == 0)
check("A6 同日志对实证 BMC2 蜷缩已被 Task105 修复（vp=907x631 adaptive + 60fps）",
      "vp=907x631 (adaptive)" in bmc2 and "fps=60" in bmc2)
check("A7 26.3 会话干净退出（FastQuit 保存成功 + exit(0)，无崩溃）",
      "FastQuit] 成功保存" in mc263 and "exit(0) called" in mc263)
check("A8 26.3 fps 锁 30 实锤（RenderDiag 序列 28-30，含加载期）",
      re.search(r"fps=29 swapOK=0", mc263) is not None
      and re.search(r"fps=30 swapOK=0", mc263) is not None)
check("A9 26.3 会话 FSR preset=4 scale=2.00（与 c947464 preset=1 同帧率 = 分辨率无关常数实证）",
      "preset=4 scale=2.00" in mc263 and "preset=1 scale=1.30" in git_show("c947464", "latestlog.old.txt"))

print("===== B. spark 原生库法证（真实 jar 内置 Mach-O） =====")
SPARK_SO = "/home/z/my-project/task106_spark/spark/macos/libasyncProfiler.so"
have_spark = os.path.exists(SPARK_SO)
check("B0 真实二进制就位（Modrinth spark-1.10.53-fabric.jar 内置件，本地法证用）",
      have_spark, "missing (rerun task106 fetch)")
if have_spark:
    data = open(SPARK_SO, "rb").read()
    check("B1 FAT 双架构（x86_64 + arm64）",
          struct.unpack(">I", data[:4])[0] == 0xCAFEBABE
          and struct.unpack(">I", data[4:8])[0] == 2)
    # 解析 arm64 切片
    off = 8
    arm = None
    for i in range(2):
        cputype, cpusub, offset, size, align = struct.unpack(">5I", data[off:off + 20])
        if cputype == 0x0100000C:
            arm = (offset, size)
        off += 20
    check("B2 arm64 切片存在", arm is not None)
    slice_off, slice_size = arm
    hdr = data[slice_off:slice_off + slice_size]
    ncmds = struct.unpack("<I", hdr[16:20])[0]
    platform = sig = None
    p = 32
    for i in range(ncmds):
        cmd, cmdsize = struct.unpack("<2I", hdr[p:p + 8])
        if cmd == 0x32:  # LC_BUILD_VERSION（0x2D 是 LC_LINKER_OPTION）
            platform = struct.unpack("<I", hdr[p + 8:p + 12])[0]
        elif cmd == 0x1D:  # LC_CODE_SIGNATURE
            sig = struct.unpack("<2I", hdr[p + 8:p + 16])
        p += cmdsize
    check("B3 arm64 切片 platform=1 (macOS) + LC_CODE_SIGNATURE 存在（签名实锤）",
          platform == 1 and sig is not None and sig[1] > 0,
          f"platform={platform} sig={sig}")
    if sig:
        check("B4 签名 blob 恰为文件尾（切片相对偏移 dataoff+datasize == 切片大小）",
              sig[0] + sig[1] == slice_size, f"{sig[0]}+{sig[1]} vs {slice_size}")

print("===== C. 代码锚点（拦截 + 签名中和） =====")
check("C1 拦截在 hooked_dlopen 顶部（先于 PLPatchMachOPlatformForFile 调用）",
      0 <= mh.index("libasyncProfiler") < mh.index("PLPatchMachOPlatformForFile(path);"))
check("C2 拦截日志锚点 + return NULL（JVM 侧转 UnsatisfiedLinkError → spark 降级 Java 采样器）",
      "[Amethyst] Task106: blocked dlopen of signed macOS profiler lib" in mh
      and re.search(r"strstr\(path, \"libasyncProfiler\"\) != NULL\) \{[\s\S]{0,600}?return NULL;", mh) is not None)
check("C3 dyld_patch_platform 记录 LC_CODE_SIGNATURE 命令",
      "command->cmd == LC_CODE_SIGNATURE" in dpp and "sigCmd = (struct linkedit_data_command *)command;" in dpp)
check("C4 中和仅在确实发生平台重标签时执行（platform 已匹配的早退路径零扰动）",
      "if (retagged && sigCmd != NULL) {" in dpp and "retagged = YES;" in dpp)
check("C5 LC_CODE_SIGNATURE → LC_SOURCE_VERSION（等尺寸 16 字节良性替身）",
      "#define kAme106LCSourceVersion 0x2A" in dpp and "sigCmd->cmd = kAme106LCSourceVersion;" in dpp)
check("C6 签名 blob 清零（dyld 视为未签名而非签名失效）",
      "memset(sliceBase + sigCmd->dataoff, 0, sigCmd->datasize);" in dpp)
check("C7 返回值语义保持（dylib 名重写仍触发 msync；仅签名中和新增）",
      dpp.rstrip().count("return YES;") >= 1 and "return retagged;" not in dpp)

print("===== D. osm_bridge bundle-direct + 相位计时锚点 =====")
check("D1 ame106 状态结构（active/warm/misses/hits + 四相累计）",
      "} ame106 = {0};" in ob and "double tPreUs, tFinUs, tReadUs, tSwapUs;" in ob
      and "double lastEntryUs, gapSumUs, gapMaxUs;" in ob)
check("D2 bundle 哨兵位置（top-down：近角 行H-1列0 / 远角 行1列W-2）",
      "size_t nearIdx = (size_t)(h - 1) * stride + 3;" in ob
      and "size_t farIdx = stride + (size_t)(w - 2) * 4 + 3;" in ob
      and "return buf[nearIdx] == code && buf[farIdx] == code;" in ob)
check("D3 warmup 30 帧激活 + 一次性日志",
      "if (++ame106.warm >= 30) {" in ob
      and "Task106 bundle-direct present engaged: 30 consecutive fresh full-surface EASU frames" in ob)
check("D4 激活态 2 连失回退权威路径",
      "else if (++ame106.misses >= 2) {" in ob
      and "Task106 bundle-direct fallback: driver buffer lost per-frame sentinels" in ob)
check("D5 fresh 判定绑定当帧 EASU（fsrActiveThisFrame + markerArmed + 当帧 markerCode）",
      "bool bundleFresh106 = fsrActiveThisFrame && ame83_fsr.markerArmed &&" in ob
      and "(unsigned char)ame83_fsr.markerCode);" in ob)
check("D6 权威回读跳过门（bundle-direct 激活时 present 不跑）",
      "if (fsrActiveThisFrame && bundle.width > 0 && bundle.height > 0 && !ame106.active) {" in ob)
check("D7 哨兵票核心共享（scratch/bundle 双票源同一状态机）",
      "static void ame103_marker_vote(bool mkHit, osm_render_window_t bundle) {" in ob
      and ob.count("ame103_marker_vote(mkHit, bundle);") == 2)
check("D8 bundle 票分支（probeFrames 供血 + 越界钳制）",
      "else if (ame106.active && stripRows > 2 && ame83_fsr.markerArmed &&" in ob
      and "nearIdx106 < total106 && farIdx106 < total106" in ob)
check("D9 心跳扩展（bd=N/M + 四相计时 + MC-side 归因）",
      "bd=%ld/%ld t=swap %.1f(max %.1f) [pre+easu %.1f glFinish %.1f readback %.1f]ms frame=%.1f MC-side=%.1fms" in ob)
check("D10 相位计时点（t106_0 入口 / t106_1 EASU 后 / t106_2 glFinish 后 / 末段 swap 累计）",
      "double t106_0 = ame106_us(mach_absolute_time());" in ob
      and "double t106_1 = ame106_us(mach_absolute_time());" in ob
      and "double t106_2 = ame106_us(mach_absolute_time());" in ob
      and "ame106.tSwapUs += t106_end - t106_0;" in ob)
check("D11 bundle-direct 全幅呈现的滤镜还原（Nearest 纪律与 present 分支同款）",
      "if (ame106.active && fsrActiveThisFrame && ame104_filters_linear) {" in ob)
check("D12 verdict 迁移日志保留 Task103/104 原文 + bundle-direct 尾注",
      "Task103 EASU sentinel verdict" in ob and "Task104 far-corner hits %d/%d" in ob
      and "(both sentinels required for LANDED)%s" in ob
      and "vote fed by driver buffer (present buffer intentionally stale in bundle-direct mode)" in ob)
check("D13 CROP 兜底数据源优先级不变（present 优先 bundle 回退）",
      "presentThisFrame ? ame100_present.present" in ob)

print("===== E. 行为镜像（Python） =====")
# E1: bundle-direct 状态机镜像
def simulate(fresh_seq):
    active, warm, misses = False, 0, 0
    states = []
    for fresh in fresh_seq:
        if active:
            if fresh:
                misses = 0
            else:
                misses += 1
                if misses >= 2:
                    active, warm, misses = False, 0, 0
        elif fresh:
            warm += 1
            if warm >= 30:
                active, misses = True, 0
        else:
            warm = 0
        states.append(active)
    return states

check("E1 持续不新鲜 → 永不激活", not any(simulate([False] * 50)))
check("E2 30 连新鲜 → 第 30 帧激活", simulate([True] * 31)[29] is True and simulate([True] * 29)[28] is False)
check("E3 激活后 2 连失 → 回退", simulate([True] * 30 + [False, False])[-1] is False)
check("E4 单失不回退（容忍瞬时毛刺）", simulate([True] * 30 + [False, True])[-1] is True)
check("E5 回退后需重新 warmup 30 帧", simulate([True] * 30 + [False, False] + [True] * 29)[-1] is False
      and simulate([True] * 30 + [False, False] + [True] * 30)[-1] is True)

# E2 组: 哨兵位置数学镜像（与 ame106_bundle_sentinels 同式）
def sentinels_ok(buf, w, h, code):
    if w < 8 or h < 8:
        return False
    stride = w * 4
    near_idx = (h - 1) * stride + 3
    far_idx = stride + (w - 2) * 4 + 3
    total = w * h * 4
    if near_idx >= total or far_idx >= total:
        return False
    return buf[near_idx] == code and buf[far_idx] == code

W, H, CODE = 16, 12, 0x5A
buf = bytearray(W * H * 4)
near_i = (H - 1) * W * 4 + 3
far_i = 1 * W * 4 + (W - 2) * 4 + 3
buf[near_i] = CODE
buf[far_i] = CODE
check("E6 双哨兵就位 → 判新鲜", sentinels_ok(buf, W, H, CODE))
buf[far_i] = CODE ^ 0xFF
check("E7 远角缺失 → 判不新鲜（覆盖受限/陈旧）", not sentinels_ok(buf, W, H, CODE))
buf[far_i] = CODE
buf[near_i] = (CODE % 254) + 1
check("E8 码不匹配（陈旧帧的旧哨兵）→ 判不新鲜", not sentinels_ok(buf, W, H, CODE))
check("E9 小尺寸拒绝（<8）", not sentinels_ok(buf, 6, H, CODE) and not sentinels_ok(buf, W, 6, CODE))

# E3 组: 签名中和 Python 镜像（构造与真实 spark 库同构的最小 FAT Mach-O）
def build_fat(active_platform):
    # arm64 切片：header + LC_BUILD_VERSION(24B) + LC_CODE_SIGNATURE(16B) + 尾部 blob
    arm_body = bytearray()
    ncmds = 2
    sizeofcmds = 24 + 16
    hdr = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 6, ncmds, sizeofcmds, 0, 0)
    arm_body += hdr
    arm_body += struct.pack("<6I", 0x32, 24, 1, (11 << 16), (13 << 16), 0)  # LC_BUILD_VERSION(0x32) platform=1 macos, minos 11.0
    blob_off = len(hdr) + sizeofcmds
    blob = bytes(range(256)) * 4  # 1024B 假签名
    arm_body += struct.pack("<4I", 0x1D, 16, blob_off, len(blob))
    arm_body += blob
    # x86_64 切片：占位（不被 patch）
    x86 = struct.pack("<8I", 0xFEEDFACF, 0x01000007, 0, 6, 0, 0, 0, 0) + b"\xAA" * 64
    fat_header = struct.pack(">2I", 0xCAFEBABE, 2)
    arm_off = 4096
    x86_off = arm_off + ((len(arm_body) + 4095) // 4096) * 4096
    fat = fat_header
    fat += struct.pack(">5I", 0x01000007, 3, x86_off, len(x86), 12)
    fat += struct.pack(">5I", 0x0100000C, 0, arm_off, len(arm_body), 12)
    fat += b"\0" * (arm_off - len(fat))
    fat += bytes(arm_body)
    fat += b"\0" * (x86_off - len(fat))
    fat += x86
    return fat, arm_off

def mirror_patch(fat, arm_off, active_platform):
    fat = bytearray(fat)
    hdr = fat[arm_off:]
    ncmds = struct.unpack("<I", hdr[16:20])[0]
    p = 32
    retagged = False
    sig = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<2I", hdr[p:p + 8])
        if cmd == 0x32:
            platform = struct.unpack("<I", hdr[p + 8:p + 12])[0]
            if platform == active_platform:
                return bytes(fat), "early-return"  # 已匹配 → 零扰动
            struct.pack_into("<I", fat, arm_off + p + 8, active_platform)
            retagged = True
        elif cmd == 0x1D:
            sig = struct.unpack("<2I", hdr[p + 8:p + 16])
        p += cmdsize
    if retagged and sig:
        # cmd → LC_SOURCE_VERSION(0x2A)，blob 清零
        sig_cmd_off = None
        p = 32
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack("<2I", hdr[p:p + 8])
            if cmd == 0x1D:
                sig_cmd_off = p
            p += cmdsize
        struct.pack_into("<I", fat, arm_off + sig_cmd_off, 0x2A)
        fat[arm_off + sig[0]: arm_off + sig[0] + sig[1]] = b"\0" * sig[1]
    return bytes(fat), "patched"

fat, arm_off = build_fat(active_platform=1)
patched, mode = mirror_patch(fat, arm_off, active_platform=13)  # iOS 活动平台
check("E10 镜像：重标签发生（macOS→iOS）", mode == "patched"
      and struct.unpack("<I", patched[arm_off + 40:arm_off + 44])[0] == 13)
# LC_CODE_SIGNATURE 位点（第 2 条命令，偏移 32+24=56）
check("E11 镜像：签名命令改写为 LC_SOURCE_VERSION(0x2A) 等尺寸",
      struct.unpack("<2I", patched[arm_off + 56:arm_off + 64]) == (0x2A, 16))
blob_off = 32 + 40  # header 32 + 24 + 16
check("E12 镜像：签名 blob 全零", patched[arm_off + blob_off:arm_off + blob_off + 1024] == b"\0" * 1024)
check("E13 镜像：x86_64 切片零扰动", b"\xAA" * 64 in patched)
check("E14 镜像：文件尺寸不变（无截断/扩展）", len(patched) == len(fat))
same, mode2 = mirror_patch(fat, arm_off, active_platform=1)  # 平台已匹配
check("E15 镜像：平台已匹配 → 早退零扰动（签名保持有效）", mode2 == "early-return" and same == fat)

print("===== F. FAQ / version.h / 级联 =====")
check("F1 sparkProfiler 新条目（问题+机制+双层修复+验证锚点）",
      "sparkProfiler" in faq and "创建新世界时闪退" in faq
      and "[Amethyst] Task106: blocked dlopen" in faq
      and "已签名库重标签必死" in faq)
check("F2 FAQ 计数 33→34（itemsByCategory 含 sparkProfiler）",
      faq.count("= [[LauncherHelpFaqItem alloc] init]") == 34 and "sodiumGlsl, sparkProfiler ]" in faq)
check("F3 fpsUnlock 判读修正（呈现常数 + bundle-direct + 相位计时报文）",
      "Task106 判读修正" in faq and "bundle-direct present engaged" in faq
      and "t=swap" in faq and "MC-side" in faq)
check("F4 version.h REVISION 17 addendum (Task 106, no bump)",
      "REVISION 17 addendum (Task 106, no bump)" in vh
      and "libasyncProfiler" in vh and "bundle-direct present" in vh)
r = subprocess.run(["python3", os.path.join(SCRIPTS, "task103_syntax_swap.py")],
                   capture_output=True, text=True)
check("F5 task103_syntax_swap 语法门（含 Task106 桩）", r.returncode == 0 and "syntax OK" in r.stdout,
      r.stdout[-150:] + r.stderr[-150:])
r = subprocess.run(["bash", os.path.join("/home/z/my-project/scripts", "task83_syntax_osm.sh")],
                   capture_output=True, text=True)
check("F6 task83_syntax_osm 语法门（含 osm_render_window_t/mach 桩）",
      r.returncode == 0 and "syntax OK" in r.stdout, r.stdout[-150:] + r.stderr[-150:])
for v in ("verify_task100.py", "verify_task103.py", "verify_task104.py", "verify_task105.py"):
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, v)],
                       capture_output=True, text=True, timeout=600)
    summary = [ln for ln in r.stdout.splitlines() if "RESULT" in ln or "结果" in ln]
    tail = summary[-1] if summary else r.stdout[-120:]
    m = re.search(r"(\d+)\s*FAIL", tail)
    zero_fail = (m is not None and int(m.group(1)) == 0) or "ALL PASS" in tail
    ok = r.returncode == 0 and zero_fail
    check(f"F7 级联 {v}", ok, tail)

print(f"\nRESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
sys.exit(0 if FAIL == 0 else 1)
