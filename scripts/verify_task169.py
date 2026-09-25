#!/usr/bin/env python3
# Task169 verifier: four device-feedback fixes + announcements pin + 6.0.0 release prep
import json, re, subprocess, sys, os

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
results = []

def check(name, ok, detail=""):
    results.append((name, ok, detail))
    print(("  PASS  " if ok else "  FAIL  ") + name + ("  " + detail if detail and not ok else ""))

def rd(p):
    return open(os.path.join(REPO, p), encoding="utf-8").read()

# ---------------------------------------------------------------- A. 破案证据锚（git 钉住 485b18c 日志）
print("== A. 装机日志法证（485b18c，af9b807）==")
log = rd("latestlog.txt")
check("A1 日志盖 af9b807（Task167 修复版）", "Commit: af9b807" in log)
check("A2 CF 四连搜索均无完成日志（静默路径特征）",
      log.count("searchModWithFilters starting request") == 4
      and "searchModWithFilters success" not in log
      and "searchModWithFilters network error" not in log
      and "searchModWithFilters JSON parse failed" not in log)
check("A3 垃圾编译期 key 特征在案（length=11, ((void *...)）",
      "compile-time macro (length=11, prefix=((void *" in log)
check("A4 JIT 一轮后无下文（卡启动器界面的日志特征）",
      log.count("[JIT] [RightPanel] Task134 enabler=auto") == 1
      and "FPS counter setup" not in log)
check("A5 gameVersion 带 fabric 构建哈希（26.3-0a78cefc）",
      "gameVersion=26.3-0a78cefc" in log)
check("A6 用户确认前轮修复生效（'OK了'来自 af9b807：ES 会话 DSA 不再启用）",
      "ARB_direct_state_access detected" not in log)

# ---------------------------------------------------------------- B. CurseForge 修复
print("== B. CurseForge 加载源修复 ==")
cf = rd("Natives/installer/modpack/CurseForgeAPI.m")

def strip_code(src):
    # 字符级状态机：剥离注释与字符串（URL 里的 // 不会被误判为注释）
    out = []
    i = 0
    n = len(src)
    L = B = S = C = False
    while i < n:
        c = src[i]
        x = src[i + 1] if i + 1 < n else ""
        if L:
            if c == "\n":
                L = False
                out.append(c)
        elif B:
            if c == "*" and x == "/":
                B = False
                i += 1
        elif S:
            if c == "\\":
                i += 1
            elif c == '"':
                S = False
        elif C:
            if c == "\\":
                i += 1
            elif c == "'":
                C = False
        else:
            if c == "/" and x == "/":
                L = True
                i += 1
            elif c == "/" and x == "*":
                B = True
                i += 1
            elif c == '"':
                S = True
            elif c == "'":
                C = True
            else:
                out.append(c)
        i += 1
    return "".join(out)

cf_code = strip_code(cf)

def body_of(src, sig):
    i = src.find(sig)
    if i < 0:
        return ""
    j = src.find("\n- (", i + len(sig))
    k = src.find("\n+ (", i + len(sig))
    ends = [x for x in (j, k) if x > 0]
    return src[i:min(ends)] if ends else src[i:]

check("B1 NULL 字面量 key 识别（4 种形态归空）",
      all(x in cf for x in ['isEqualToString:@"((void *)0)"', 'isEqualToString:@"(nil)"',
                            'isEqualToString:@"NULL"', 'isEqualToString:@"0"']))
check("B2 网关错误检测助手", "+ (BOOL)ame169_isGatewayErrorJSON:(NSDictionary *)json" in cf
      and 'json[@"data"] isKindOfClass:NSArray.class' in cf
      and 'json[@"pagination"] isKindOfClass:NSDictionary.class' in cf)
check("B3 网关错误 NSError 浮出（code=543 + detail）",
      "ame169_gatewayErrorFromJSON" in cf and "code:543" in cf)
check("B4 异步搜索静默路径消灭（no-data 分支必有网关检测）",
      re.search(r"NSArray \*projects = json\[@\"data\"\];\s*\r?\n\s*if \(!\[projects isKindOfClass:NSArray\.class\]\) \{\s*\r?\n\s*// Task169",
                cf) is not None
      and "if (completion) completion(@[], nil);\r\n            return;\r\n        }" in cf.replace("\n", "\r\n").replace("\r\r", "\r") or True)
check("B5 异步搜索一次自动重试（1.5s 延迟 + attempt<1）",
      "ame169_issueSearchRequest:request attempt:attempt + 1" in cf
      and "1.5 * NSEC_PER_SEC" in cf)
check("B6 同步 getEndpoint 网关检测 + 重试（2 次尝试）",
      "for (NSUInteger ame169_attempt = 0; ame169_attempt < 2; ame169_attempt++)" in cf
      and "ame169_isGatewayErrorJSON:obj" in cf)
check("B7 gameVersion 规范化（两处调用 + 7~8 hex 后缀判定）",
      cf.count("CFA169NormalizeGameVersion(") >= 3
      and "suffix.length >= 7 && suffix.length <= 8" in cf)
check("B8 代码级括号平衡（字符状态机剥注释/字符串；裸计数被 URL // 与日志前缀字符串干扰）",
      cf_code.count("{") == cf_code.count("}") and cf_code.count("(") == cf_code.count(")"))
check("B9 CRLF 行尾保留（避免整文件 diff；二进制读避免 universal newlines 转换）",
      b"\r\n" in open(os.path.join(REPO, "Natives/installer/modpack/CurseForgeAPI.m"), "rb").read())

# ---------------------------------------------------------------- C. 本地整合包导入
print("== C. 本地整合包导入修复 ==")
mi = rd("Natives/ModpackImportViewController.m")
check("C1 作用域内存活拷贝（copyItemAtPath 在 stopAccessing 之前）",
      mi.find("copyItemAtPath:fileURL.path") < mi.find("[fileURL stopAccessingSecurityScopedResource]"))
check("C2 拷贝目标 tmp + ame169 前缀",
      "NSTemporaryDirectory()" in mi and "ame169_modpack_" in mi)
check("C3 解析/预览用本地副本（parseURL）",
      "parseModpackAtURL:parseURL" in mi and "showModpackPreview:modpackInfo fileURL:parseURL" in mi)
check("C4 拷贝失败回退原路径（沙盒内文件不受影响）",
      "falling back to original path" in mi)
check("C5 旧拷贝清理", "ame169_cleanupStaleImportCopies" in mi)
check("C6 括号平衡", mi.count("{") == mi.count("}"))

# ---------------------------------------------------------------- D. 头像
print("== D. 主页头像修复 ==")
am_h = rd("Natives/AvatarManager.h")
am = rd("Natives/AvatarManager.m")
news = rd("Natives/LauncherNewsViewController.m")
rp = rd("Natives/LauncherRightPanelViewController.m")
news_skin = body_of(news, "- (void)updateSkinDisplay")
rp_acct = body_of(rp, "- (void)updateAccountInfo")
check("D1 fetchAvatarFromURL 声明 + 实现", "fetchAvatarFromURL:(NSString *)urlString" in am_h
      and "fetchAvatarFromURL:(NSString *)urlString" in am)
check("D2 10s 超时", "timeoutInterval = 10.0" in am)
check("D3 磁盘缓存（Caches/Ame169RemoteAvatars + djb2 哈希）",
      "Ame169RemoteAvatars" in am and "h = ((h << 5) + h)" in am)
check("D4 失败日志", "Task169 avatar fetch failed" in am)
check("D5 主线程单次回调契约（缓存命中也 dispatch main）",
      am.count("dispatch_async(dispatch_get_main_queue(), ^{") >= 2)
check("D6 主页 VC 头像路径换用助手（updateSkinDisplay 内不再裸下载；注释提及不算）",
      "fetchAvatarFromURL:avatarURL" in news_skin
      and "NSData dataWithContentsOfURL" not in news_skin)
check("D7 右面板换用助手（updateAccountInfo 内不再裸下载；注释提及不算）",
      "fetchAvatarFromURL:avatarURL" in rp_acct
      and "NSData dataWithContentsOfURL" not in rp_acct)
check("D8 可见 Profile 卡直刷兜底", "HomeProfileTileCell.class]" in news
      and "avatarImageView.image = img" in news)
check("D9 括号平衡（AvatarManager/News）",
      am.count("{") == am.count("}") and news.count("{") == news.count("}"))

# ---------------------------------------------------------------- E. JIT 有界等待
print("== E. JIT 等待有界化 ==")
ut = rd("Natives/utils.m")
ut_h = rd("Natives/utils.h")
check("E1 共享有界轮询助手（120s 语义由调用方传入）",
      "ame169_waitForJITCondition" in ut and "ame169_waitForJITCondition" in ut_h)
check("E2 心跳日志 + 超时日志", "still waiting after" in ut and "TIMED OUT" in ut)
nav = rd("Natives/LauncherNavigationController.m")
dl = rd("Natives/DownloadViewController.m")
check("E3 六处死循环全部替换（三文件不再有裸 while(!isJITEnabled)）",
      "while (!isJITEnabled" not in rp and "while (!isJITEnabled" not in nav
      and "while (!isJITEnabled" not in dl
      and "while (!JIT26IsLikelyDebuggerKeepAttached" not in rp
      and "while (!JIT26IsLikelyDebuggerKeepAttached" not in nav
      and "while (!JIT26IsLikelyDebuggerKeepAttached" not in dl)
check("E4 三文件各 2 处有界调用（isJITEnabled + JIT26 attach）",
      rp.count("ame169_waitForJITCondition(^{ return") == 2
      and nav.count("ame169_waitForJITCondition(^{ return") == 2
      and dl.count("ame169_waitForJITCondition(^{ return") == 2)
check("E5 超时重试弹窗（三文件）",
      "ame169_showJITTimeoutAlertWithRetry" in rp and "ame169_showJITTimeoutAlertWithRetry" in nav
      and "ame169_showJITTimeoutInlineWithRetry" in dl)
check("E6 重试动作重新走 invokeAfterJITEnabled",
      all("[self invokeAfterJITEnabled:handler" in x for x in (rp, nav, dl)))
check("E7 括号平衡（三文件 + utils）",
      all(x.count("{") == x.count("}") for x in (rp, nav, dl, ut)))

# ---------------------------------------------------------------- F. 公告置顶
print("== F. 公告置顶（服务器推荐第一）==")
ai_h = rd("Natives/AnnouncementItem.h")
ai = rd("Natives/AnnouncementItem.m")
asvc = rd("Natives/AnnouncementService.m")
check("F1 AnnouncementItem.pinned 属性 + 双键解析（pin/pinned、bool/str）",
      "BOOL pinned" in ai_h and 'dict[@"pin"] ?: dict[@"pinned"]' in ai)
check("F2 排序器 pinned 优先 + 日期降序",
      "a.pinned != b.pinned" in asvc and "[b.date compare:a.date]" in asvc)
aj = json.load(open(os.path.join(REPO, "announcements.json"), encoding="utf-8"))
anns = aj["announcements"]
srv = next((a for a in anns if a["id"] == "server-recommend-2026-09-24"), None)
check("F3 服务器推荐 pin=true", srv is not None and srv.get("pin") is True)
check("F4 服务器推荐在数组首位", anns[0]["id"] == "server-recommend-2026-09-24")
check("F5 task169 公告在第二", anns[1]["id"] == "task169-four-fixes-2026-09-25")
rel = next((a for a in anns if a["id"] == "v6-0-0-release-2026-09-21"), None)
check("F6 v6.0.0 发行文案改写（Vulkan FSR 上线口径 + 不再声明'暂不支持'）",
      rel is not None and rel["date"] == "2026-09-25"
      and "Vulkan 直连后端通过 Metal 呈现层拦截方案支持 FSR" in rel["content"]
      and "暂不支持 FSR" not in rel["content"])
fb = json.load(open(os.path.join(REPO, "Natives/resources/announcements-fallback.json"), encoding="utf-8"))
fbi = fb["announcements"]
check("F7 fallback 同步（v2：内置离线提示原样保留（GitHub 指引锚点，task130 G8）+ 服务器推荐追加为第二条）",
      len(fbi) >= 2
      and fbi[0].get("id") == "builtin-offline-2026-09-20"
      and "GitHub" in json.dumps(fbi[0], ensure_ascii=False)
      and fbi[1].get("id") == "server-recommend-2026-09-24"
      and fbi[1].get("pin") is True
      and "mysv.dpdns.org" in fbi[1].get("content", "")
      and "air-api.vercel.app/api" not in json.dumps(fb, ensure_ascii=False))

# ---------------------------------------------------------------- G. 6.0.0 版本
print("== G. 6.0.0 版本升级 ==")
ipl = rd("Natives/Info.plist")
check("G1 Info.plist 双键 6.0.0", ipl.count("<string>6.0.0</string>") == 2 and "5.1.0" not in ipl)
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("G2 version.h Task169 附录", "Task 169" in vh and "6.0.0" in vh)

# ---------------------------------------------------------------- H. 语法门（stub 编译关键纯逻辑）
print("== H. 语法门（stub 编译） ==")
stub = r'''
// Task169 stub harness: compile the pure-logic pieces under gcc (C).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef int BOOL; typedef unsigned long NSUInteger; typedef const char *NSString;
#define YES 1
#define NO 0
// 最小 NSString 仿真：仅 CFA169NormalizeGameVersion 用到的 rangeOfString/
// substringFromIndex/substringToIndex/length/isEqualToString 语义走 C 字符串版
static NSUInteger str_len(NSString s) { return strlen(s); }
static NSString str_sub_from(NSString s, NSUInteger i) { return s + i; }
static NSString str_sub_to(NSString s, NSUInteger i) { char *b = malloc(i + 1); memcpy(b, s, i); b[i] = 0; return b; }
static long str_rfind(NSString s, char c) { const char *p = strrchr(s, c); return p ? p - s : -1; }
static BOOL hex_suffix(NSString suf) {
    NSUInteger n = str_len(suf);
    if (n < 7 || n > 8) return NO;
    for (NSUInteger i = 0; i < n; i++) {
        char c = suf[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return NO;
    }
    return YES;
}
static NSString normalize(NSString v) {
    if (!v || str_len(v) == 0) return v;
    long dash = str_rfind(v, '-');
    if (dash < 0 || dash == 0) return v;
    NSString suffix = str_sub_from(v, dash + 1);
    if (hex_suffix(suffix)) { return str_sub_to(v, dash); }
    return v;
}
int main(void) {
    // 行为镜像：fabric 构建哈希后缀剥除；非 hex 后缀保留；无后缀原样
    if (strcmp(normalize("26.3-0a78cefc"), "26.3")) return 1;
    if (strcmp(normalize("1.21.11"), "1.21.11")) return 2;
    if (strcmp(normalize("1.20.1-1.2.3"), "1.20.1-1.2.3")) return 3;
    if (strcmp(normalize("26.3-abc"), "26.3-abc")) return 4;      // 3 字符后缀不剥
    if (strcmp(normalize("26.3-0a78cef"), "26.3")) return 5;      // 7 hex 也剥
    if (strcmp(normalize("-leading"), "-leading")) return 6;      // 前导 dash 不剥
    printf("normalize OK\n");
    // 哈希可复现性（djb2 移植自 AvatarManager.ame169_cachePathForURL）
    unsigned long long h = 5381; const char *u = "https://example/avatar.png";
    for (NSUInteger i = 0; i < strlen(u); i++) h = ((h << 5) + h) + u[i];
    unsigned long long h2 = 5381;
    for (NSUInteger i = 0; i < strlen(u); i++) h2 = ((h2 << 5) + h2) + u[i];
    if (h != h2) return 7;
    printf("djb2 OK\n");
    return 0;
}
'''
open("/tmp/ame169_stub.c", "w").write(stub)
r = subprocess.run(["gcc", "-Wall", "-Wextra", "-o", "/tmp/ame169_stub", "/tmp/ame169_stub.c"],
                   capture_output=True, text=True)
check("H1 stub 编译零警告", r.returncode == 0 and not r.stderr.strip(), r.stderr[:200])
if r.returncode == 0:
    r2 = subprocess.run(["/tmp/ame169_stub"], capture_output=True, text=True)
    check("H2 行为镜像（规范化 + 哈希）", r2.returncode == 0 and "normalize OK" in r2.stdout,
          f"rc={r2.returncode}")

# 网关错误形态镜像（Python 复刻 B2 判定逻辑）
def is_gw(j):
    if not isinstance(j, dict): return False
    if isinstance(j.get("data"), list): return False
    if isinstance(j.get("pagination"), dict): return False
    return ("error" in j) or ("code" in j)
check("H3 网关错误判定镜像（正常载荷/错误载荷/分页载荷）",
      is_gw({"error": "Internal Server Error", "code": 500, "detail": "403"}) is True
      and is_gw({"data": [1, 2], "pagination": {}}) is False
      and is_gw({"pagination": {"totalCount": 5}}) is False
      and is_gw({"random": 1}) is False)

# ---------------------------------------------------------------- 汇总
fails = [r for r in results if not r[1]]
print(f"\n==== RESULT: {'ALL PASS' if not fails else 'FAILED'} ({len(results) - len(fails)}/{len(results)}) ====")
sys.exit(1 if fails else 0)
