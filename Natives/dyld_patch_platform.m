#import <Foundation/Foundation.h>
#include <libgen.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <sys/mman.h>
#include <sys/stat.h>

// Task 106：LC_SOURCE_VERSION（cmd 0x2A，struct {cmd,cmdsize,version,-sdk}）
// 恰好 16 字节，与 linkedit_data_command（LC_CODE_SIGNATURE）同尺寸。
// dyld 对它只做元数据记录、无任何校验语义——是中和签名的等尺寸安全替身。
#define kAme106LCSourceVersion 0x2A

extern int dyld_get_active_platform();

// Rewrite an LC_(LOAD|WEAK)_DYLIB install name in place. The replacement must
// fit in the original load command's string buffer.
static void PLRewriteDylibName(struct dylib_command *dylib, const char *newName) {
    char *dylibName = (void *)dylib + dylib->dylib.name.offset;
    size_t bufLen = dylib->cmdsize - dylib->dylib.name.offset;
    size_t nameLen = strlen(newName);
    if (nameLen + 1 > bufLen) return;
    memcpy(dylibName, newName, nameLen + 1);
    memset(dylibName + nameLen + 1, 0, bufLen - nameLen - 1);
}

static BOOL PLPatchMachOPlatformForSlice(const char *path, struct mach_header_64 *header) {
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    BOOL retagged = NO;
    struct linkedit_data_command *sigCmd = NULL;

    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds; i++) {
        if (command->cmd == LC_BUILD_VERSION) {
            struct build_version_command *buildver = (struct build_version_command *)command;
            int activePlatform = dyld_get_active_platform();
            if (buildver->platform == activePlatform) return NO; // it is already set, stop
            buildver->platform = activePlatform; // set to current platform
            retagged = YES;
        } else if (command->cmd == LC_LOAD_DYLIB || command->cmd == LC_LOAD_WEAK_DYLIB) {
            struct dylib_command *dylib = (struct dylib_command *)command;
            char *dylibName = (void *)dylib + dylib->dylib.name.offset;
            char *verPtr = strstr(dylibName, "/Versions/");
            if (verPtr) {
                // Remove "/Versions/X"
                int lastComponentLen = strlen(dylibName) - (verPtr - dylibName) - 11;
                memmove(verPtr, verPtr + 11, lastComponentLen);
                verPtr[lastComponentLen] = '\0';
            }
            // Redirect macOS-only umbrella frameworks to iOS equivalents.
            // Cocoa/AppKit don't exist on iOS, which makes dlopen fail even
            // after the platform retag above. libjcocoa (java-objc-bridge,
            // pulled in by Minecraft's MacosUtil) links Cocoa but only uses
            // Foundation symbols eagerly; everything AppKit is resolved at
            // runtime via objc_getClass, whose nil results are harmless.
            // UIKit exists on iOS and its path has the exact same length as
            // the stripped Cocoa path, so it always fits in place.
            if (strstr(dylibName, "Cocoa.framework") || strstr(dylibName, "AppKit.framework")) {
                PLRewriteDylibName(dylib, "/System/Library/Frameworks/UIKit.framework/UIKit");
            }
        } else if (command->cmd == LC_CODE_SIGNATURE) {
            // Task 106：记录签名命令——平台重标签后签名哈希必然失效，
            // 已签名库会被 dyld 直接杀进程（spark libasyncProfiler 实锤）。
            sigCmd = (struct linkedit_data_command *)command;
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }

    // Task 106（签名中和）：仅在本切片确实发生了平台重标签时执行——
    // 把 LC_CODE_SIGNATURE 原位改写为等尺寸的 LC_SOURCE_VERSION，并把
    // 指向的签名字节块清零。dyld 由此把该库视为“未签名”而不是“签名失效”：
    // 本设备/越狱环境的未签名 home 目录库历来可正常加载（进程的宽松
    // 代码签名策略），而签名失效 = 必死。零字节块留在 __LINKEDIT 尾部
    // 无引用无害；其余切片（x86_64）不受影响。
    if (retagged && sigCmd != NULL) {
        uint8_t *sliceBase = (uint8_t *)header;
        sigCmd->cmd = kAme106LCSourceVersion;
        if (sigCmd->dataoff != 0 && sigCmd->datasize != 0) {
            memset(sliceBase + sigCmd->dataoff, 0, sigCmd->datasize);
        }
    }
    return YES;
}


BOOL PLPatchMachOPlatformForFile(const char *path) {
    int fd = open(path, O_RDWR, (mode_t)0600);
    if (fd == -1) return NO;
    struct stat s;
    fstat(fd, &s);

    void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (!map) {
        close(fd);
        return NO;
    }

    BOOL patched = NO;
    uint32_t magic = *(uint32_t *)map;
    if (magic == FAT_CIGAM) {
        // Find compatible slice
        struct fat_header *header = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
        for (int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
            if (OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                NSLog(@"[Amethyst] Patching %s", path);
                patched |= PLPatchMachOPlatformForSlice(path, (struct mach_header_64 *)(map + OSSwapInt32(arch->offset)));
            }
            arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
        }
    } else if (magic == MH_MAGIC_64 && ((struct mach_header_64 *)map)->cputype == CPU_TYPE_ARM64) {
        patched = PLPatchMachOPlatformForSlice(path, (struct mach_header_64 *)map);
    }

    if (patched) msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
    return patched;
}
