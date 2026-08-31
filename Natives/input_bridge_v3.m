/*
 * V3 input bridge implementation.
 *
 * Status:
 * - Active development
 * - Works with some bugs:
 *  + Modded versions gives broken stuff..
 */

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "SurfaceViewController.h"

#include <assert.h>
#include <dlfcn.h>
#include <libgen.h>
#include <stdlib.h>
#include <stdatomic.h>

#include "jni.h"
#include "glfw_keycodes.h"
#include "ios_uikit_bridge.h"
#include "utils.h"

#include "JavaLauncher.h"

// SDL3 event injection via dlsym — used when GLFW callbacks are NULL (MC 26.3)
// Only SDL_PushEvent and SDL_GetWindowID are exported from libSDL3.dylib.
// Internal functions like SDL_SendMouseMotion are NOT exported, so we construct
// SDL_Event structs and push them directly.
//
// We cannot #include <SDL3/SDL_events.h> from the Natives build, so we define
// the minimal constants and structs we need inline.

// SDL3 event type constants (from SDL_events.h)
#define SDL3_EVENT_KEY_DOWN        0x300
#define SDL3_EVENT_KEY_UP          0x301
#define SDL3_EVENT_MOUSE_MOTION    0x400
#define SDL3_EVENT_MOUSE_BUTTON_DOWN 0x401
#define SDL3_EVENT_MOUSE_BUTTON_UP   0x402
#define SDL3_EVENT_MOUSE_WHEEL     0x403

typedef uint32_t SDL3_WindowID;
typedef uint32_t SDL3_MouseID;
typedef uint16_t SDL3_Keymod;
typedef int      SDL3_Scancode;
typedef uint32_t SDL3_Keycode;

// SDL3 MouseMotionEvent layout (must match SDL3 ABI exactly)
typedef struct {
    uint32_t type;
    uint32_t reserved;
    uint64_t timestamp;
    SDL3_WindowID windowID;
    SDL3_MouseID which;
    uint32_t state;
    float x, y;
    float xrel, yrel;
} SDL3_MouseMotionEvent;

// SDL3 MouseButtonEvent layout
typedef struct {
    uint32_t type;
    uint32_t reserved;
    uint64_t timestamp;
    SDL3_WindowID windowID;
    SDL3_MouseID which;
    uint8_t button;
    bool down;
    uint8_t clicks;
    uint8_t padding;
    float x, y;
} SDL3_MouseButtonEvent;

// SDL3 MouseWheelEvent layout
typedef struct {
    uint32_t type;
    uint32_t reserved;
    uint64_t timestamp;
    SDL3_WindowID windowID;
    SDL3_MouseID which;
    float x, y;
    uint32_t direction;
    float mouse_x, mouse_y;
    int32_t integer_x, integer_y;
} SDL3_MouseWheelEvent;

// SDL3 KeyboardEvent layout
typedef struct {
    uint32_t type;
    uint32_t reserved;
    uint64_t timestamp;
    SDL3_WindowID windowID;
    uint32_t which;
    SDL3_Scancode scancode;
    SDL3_Keycode key;
    SDL3_Keymod mod;
    uint16_t raw;
    bool down;
    bool repeat;
} SDL3_KeyboardEvent;

// Union large enough to hold any SDL3 event
typedef union {
    uint32_t type;
    char _padding[128];
} SDL3_Event;

typedef bool SDL_PushEvent_func(void *event);
typedef uint32_t SDL_GetWindowID_func(void *window);
typedef bool SDL_HideCursor_func(void);
typedef bool SDL_ShowCursor_func(void);

static SDL_PushEvent_func     *pSDL_PushEvent     = NULL;
static SDL_GetWindowID_func   *pSDL_GetWindowID   = NULL;
static void *g_sdlWindow = NULL;  // The real SDL3 window pointer

static void initSDLEventFuncs(void) {
    static BOOL inited = NO;
    if (inited) return;
    inited = YES;
    pSDL_PushEvent   = dlsym(RTLD_DEFAULT, "SDL_PushEvent");
    pSDL_GetWindowID = dlsym(RTLD_DEFAULT, "SDL_GetWindowID");
    NSLog(@"[InputDiag] initSDLEventFuncs: PushEvent=%p GetWindowID=%p g_sdlWindow=%p",
        (void*)pSDL_PushEvent, (void*)pSDL_GetWindowID, g_sdlWindow);
}

// Called from UIKit_CreateWindow to register the real SDL window
void Amethyst_SetSDLWindow(void *window) {
    g_sdlWindow = window;
    // Re-init in case libSDL3.dylib wasn't loaded at JNI_OnLoad time
    initSDLEventFuncs();
    NSLog(@"[InputDiag] Amethyst_SetSDLWindow: %p PushEvent=%p", window, (void*)pSDL_PushEvent);
}

static SDL3_WindowID getSDLWindowID(void) {
    if (g_sdlWindow && pSDL_GetWindowID) {
        return pSDL_GetWindowID(g_sdlWindow);
    }
    return 0;
}

// Push a mouse motion event into SDL's event queue
static void pushSDLMouseMotion(float x, float y, float xrel, float yrel) {
    if (!pSDL_PushEvent || !g_sdlWindow) return;
    SDL3_MouseMotionEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = SDL3_EVENT_MOUSE_MOTION;
    ev.windowID = getSDLWindowID();
    ev.which = 0;
    ev.state = 0;
    ev.x = x;
    ev.y = y;
    ev.xrel = xrel;
    ev.yrel = yrel;
    pSDL_PushEvent((void*)&ev);
}

// Push a mouse button event into SDL's event queue
// sdlButton: 1=left, 2=middle, 3=right (SDL convention)
static void pushSDLMouseButton(uint8_t sdlButton, bool down, float x, float y) {
    if (!pSDL_PushEvent || !g_sdlWindow) return;
    SDL3_MouseButtonEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = down ? SDL3_EVENT_MOUSE_BUTTON_DOWN : SDL3_EVENT_MOUSE_BUTTON_UP;
    ev.windowID = getSDLWindowID();
    ev.which = 0;
    ev.button = sdlButton;
    ev.down = down;
    ev.clicks = 1;
    ev.x = x;
    ev.y = y;
    pSDL_PushEvent((void*)&ev);
}

// Push a keyboard event into SDL's event queue
static void pushSDLKeyboardEvent(SDL3_Scancode scancode, bool down) {
    if (!pSDL_PushEvent || !g_sdlWindow) return;
    SDL3_KeyboardEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = down ? SDL3_EVENT_KEY_DOWN : SDL3_EVENT_KEY_UP;
    ev.windowID = getSDLWindowID();
    ev.which = 0;
    ev.scancode = scancode;
    ev.key = 0;
    ev.mod = 0;
    ev.down = down;
    ev.repeat = false;
    pSDL_PushEvent((void*)&ev);
}

// Push a mouse wheel event into SDL's event queue
static void pushSDLMouseWheel(float x, float y) {
    if (!pSDL_PushEvent || !g_sdlWindow) return;
    SDL3_MouseWheelEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = SDL3_EVENT_MOUSE_WHEEL;
    ev.windowID = getSDLWindowID();
    ev.which = 0;
    ev.x = x;
    ev.y = y;
    ev.direction = 0;
    ev.mouse_x = cursorX;
    ev.mouse_y = cursorY;
    ev.integer_x = (int32_t)x;
    ev.integer_y = (int32_t)y;
    pSDL_PushEvent((void*)&ev);
}

// GLFW keycode → SDL_Scancode conversion
static int glfwKeyToSDLScancode(int glfwKey) {
    // Printable keys: ASCII-based, same as USB HID usage
    if (glfwKey >= GLFW_KEY_A && glfwKey <= GLFW_KEY_Z) return 4 + (glfwKey - GLFW_KEY_A);   // SDL_SCANCODE_A=4
    if (glfwKey >= GLFW_KEY_0 && glfwKey <= GLFW_KEY_9) return 39 + (glfwKey - GLFW_KEY_0);   // SDL_SCANCODE_0=39
    if (glfwKey >= GLFW_KEY_F1 && glfwKey <= GLFW_KEY_F25) return 58 + (glfwKey - GLFW_KEY_F1); // SDL_SCANCODE_F1=58
    if (glfwKey >= GLFW_KEY_NUMPAD_0 && glfwKey <= GLFW_KEY_NUMPAD_9) return 98 + (glfwKey - GLFW_KEY_NUMPAD_0);
    switch (glfwKey) {
        case GLFW_KEY_SPACE:           return 44;
        case GLFW_KEY_APOSTROPHE:      return 52;
        case GLFW_KEY_COMMA:           return 54;
        case GLFW_KEY_MINUS:           return 45;
        case GLFW_KEY_PERIOD:          return 55;
        case GLFW_KEY_SLASH:           return 56;
        case GLFW_KEY_SEMICOLON:       return 51;
        case GLFW_KEY_EQUAL:           return 46;
        case GLFW_KEY_LEFT_BRACKET:    return 47;
        case GLFW_KEY_BACKSLASH:       return 49;
        case GLFW_KEY_RIGHT_BRACKET:   return 48;
        case GLFW_KEY_GRAVE_ACCENT:    return 53;
        case GLFW_KEY_ESCAPE:          return 41;
        case GLFW_KEY_ENTER:           return 40;
        case GLFW_KEY_TAB:             return 43;
        case GLFW_KEY_BACKSPACE:       return 42;
        case GLFW_KEY_INSERT:          return 73;
        case GLFW_KEY_DELETE:          return 76;
        case GLFW_KEY_DPAD_RIGHT:      return 79;
        case GLFW_KEY_DPAD_LEFT:       return 80;
        case GLFW_KEY_DPAD_DOWN:       return 81;
        case GLFW_KEY_DPAD_UP:         return 82;
        case GLFW_KEY_PAGE_UP:         return 75;
        case GLFW_KEY_PAGE_DOWN:       return 78;
        case GLFW_KEY_HOME:            return 74;
        case GLFW_KEY_END:             return 77;
        case GLFW_KEY_CAPS_LOCK:       return 57;
        case GLFW_KEY_SCROLL_LOCK:     return 71;
        case GLFW_KEY_NUM_LOCK:        return 83;
        case GLFW_KEY_PRINT_SCREEN:    return 70;
        case GLFW_KEY_PAUSE:           return 72;
        case GLFW_KEY_LEFT_SHIFT:      return 225;
        case GLFW_KEY_LEFT_CONTROL:    return 224;
        case GLFW_KEY_LEFT_ALT:        return 226;
        case GLFW_KEY_LEFT_SUPER:      return 227;
        case GLFW_KEY_RIGHT_SHIFT:     return 229;
        case GLFW_KEY_RIGHT_CONTROL:   return 228;
        case GLFW_KEY_RIGHT_ALT:       return 230;
        case GLFW_KEY_RIGHT_SUPER:     return 231;
        case GLFW_KEY_MENU:            return 101;
        case GLFW_KEY_NUMPAD_ADD:      return 87;
        case GLFW_KEY_NUMPAD_SUBTRACT: return 86;
        case GLFW_KEY_NUMPAD_MULTIPLY: return 85;
        case GLFW_KEY_NUMPAD_DIVIDE:   return 84;
        case GLFW_KEY_NUMPAD_DECIMAL:  return 220;
        case GLFW_KEY_NUMPAD_ENTER:    return 88;
        case GLFW_KEY_NUMPAD_EQUAL:    return 103;
        default:                       return 0; // SDL_SCANCODE_UNKNOWN
    }
}

// SDL button ID mapping: GLFW uses 0-based, SDL uses 1-based
static uint8_t glfwButtonToSDLButton(int glfwButton) {
    switch (glfwButton) {
        case GLFW_MOUSE_BUTTON_LEFT:   return 1; // SDL_BUTTON_LEFT
        case GLFW_MOUSE_BUTTON_RIGHT:  return 3; // SDL_BUTTON_RIGHT
        case GLFW_MOUSE_BUTTON_MIDDLE: return 2; // SDL_BUTTON_MIDDLE
        default:                       return (uint8_t)(glfwButton + 1);
    }
}

jint (*orig_ProcessImpl_forkAndExec)(JNIEnv *env, jobject process, jint mode, jbyteArray helperpath, jbyteArray prog, jbyteArray argBlock, jint argc, jbyteArray envBlock, jint envc, jbyteArray dir, jintArray std_fds, jboolean redirectErrorStream);
jlong (*orig_ProcessHandleImpl_isAlive0)(JNIEnv *env, jclass clazz, jlong jpid);

NSString* processPath(NSString* path) {
    if ([path hasPrefix:@"file:"]) {
        path = [path substringFromIndex:5].stringByRemovingPercentEncoding;
    }
    path = path.stringByResolvingSymlinksInPath;

    NSString *prefix = @"file";
    if ([UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:@"shareddocuments://"]] &&
      ![path hasPrefix:@"/var/mobile/Documents"]) {
        // Prefer opening in Files if containerized
        prefix = @"shareddocuments";
    } else if ([UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:@"filza://"]]) {
        // Open in Filza if installed
        prefix = @"filza";
    } else if ([UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:@"santander://"]]) {
        // Open in Santander if installed
        prefix = @"santander";
    }

    return [NSString stringWithFormat:@"%@://%@", prefix, path];
}

void openURLGlobal(NSString *path) {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([path hasPrefix:@"http"]) {
            openLink(UIWindow.mainWindow.rootViewController, [NSURL URLWithString:path]);
            dispatch_group_leave(group);
            return;
        }
        NSString *realPath = processPath(path);
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:realPath] options:@{} completionHandler:^(BOOL success) {
            if (success) {
                NSLog(@"Opened \"%@\"", realPath);
            } else {
                NSLog(@"Failed to open \"%@\"", realPath);
            }
            dispatch_group_leave(group);
        }];
    });

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

/**
 * Hooked version of java.lang.UNIXProcess.forkAndExec()
 * which is used to handle the "open" command.
 *
 * iOS 沙箱禁止 fork/exec，原生 forkAndExec 必然失败并可能导致进程崩溃。
 * 此处对非 "open" 命令不再透传给原生实现，而是抛出明确的 Java IOException，
 * 让调用方（如 Forge/NeoForge installer.jar 的 processor 步骤）能优雅失败而非原生崩溃。
 * "open" 命令仍走 URL scheme 转发到 Files/Filza 等外部应用。
 */
jint
hooked_ProcessImpl_forkAndExec(JNIEnv *env, jobject process, jint mode, jbyteArray helperpath, jbyteArray prog, jbyteArray argBlock, jint argc, jbyteArray envBlock, jint envc, jbyteArray dir, jintArray std_fds, jboolean redirectErrorStream) {
    char *pProg = (char *)((*env)->GetByteArrayElements(env, prog, NULL));

    // Here we only handle the "open" command
    if (strcmp(basename(pProg), "open")) {
        // 非 "open" 命令：iOS 沙箱禁止 fork/exec，透传给原生实现会导致
        // "Operation not permitted" 或直接崩溃。改为抛 IOException 让上层优雅失败。
        NSLog(@"[input_bridge] Blocked fork/exec of '%s' (iOS sandbox forbids fork/exec)", pProg);
        (*env)->ReleaseByteArrayElements(env, prog, (jbyte *)pProg, 0);
        jclass exClass = (*env)->FindClass(env, "java/io/IOException");
        if (exClass != NULL) {
            (*env)->ThrowNew(env, exClass, "fork/exec not permitted on iOS sandbox");
            (*env)->DeleteLocalRef(env, exClass);
        }
        return -1;
    }

    char *path = (char *)((*env)->GetByteArrayElements(env, argBlock, NULL));
    openURLGlobal(@(path));

    (*env)->ReleaseByteArrayElements(env, prog, (jbyte *)pProg, 0);
    (*env)->ReleaseByteArrayElements(env, argBlock, (jbyte *)path, 0);
    return 0;
}

/**
 * Hooked version of java.lang.ProcessHandleImpl.isAlive0()
 * which is used to ignore "Operation not permitted"
 */
jlong hooked_ProcessHandleImpl_isAlive0(JNIEnv *env, jclass clazz, jlong jpid) {
    jlong result = orig_ProcessHandleImpl_isAlive0(env, clazz, jpid);
    if ((*env)->ExceptionOccurred(env)) {
        (*env)->ExceptionClear(env);
    }
    return result;
}

// Part of awt_bridge
void CTCClipboard_nQuerySystemClipboard(JNIEnv *env, jclass clazz) {
    if(method_SystemClipboardDataReceived == NULL) {
        class_CTCClipboard = (*env)->NewGlobalRef(env, clazz);
        method_SystemClipboardDataReceived = (*env)->GetStaticMethodID(env, clazz, "systemClipboardDataReceived", "(Ljava/lang/String;Ljava/lang/String;)V");
    }
    // From Java_net_kdt_pojavlaunch_AWTInputBridge_nativeClipboardReceived
    // Note: we cannot use main_queue here as it will cause deadlock
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        JNIEnv *env;
        (*runtimeJavaVMPtr)->AttachCurrentThread(runtimeJavaVMPtr, &env, NULL);
        const char* mimeChars = "text/plain";
        (*env)->CallStaticVoidMethod(env, class_CTCClipboard, method_SystemClipboardDataReceived,
            UIKit_accessClipboard(env, CLIPBOARD_PASTE, NULL),
            (*env)->NewStringUTF(env, mimeChars));
        (*runtimeJavaVMPtr)->DetachCurrentThread(runtimeJavaVMPtr);
    });
}

void CTCClipboard_nPutClipboardData(JNIEnv* env, jclass clazz, jstring clipboardData, jstring clipboardDataMime) {
    // TODO: handle non-text data(?)
    UIKit_accessClipboard(env, CLIPBOARD_COPY, clipboardData);
}

void CTCDesktopPeer_openGlobal(JNIEnv *env, jclass clazz, jstring path) {
    const char* stringChars = (*env)->GetStringUTFChars(env, path, NULL);
    openURLGlobal(@(stringChars));
    (*env)->ReleaseStringUTFChars(env, path, stringChars);
}

void registerOpenHandler(JNIEnv *env) {
    jclass cls;

    // Hook forkAndExec
    orig_ProcessImpl_forkAndExec = dlsym(RTLD_DEFAULT, "Java_java_lang_UNIXProcess_forkAndExec");
    if (!orig_ProcessImpl_forkAndExec) {
        orig_ProcessImpl_forkAndExec = dlsym(RTLD_DEFAULT, "Java_java_lang_ProcessImpl_forkAndExec");
        cls = (*env)->FindClass(env, "java/lang/ProcessImpl");
    } else {
        cls = (*env)->FindClass(env, "java/lang/UNIXProcess");
    }
    JNINativeMethod forkAndExecMethod[] = {
        {"forkAndExec", "(I[B[B[BI[BI[B[IZ)I", (void *)&hooked_ProcessImpl_forkAndExec}
    };
    (*env)->RegisterNatives(env, cls, forkAndExecMethod, 1);

    // (Java 17 only) Hook isAlive0
    cls = (*env)->FindClass(env, "java/lang/ProcessHandleImpl");
    if ((*env)->ExceptionOccurred(env)) {
        // Java 8
        (*env)->ExceptionClear(env);
    } else {
        orig_ProcessHandleImpl_isAlive0 = dlsym(RTLD_DEFAULT, "Java_java_lang_ProcessHandleImpl_isAlive0");
        JNINativeMethod isAlive0Method[] = {
            {"isAlive0", "(J)J", (void *)&hooked_ProcessHandleImpl_isAlive0}
        };
        (*env)->RegisterNatives(env, cls, isAlive0Method, 1);
    }

    // Register CTCClipboard natives
    cls = (*env)->FindClass(env, "net/java/openjdk/cacio/ctc/CTCClipboard");
    if ((*env)->ExceptionOccurred(env)) {
        // Java 17
        (*env)->ExceptionClear(env);
        cls = (*env)->FindClass(env, "com/github/caciocavallosilano/cacio/ctc/CTCClipboard");
    }
    JNINativeMethod clipboardMethods[] = {
        {"nQuerySystemClipboard", "()V", (void *)&CTCClipboard_nQuerySystemClipboard},
        {"nPutClipboardData", "(Ljava/lang/String;Ljava/lang/String;)V", (void *)&CTCClipboard_nPutClipboardData}
    };
    (*env)->RegisterNatives(env, cls, clipboardMethods, 2);

    // Register CTCDesktopPeer natives
    cls = (*env)->FindClass(env, "net/java/openjdk/cacio/ctc/CTCDesktopPeer");
    if ((*env)->ExceptionOccurred(env)) {
        // Java 17, not available
        //(*env)->ExceptionDescribe(env);
        (*env)->ExceptionClear(env);
        return;
    }
    JNINativeMethod peerOpenMethods[] = {
        {"openFile", "(Ljava/lang/String;)V", (void *)&CTCDesktopPeer_openGlobal},
        {"openUri", "(Ljava/lang/String;)V", (void *)&CTCDesktopPeer_openGlobal}
    };
    (*env)->RegisterNatives(env, cls, peerOpenMethods, 2);
}

// JNI_OnLoad
void JNI_OnLoadGLFW() {
    if (runtimeJNIEnvPtr == NULL) {
        NSLog(@"[JNI] JNI_OnLoadGLFW: runtimeJNIEnvPtr is NULL, skipping");
        return;
    }
    jclass clazz = (*runtimeJNIEnvPtr)->FindClass(runtimeJNIEnvPtr, "org/lwjgl/glfw/GLFW");
    if (clazz == NULL) {
        if ((*runtimeJNIEnvPtr)->ExceptionOccurred(runtimeJNIEnvPtr)) {
            (*runtimeJNIEnvPtr)->ExceptionDescribe(runtimeJNIEnvPtr);
            (*runtimeJNIEnvPtr)->ExceptionClear(runtimeJNIEnvPtr);
        }
        NSLog(@"[JNI] JNI_OnLoadGLFW: FindClass(org/lwjgl/glfw/GLFW) returned NULL, skipping registration");
        return;
    }
    vmGlfwClass = (*runtimeJNIEnvPtr)->NewGlobalRef(runtimeJNIEnvPtr, clazz);
    method_internalWindowSizeChanged = (*runtimeJNIEnvPtr)->GetStaticMethodID(runtimeJNIEnvPtr, vmGlfwClass, "internalWindowSizeChanged", "(JII)V");
    if ((*runtimeJNIEnvPtr)->ExceptionOccurred(runtimeJNIEnvPtr)) {
        (*runtimeJNIEnvPtr)->ExceptionDescribe(runtimeJNIEnvPtr);
        (*runtimeJNIEnvPtr)->ExceptionClear(runtimeJNIEnvPtr);
        method_internalWindowSizeChanged = NULL;
    }
    jfieldID field_keyDownBuffer = (*runtimeJNIEnvPtr)->GetStaticFieldID(runtimeJNIEnvPtr, vmGlfwClass, "keyDownBuffer", "Ljava/nio/ByteBuffer;");
    if ((*runtimeJNIEnvPtr)->ExceptionOccurred(runtimeJNIEnvPtr)) {
        (*runtimeJNIEnvPtr)->ExceptionDescribe(runtimeJNIEnvPtr);
        (*runtimeJNIEnvPtr)->ExceptionClear(runtimeJNIEnvPtr);
        field_keyDownBuffer = NULL;
    }
    if (field_keyDownBuffer != NULL) {
        jobject keyDownBufferJ = (*runtimeJNIEnvPtr)->GetStaticObjectField(runtimeJNIEnvPtr, vmGlfwClass, field_keyDownBuffer);
        if (keyDownBufferJ != NULL) {
            keyDownBuffer = (*runtimeJNIEnvPtr)->GetDirectBufferAddress(runtimeJNIEnvPtr, keyDownBufferJ);
        }
    }
    NSLog(@"[JNI] JNI_OnLoadGLFW registered, class=%p, method=%p, keyDownBuffer=%p", (void *)vmGlfwClass, (void *)method_internalWindowSizeChanged, (void *)keyDownBuffer);
}

jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    runtimeJavaVMPtr = vm;

    // Initialize SDL3 event function pointers for MC 26.3+ input
    initSDLEventFuncs();

    JNIEnv *env;
    (*runtimeJavaVMPtr)->GetEnv(runtimeJavaVMPtr, (void **)&env, JNI_VERSION_1_4);
    registerOpenHandler(env);
    if (!getenv("POJAV_SKIP_JNI_GLFW")) {
        runtimeJNIEnvPtr = env;
        JNI_OnLoadGLFW();
    }

    return JNI_VERSION_1_4;
}

// Should be?
void JNI_OnUnload(JavaVM* vm, void* reserved) {
    runtimeJNIEnvPtr = NULL;
}

#define ADD_CALLBACK_WWIN(NAME) \
JNIEXPORT jlong JNICALL Java_org_lwjgl_glfw_GLFW_nglfwSet##NAME##Callback(JNIEnv * env, jclass cls, jlong window, jlong callbackptr) { \
    void** oldCallback = (void**) &GLFW_invoke_##NAME; \
    GLFW_invoke_##NAME = (GLFW_invoke_##NAME##_func*) (uintptr_t) callbackptr; \
    return (jlong) (uintptr_t) *oldCallback; \
}

ADD_CALLBACK_WWIN(Char)
ADD_CALLBACK_WWIN(CharMods)
ADD_CALLBACK_WWIN(CursorEnter)
ADD_CALLBACK_WWIN(CursorPos)
ADD_CALLBACK_WWIN(FramebufferSize)
ADD_CALLBACK_WWIN(Key)
ADD_CALLBACK_WWIN(MouseButton)
ADD_CALLBACK_WWIN(Scroll)
ADD_CALLBACK_WWIN(WindowPos)
ADD_CALLBACK_WWIN(WindowSize)

#undef ADD_CALLBACK_WWIN

void handleFramebufferSizeJava(void* window, int w, int h) {
    if(GLFW_invoke_CursorEnter)GLFW_invoke_CursorEnter(window, 1);
    if(GLFW_invoke_WindowPos)GLFW_invoke_WindowPos(window, 0, 0);
    (*runtimeJNIEnvPtr)->CallStaticVoidMethod(runtimeJNIEnvPtr, vmGlfwClass, method_internalWindowSizeChanged, (long)window, w, h);
}

void pojavPumpEvents(void* window) {
    static BOOL setInputReady = NO;
    static int pumpCount = 0;
    if(!setInputReady) {
        setInputReady = YES;
        CallbackBridge_nativeSetInputReady(YES);
        NSLog(@"[InputDiag] pojavPumpEvents: isInputReady set to YES, showingWindow=%p", (void*)showingWindow);
    }
    pumpCount++;

    // Poll SDL relative mouse mode periodically (not just on touch) so cursor
    // hides automatically when entering the map, without needing a touch first.
    if (g_sdlWindow && pumpCount % 30 == 0) {
        typedef bool (*GetRelModeFunc)(void*);
        static GetRelModeFunc getRelMode = NULL;
        static bool inited = false;
        if (!inited) {
            getRelMode = (GetRelModeFunc)dlsym(RTLD_DEFAULT, "SDL_GetWindowRelativeMouseMode");
            inited = true;
        }
        if (getRelMode) {
            bool relMode = getRelMode(g_sdlWindow);
            if (relMode != isGrabbing) {
                BOOL wasGrabbing = isGrabbing;
                isGrabbing = relMode;

                if (!wasGrabbing && relMode) {
                    pushSDLMouseButton(1, false, (float)cursorX, (float)cursorY);
                }

                typedef bool (*VoidFunc)(void);
                static VoidFunc hideCursor = NULL;
                static VoidFunc showCursor = NULL;
                if (!hideCursor) hideCursor = (VoidFunc)dlsym(RTLD_DEFAULT, "SDL_HideCursor");
                if (!showCursor) showCursor = (VoidFunc)dlsym(RTLD_DEFAULT, "SDL_ShowCursor");
                if (relMode && hideCursor) hideCursor();
                else if (!relMode && showCursor) showCursor();

                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        SurfaceViewController *vc = (SurfaceViewController *)UIWindow.mainWindow.rootViewController;
                        if (vc) [vc updateGrabState];
                    } @catch (NSException *e) {}
                });

                NSLog(@"[InputDiag] isGrabbing synced from SDL (pump): %d", isGrabbing);
            }
        }
    }
    if (pumpCount <= 5 || pumpCount % 300 == 0) {
        NSLog(@"[InputDiag] pojavPumpEvents #%d: window=%p GLFW_invoke_Key=%p GLFW_invoke_CursorPos=%p GLFW_invoke_Char=%p isGrabbing=%d isUseStackQueue=%d eventCounter=%d",
            pumpCount, window,
            (void*)GLFW_invoke_Key, (void*)GLFW_invoke_CursorPos, (void*)GLFW_invoke_Char,
            isGrabbing, isUseStackQueueCall,
            (int)atomic_load_explicit(&eventCounter, memory_order_relaxed));
    }
    size_t counter = atomic_load_explicit(&eventCounter, memory_order_acquire);
    if((cLastX != cursorX || cLastY != cursorY) && GLFW_invoke_CursorPos) {
        cLastX = cursorX;
        cLastY = cursorY;
        if (isUseStackQueueCall)
            GLFW_invoke_CursorPos(window, cursorX, cursorY);
    }
    for(size_t i = 0; i < counter; i++) {
        GLFWInputEvent event = events[i];
        switch(event.type) {
            case EVENT_TYPE_CHAR:
                if(GLFW_invoke_Char) GLFW_invoke_Char(window, event.i1);
                break;
            case EVENT_TYPE_CHAR_MODS:
                if(GLFW_invoke_CharMods) GLFW_invoke_CharMods(window, event.i1, event.i2);
                break;
            case EVENT_TYPE_KEY:
                if(GLFW_invoke_Key) GLFW_invoke_Key(window, event.i1, event.i2, event.i3, event.i4);
                break;
            case EVENT_TYPE_MODIFIERS:
                CallbackBridge_syncModifiersToMC(event.i1);
                break;
            case EVENT_TYPE_MOUSE_BUTTON:
                if(GLFW_invoke_MouseButton) GLFW_invoke_MouseButton(window, event.i1, event.i2, event.i3);
                break;
            case EVENT_TYPE_SCROLL:
                if(GLFW_invoke_Scroll) GLFW_invoke_Scroll(window, event.f1, event.f2);
                break;
            case EVENT_TYPE_FRAMEBUFFER_SIZE:
                handleFramebufferSizeJava(window, event.i1, event.i2);
                if(GLFW_invoke_FramebufferSize) GLFW_invoke_FramebufferSize(window, event.i1, event.i2);
                break;
            case EVENT_TYPE_WINDOW_SIZE:
                handleFramebufferSizeJava(window, event.i1, event.i2);
                if(GLFW_invoke_WindowSize) GLFW_invoke_WindowSize(window, event.i1, event.i2);
                break;
        }
    }
    atomic_store_explicit(&eventCounter, counter, memory_order_release);
}
void pojavRewindEvents() {
    atomic_store_explicit(&eventCounter, 0, memory_order_release);
}

JNIEXPORT void JNICALL
Java_org_lwjgl_glfw_GLFW_nglfwGetCursorPos(JNIEnv *env, jclass clazz, jlong window, jobject xpos,
                                          jobject ypos) {
    *(double*)(*env)->GetDirectBufferAddress(env, xpos) = cursorX;
    *(double*)(*env)->GetDirectBufferAddress(env, ypos) = cursorY;
}

JNIEXPORT void JNICALL
Java_org_lwjgl_glfw_GLFW_nglfwGetCursorPosA(JNIEnv *env, jclass clazz, jlong window,
                                            jdoubleArray xpos, jdoubleArray ypos) {
    (*env)->SetDoubleArrayRegion(env, xpos, 0,1, &cursorX);
    (*env)->SetDoubleArrayRegion(env, ypos, 0,1, &cursorY);
}

JNIEXPORT void JNICALL
Java_org_lwjgl_glfw_GLFW_glfwSetCursorPos(JNIEnv *env, jclass clazz, jlong window, jdouble xpos,
                                          jdouble ypos) {
    cLastX = cursorX = xpos;
    cLastY = cursorY = ypos;
}

void sendData(short type, int i1, int i2, short i3, short i4) {
    size_t counter = atomic_load_explicit(&eventCounter, memory_order_acquire);
    if (counter < 7999) {
        GLFWInputEvent *event = &events[counter++];
        event->type = type;
        event->i1 = i1;
        event->i2 = i2;
        event->i3 = i3;
        event->i4 = i4;
    }
    atomic_store_explicit(&eventCounter, counter, memory_order_release);
}

void sendDataFloat(short type, float i1, float i2, short i3, short i4) {
    size_t counter = atomic_load_explicit(&eventCounter, memory_order_acquire);
    if (counter < 7999) {
        GLFWInputEvent *event = &events[counter++];
        event->type = type;
        event->f1 = i1;
        event->f2 = i2;
        event->i3 = i3;
        event->i4 = i4;
    }
    atomic_store_explicit(&eventCounter, counter, memory_order_release);
}

void closeGLFWWindow() {
    NSLog(@"Closing GLFW window");

    /*
    jclass glfwClazz = (*runtimeJNIEnvPtr)->FindClass(runtimeJNIEnvPtr, "org/lwjgl/glfw/GLFW");
    assert(glfwClazz != NULL);
    jmethodID glfwMethod = (*runtimeJNIEnvPtr)->GetStaticMethodID(runtimeJNIEnvPtr, glfwMethod, "glfwSetWindowShouldClose", "(JZ)V");
    assert(glfwMethod != NULL);
    
    (*runtimeJNIEnvPtr)->CallStaticVoidMethod(
        runtimeJNIEnvPtr,
        glfwClazz, glfwMethod,
        (jlong) showingWindow, JNI_TRUE
    );
    */
    exit(-1);
}

const int hotbarKeys[9] = {
    GLFW_KEY_1, GLFW_KEY_2, GLFW_KEY_3,
    GLFW_KEY_4, GLFW_KEY_5, GLFW_KEY_6,
    GLFW_KEY_7, GLFW_KEY_8, GLFW_KEY_9
};
int guiScale = 1;
int mcscale(CGFloat input) {
    return (int)((guiScale * input)/resolutionScale);
}
int callback_SurfaceViewController_touchHotbar(CGFloat x, CGFloat y) {
    // 诊断：物品栏点不动时，靠这段代码一次性定位卡在哪一环。
    // 可能的失败原因互不相关，只看现象无法区分：
    //   1. isGrabbing 恒为 0 —— SDL3 下抓取状态没同步过来（最常见）
    //   2. guiScale 卡在初始值 1 —— mcscale() 把命中区域缩小到约 60x6 像素
    //   3. 传入坐标与 physicalWidth/Height 不同坐标系（rootView vs surfaceView）
    //   4. resolutionScale 异常
    // 限频：每 20 次打印一次，避免触摸时刷屏。
    static int hotbarDiagCount = 0;
    BOOL shouldLog = ((hotbarDiagCount++ % 20) == 0);

    if (isGrabbing == JNI_FALSE) {
        if (shouldLog) {
            NSLog(@"[HotbarDiag] REJECT isGrabbing=0 | x=%.1f y=%.1f | phys=%dx%d guiScale=%d resScale=%.2f sdlWin=%p",
                  x, y, (int)physicalWidth, (int)physicalHeight, guiScale,
                  (double)resolutionScale, g_sdlWindow);
        }
        return -1;
    }

    int barHeight = mcscale(20);
    int barY = physicalHeight - barHeight;
    if (y < barY) {
        if (shouldLog) {
            NSLog(@"[HotbarDiag] REJECT above bar | y=%.1f < barY=%d (barH=%d physH=%d guiScale=%d resScale=%.2f)",
                  y, barY, barHeight, (int)physicalHeight, guiScale, (double)resolutionScale);
        }
        return -1;
    }

    int barWidth = mcscale(180);
    int barX = (physicalWidth / 2) - (barWidth / 2);
    if (x < barX || x >= barX + barWidth) {
        if (shouldLog) {
            NSLog(@"[HotbarDiag] REJECT outside bar | x=%.1f not in [%d,%d) barW=%d physW=%d guiScale=%d resScale=%.2f",
                  x, barX, barX + barWidth, barWidth, (int)physicalWidth, guiScale, (double)resolutionScale);
        }
        return -1;
    }

    int slot = hotbarKeys[(int) MathUtils_map(x, barX, barX + barWidth, 0, 9)];
    if (shouldLog) {
        NSLog(@"[HotbarDiag] HIT slot key=%d | x=%.1f barX=%d barW=%d physW=%d guiScale=%d",
              slot, x, barX, barWidth, (int)physicalWidth, guiScale);
    }
    return slot;
}

JNIEXPORT void JNICALL Java_net_kdt_pojavlaunch_uikit_UIKit_updateMCGuiScale(JNIEnv* env, jclass clazz, jint scale) {
    guiScale = scale;
}

JNIEXPORT jstring JNICALL Java_org_lwjgl_glfw_CallbackBridge_nativeClipboard(JNIEnv* env, jclass clazz, jint action, jstring copySrc) {
    NSDebugLog(@"Debug: Clipboard access is going on\n");
    return UIKit_accessClipboard(env, action, copySrc);
}

JNIEXPORT void JNICALL Java_org_lwjgl_glfw_CallbackBridge_nativeSetGrabbing(JNIEnv* env, jclass clazz, jboolean grabbing, jfloat xset, jfloat yset) {
    isGrabbing = grabbing;

    // Manage SDL cursor visibility: hide when grabbing (in-game), show when not (menu)
    static SDL_HideCursor_func *pSDL_HideCursor = NULL;
    static SDL_ShowCursor_func *pSDL_ShowCursor = NULL;
    static BOOL cursorFuncsResolved = NO;
    if (!cursorFuncsResolved) {
        pSDL_HideCursor = dlsym(RTLD_DEFAULT, "SDL_HideCursor");
        pSDL_ShowCursor = dlsym(RTLD_DEFAULT, "SDL_ShowCursor");
        cursorFuncsResolved = YES;
    }
    if (pSDL_HideCursor && pSDL_ShowCursor) {
        if (grabbing) {
            pSDL_HideCursor();
            NSLog(@"[InputDiag] nativeSetGrabbing: SDL_HideCursor called");
        } else {
            pSDL_ShowCursor();
            NSLog(@"[InputDiag] nativeSetGrabbing: SDL_ShowCursor called");
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        SurfaceViewController *vc = [SurfaceViewController currentInstance];
        if (vc) {
            [vc updateGrabState];
        }
    });
}

JNIEXPORT jboolean JNICALL Java_org_lwjgl_glfw_CallbackBridge_nativeIsGrabbing(JNIEnv* env, jclass clazz) {
    return isGrabbing;
}

void CallbackBridge_nativeSetInputReady(BOOL inputReady) {
    isInputReady = inputReady;
    if (inputReady) {
        if (GLFW_invoke_FramebufferSize) {
            GLFW_invoke_FramebufferSize((void*) showingWindow, windowWidth, windowHeight);
        }
        if (GLFW_invoke_WindowSize) {
            GLFW_invoke_FramebufferSize((void*) showingWindow, windowWidth, windowHeight);
        }
    }
}

// Queue modifier synchronization from UIKit callbacks. JNI work is consumed
// by pojavPumpEvents on the game thread, where runtimeJNIEnvPtr is valid.
void CallbackBridge_queueModifierSync(int mods) {
    if (!isInputReady) return;
    sendData(EVENT_TYPE_MODIFIERS, mods, 0, 0, 0);
}

// ============================================================================
// issue #27 修复（参照 FCL commit 08c0716）：物理键盘 modifier 同步
//
// MC 1.21.9+ 不再仅依赖 key 回调中的 mods 参数，而是通过
// InputConstants.isKeyDown(window, GLFW_KEY_LEFT_SHIFT) 查询 modifier 状态。
// 该状态由 MC 内部缓存维护，仅靠 GLFW key callback 无法同步，
// 必须显式调用 Java 端 setModifiers 才能更新。
//
// 此处通过 JNI 反射调用 com.mojang.blaze3d.platform.InputConstants
// 的内部方法（如果存在），实现 modifier 缓存的显式同步。
// 旧版本 MC 没有此机制，调用会安全失败（找不到方法直接返回）。
//
// 由 KeyboardInput.m 在物理键盘事件中调用（pressesBegan/pressesEnded），
// 也可被 Java 端 CallbackBridge.nativeSetModifiers 调用。
// ============================================================================
void CallbackBridge_syncModifiersToMC(int mods) {
    if (!runtimeJavaVMPtr || !isInputReady) return;

    JNIEnv *env = NULL;
    jint envStatus = (*runtimeJavaVMPtr)->GetEnv(
        runtimeJavaVMPtr, (void **)&env, JNI_VERSION_1_4);
    if (envStatus != JNI_OK || !env) return;

    jclass inputConstantsClass = (*env)->FindClass(env, "com/mojang/blaze3d/platform/InputConstants");
    if (!inputConstantsClass) {
        if ((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);
        return;
    }
    jmethodID setModifiersMethod = (*env)->GetStaticMethodID(env, inputConstantsClass, "setModifiers", "(I)V");
    if (!setModifiersMethod) {
        if ((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);
        (*env)->DeleteLocalRef(env, inputConstantsClass);
        return;
    }
    (*env)->CallStaticVoidMethod(env, inputConstantsClass, setModifiersMethod, (jint)mods);
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
    }
    (*env)->DeleteLocalRef(env, inputConstantsClass);
}

// JNI wrapper：供 Java 端 CallbackBridge.nativeSetModifiers(int) 调用
JNIEXPORT void JNICALL Java_org_lwjgl_glfw_CallbackBridge_nativeSetModifiers(JNIEnv* env, jclass clazz, jint mods) {
    CallbackBridge_syncModifiersToMC(mods);
}

BOOL CallbackBridge_nativeSendChar(jchar codepoint /* jint codepoint */) {
    if (GLFW_invoke_Char && isInputReady) {
        if (isUseStackQueueCall) {
            sendData(EVENT_TYPE_CHAR, codepoint, 0, 0, 0);
        } else {
            GLFW_invoke_Char((void*) showingWindow, (unsigned int) codepoint);
            // return lwjgl2_triggerCharEvent(codepoint);
        }
        return YES;
    }
    return NO;
}

BOOL CallbackBridge_nativeSendCharMods(jchar codepoint, int mods) {
    if (GLFW_invoke_CharMods && isInputReady) {
        if (isUseStackQueueCall) {
            sendData(EVENT_TYPE_CHAR_MODS, (unsigned int) codepoint, mods, 0, 0);
        } else {
            GLFW_invoke_CharMods((void*) showingWindow, codepoint, mods);
        }
        return YES;
    }
    return NO;
}
/*
JNIEXPORT void JNICALL Java_org_lwjgl_glfw_CallbackBridge_nativeSendCursorEnter(JNIEnv* env, jclass clazz, jint entered) {
    if (GLFW_invoke_CursorEnter && isInputReady) {
        GLFW_invoke_CursorEnter(showingWindow, entered);
    }
}
*/

// ============================================================================
// grab 状态同步（MC 26.3 / SDL3）
//
// MC 26.3 改用 SDL3 后不再调用 glfwSetInputMode，于是 CallbackBridge_nativeSetGrabbing
// 与 pojavPumpEvents 都不会被触发，isGrabbing 只能从 SDL 侧同步。
//
// 原先只靠 CallbackBridge_nativeSendCursorPos 里的轮询，而它有两个致命缺陷：
//   1. 必须由触摸事件驱动 —— 进世界后玩家不碰屏幕就永远同步不了
//   2. 若 MC 根本不启用 SDL relative mouse mode，轮询结果恒为 false
// 实测日志中 isGrabbing 全程为 0，正是这条链路断了。
//
// isGrabbing 直接决定游戏内物品栏能否点击：
//   callback_SurfaceViewController_touchHotbar() 首行即 `if (isGrabbing == JNI_FALSE) return -1;`
// 同时 guiScale 也只有在本函数里才会刷新，而 mcscale() 用它计算物品栏命中区域；
// guiScale 卡在初始值 1 会让区域缩小到约 60x6 像素，等于点不中。
// 两者任一失效都会表现为"hotbar 点不动"，即上游 issue 里反馈的那个现象。
//
// 调用方：
//   1. main_hook.m 的 hooked_dlsym 拦截 SDL_SetWindowRelativeMouseMode（主路径）
//   2. CallbackBridge_nativeSendCursorPos 的轮询（兜底）
//
// 注意这里可能在任意线程被调用（渲染线程 / UI 主线程），因此 JNI 调用必须
// 获取本线程自己的 JNIEnv，不能复用 runtimeJNIEnvPtr。
// ============================================================================
void CallbackBridge_syncGrabStateFromSDL(BOOL relMode, const char *source) {
    static BOOL lastRelMode = NO;
    static BOOL haveLast = NO;

    if (haveLast && relMode == lastRelMode) return;
    haveLast = YES;
    lastRelMode = relMode;

    BOOL wasGrabbing = isGrabbing;
    isGrabbing = relMode;
    NSLog(@"[InputDiag] grab state -> %d (was %d, source=%s)",
          relMode, wasGrabbing, source ? source : "?");

    // 进入抓取时补发一次左键释放：菜单里那次 ACTION_DOWN 否则永远不会抬起
    if (!wasGrabbing && relMode) {
        pushSDLMouseButton(1, false, (float)cursorX, (float)cursorY);
        NSLog(@"[InputDiag] Released stale mouse button on grab enter");
    }

    // 光标显隐
    typedef bool (*VoidFunc)(void);
    static VoidFunc hideCursor = NULL;
    static VoidFunc showCursor = NULL;
    if (!hideCursor) hideCursor = (VoidFunc)dlsym(RTLD_DEFAULT, "SDL_HideCursor");
    if (!showCursor) showCursor = (VoidFunc)dlsym(RTLD_DEFAULT, "SDL_ShowCursor");
    if (relMode && hideCursor) hideCursor();
    else if (!relMode && showCursor) showCursor();

    // 刷新 guiScale（物品栏命中判定依赖它）。
    // MC 26.3 走 SDL 时 glfwSetInputMode 不会被调用，guiScale 不会自动更新。
    //
    // 不加 isInputReady 判断：26.3 下 pojavPumpEvents 从不执行，isInputReady 恒为 NO，
    // 加了会让这里永远跳过。
    JNIEnv *scaleEnv = NULL;
    BOOL scaleDidAttach = NO;
    if (runtimeJavaVMPtr != NULL) {
        if ((*runtimeJavaVMPtr)->GetEnv(runtimeJavaVMPtr, (void **)&scaleEnv, JNI_VERSION_1_4) != JNI_OK || scaleEnv == NULL) {
            scaleEnv = NULL;
            if ((*runtimeJavaVMPtr)->AttachCurrentThread(runtimeJavaVMPtr, &scaleEnv, NULL) == JNI_OK && scaleEnv != NULL) {
                scaleDidAttach = YES;
            } else {
                scaleEnv = NULL;
            }
        }
    }
    if (scaleEnv != NULL) {
        @try {
            jclass uikitClass = (*scaleEnv)->FindClass(scaleEnv, "net/kdt/pojavlaunch/uikit/UIKit");
            if (uikitClass == NULL) {
                if ((*scaleEnv)->ExceptionCheck(scaleEnv)) (*scaleEnv)->ExceptionClear(scaleEnv);
                NSLog(@"[InputDiag] updateMCGuiScale: UIKit class not found");
            } else {
                jmethodID updateScale = (*scaleEnv)->GetStaticMethodID(scaleEnv, uikitClass, "updateMCGuiScale", "()V");
                if (updateScale == NULL) {
                    if ((*scaleEnv)->ExceptionCheck(scaleEnv)) (*scaleEnv)->ExceptionClear(scaleEnv);
                    NSLog(@"[InputDiag] updateMCGuiScale: method not found");
                } else {
                    (*scaleEnv)->CallStaticVoidMethod(scaleEnv, uikitClass, updateScale);
                    if ((*scaleEnv)->ExceptionCheck(scaleEnv)) {
                        (*scaleEnv)->ExceptionDescribe(scaleEnv);
                        (*scaleEnv)->ExceptionClear(scaleEnv);
                    } else {
                        NSLog(@"[InputDiag] updateMCGuiScale called, guiScale=%d", guiScale);
                    }
                }
                (*scaleEnv)->DeleteLocalRef(scaleEnv, uikitClass);
            }
        } @catch (NSException *e) {
            NSLog(@"[InputDiag] updateMCGuiScale exception: %@", e);
        }
        if (scaleDidAttach) {
            (*runtimeJavaVMPtr)->DetachCurrentThread(runtimeJavaVMPtr);
        }
    } else {
        NSLog(@"[InputDiag] updateMCGuiScale skipped: no JNIEnv for this thread");
    }

    // UI 侧（虚拟鼠标指针等）切回主线程刷新
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            SurfaceViewController *vc = (SurfaceViewController *)UIWindow.mainWindow.rootViewController;
            if (vc) {
                [vc updateGrabState];
            } else {
                NSLog(@"[InputDiag] updateGrabState: UIWindow.mainWindow is nil");
            }
        } @catch (NSException *e) {
            NSLog(@"[InputDiag] updateGrabState exception: %@", e);
        }
    });
}

void CallbackBridge_nativeSendCursorPos(char event, CGFloat x, CGFloat y) {
    static int cursorSendCount = 0;
    cursorSendCount++;
    if (cursorSendCount <= 10 || cursorSendCount % 50 == 0) {
        NSLog(@"[InputDiag] sendCursorPos #%d: event=%d x=%.1f y=%.1f GLFW_invoke_CursorPos=%p isInputReady=%d g_sdlWindow=%p isGrabbing=%d",
            cursorSendCount, event, x, y,
            (void*)GLFW_invoke_CursorPos, isInputReady, g_sdlWindow, isGrabbing);
    }

    // Sync isGrabbing from SDL's relative mouse mode (MC 26.3 uses SDL, not GLFW).
    //
    // 主同步路径已移到 main_hook.m —— 那里通过 hooked_dlsym 拦截 MC 对
    // SDL_SetWindowRelativeMouseMode 的调用，MC 一切换立即同步，不要求玩家先触摸。
    // 这里保留轮询仅作兜底（例如 MC 改用其它 API 设置该状态时）。
    if (g_sdlWindow) {
        typedef bool (*GetRelModeFunc)(void*);
        static GetRelModeFunc getRelMode = NULL;
        static bool cursorFuncsInited = NO;
        if (!cursorFuncsInited) {
            getRelMode = (GetRelModeFunc)dlsym(RTLD_DEFAULT, "SDL_GetWindowRelativeMouseMode");
            cursorFuncsInited = YES;
            NSLog(@"[InputDiag] SDL_GetWindowRelativeMouseMode resolved: %p", (void *)getRelMode);
        }
        if (getRelMode) {
            CallbackBridge_syncGrabStateFromSDL(getRelMode(g_sdlWindow), "poll");
        }
    }

    // Update cursor position tracking regardless
    switch (event) {
        case ACTION_DOWN:
        case ACTION_UP:
            if (!isGrabbing) {
                cursorX = x;
                cursorY = y;
            }
            break;

        case ACTION_MOVE:
            if (isGrabbing) {
                cursorX += x - cLastX;
                cursorY += y - cLastY;
            } else {
                cursorX = x;
                cursorY = y;
            }
            break;

        case ACTION_MOVE_MOTION:
            cursorX += x;
            cursorY += y;
            break;
    }

    // Path A: GLFW callbacks (older MC versions)
    if (GLFW_invoke_CursorPos && isInputReady) {
        if (!isUseStackQueueCall) {
            GLFW_invoke_CursorPos((void*) showingWindow, (double) cursorX, (double) cursorY);
        }
    }

    // Path B: SDL3 events (MC 26.3+)
    // When GLFW callbacks are NULL, we inject SDL mouse events directly.
    //
    // The raw touch path NEVER sends mouse buttons.
    // All clicks are handled by the gesture system:
    //   - surfaceOnClick (tap)     → SDL right-click (place) or left-click (menu)
    //   - surfaceOnLongpress (hold) → SDL left-click (break)
    //   - touchesMoved (drag)      → ACTION_MOVE_MOTION → camera rotation
    //
    // If we also sent buttons here, every tap would double-click
    // (once from raw touch, once from gesture).
    if (!GLFW_invoke_CursorPos && g_sdlWindow) {
        if (event == ACTION_MOVE_MOTION) {
            pushSDLMouseMotion((float)cursorX, (float)cursorY, (float)x, (float)y);
        } else {
            // Menu or in-game: always send cursor position (absolute or delta)
            pushSDLMouseMotion((float)cursorX, (float)cursorY, 0, 0);
        }
    }
}

char getKeyModifiers(int key, int action) {
    static char currMods;
    char mod;
    switch (key) {
        case GLFW_KEY_LEFT_SHIFT:
        case GLFW_KEY_RIGHT_SHIFT:
            mod = GLFW_MOD_SHIFT;
            break;
        case GLFW_KEY_LEFT_CONTROL:
        case GLFW_KEY_RIGHT_CONTROL:
            mod = GLFW_MOD_CONTROL;
            break;
        case GLFW_KEY_LEFT_ALT:
        case GLFW_KEY_RIGHT_ALT:
            mod = GLFW_MOD_ALT;
            break;
        case GLFW_KEY_LEFT_SUPER:
        case GLFW_KEY_RIGHT_SUPER:
            mod = GLFW_MOD_SUPER;
            break;
        case GLFW_KEY_CAPS_LOCK:
            mod = GLFW_MOD_CAPS_LOCK;
            break;
        case GLFW_KEY_NUM_LOCK:
            mod = GLFW_MOD_NUM_LOCK;
            break;
        default:
            return currMods;
    }
    if (action) {
        currMods |= mod;
    } else {
        currMods &= ~mod;
    }
    return currMods;
}

void CallbackBridge_nativeSendKey(int key, int scancode, int action, int mods) {
    static int keySendCount = 0;
    keySendCount++;
    if (keySendCount <= 10 || keySendCount % 50 == 0) {
        NSLog(@"[InputDiag] sendKey #%d: key=%d scancode=%d action=%d mods=%d GLFW_invoke_Key=%p isInputReady=%d g_sdlWindow=%p",
            keySendCount, key, scancode, action, mods,
            (void*)GLFW_invoke_Key, isInputReady, g_sdlWindow);
    }

    // Path A: GLFW callbacks (older MC versions)
    if (GLFW_invoke_Key && isInputReady) {
        keyDownBuffer[MAX(0, key-31)]=(jbyte)action;
        if (mods == 0) {
            mods = getKeyModifiers(key, action);
        }

        if (isUseStackQueueCall) {
            sendData(EVENT_TYPE_KEY, key, scancode, action, mods);
        } else {
            GLFW_invoke_Key((void*) showingWindow, key, scancode, action, mods);
        }
    }

    // Path B: SDL3 events (MC 26.3+)
    if (!GLFW_invoke_Key && g_sdlWindow) {
        int sdlScancode = glfwKeyToSDLScancode(key);
        if (sdlScancode != 0) {
            pushSDLKeyboardEvent(sdlScancode, action != 0);
        }
    }

    // On macOS, Minecraft expects the Command key
    if (key == GLFW_KEY_LEFT_CONTROL) {
        CallbackBridge_nativeSendKey(GLFW_KEY_LEFT_SUPER, 0, action, mods);
    } else if (key == GLFW_KEY_RIGHT_CONTROL) {
        CallbackBridge_nativeSendKey(GLFW_KEY_RIGHT_SUPER, 0, action, mods);
    }
}

void CallbackBridge_nativeSendMouseButton(int button, int action, int mods) {
    // Path A: GLFW callbacks (older MC versions)
    if (isInputReady) {
        if (button == -1) {
        } else if (GLFW_invoke_MouseButton) {
            if (mods == 0) {
                mods = getKeyModifiers(0, action);
            }

            if (isUseStackQueueCall) {
                sendData(EVENT_TYPE_MOUSE_BUTTON, button, action, mods, 0);
            } else {
                GLFW_invoke_MouseButton((void*) showingWindow, button, action, mods);
            }
        }
    }

    // Path B: SDL3 events (MC 26.3+)
    if (!GLFW_invoke_MouseButton && g_sdlWindow && button >= 0) {
        pushSDLMouseButton(glfwButtonToSDLButton(button), action != 0, (float)cursorX, (float)cursorY);
    }
}

void CallbackBridge_nativeSendScreenSize(int width, int height) {
    windowWidth = width;
    windowHeight = height;
    
    if (isInputReady) {
        if (GLFW_invoke_FramebufferSize) {
            if (isUseStackQueueCall) {
                sendData(EVENT_TYPE_FRAMEBUFFER_SIZE, width, height, 0, 0);
            } else {
                GLFW_invoke_FramebufferSize((void*) showingWindow, width, height);
            }
        }
        if (GLFW_invoke_WindowSize) {
            if (isUseStackQueueCall) {
                sendData(EVENT_TYPE_WINDOW_SIZE, width, height, 0, 0);
            } else {
                GLFW_invoke_WindowSize((void*) showingWindow, width, height);
            }
        }
    }
    
    // return (isInputReady && (GLFW_invoke_FramebufferSize || GLFW_invoke_WindowSize));
}

void CallbackBridge_nativeSendScroll(CGFloat xoffset, CGFloat yoffset) {
    // Path A: GLFW callbacks
    if (GLFW_invoke_Scroll && isInputReady) {
        if (isUseStackQueueCall) {
            sendDataFloat(EVENT_TYPE_SCROLL, xoffset, yoffset, 0, 0);
        } else {
            GLFW_invoke_Scroll((void*) showingWindow, (double) xoffset, (double) yoffset);
        }
    }

    // Path B: SDL3 events (MC 26.3+)
    if (!GLFW_invoke_Scroll && g_sdlWindow) {
        pushSDLMouseWheel((float)xoffset, (float)yoffset);
    }
}
JNIEXPORT void JNICALL Java_org_lwjgl_glfw_GLFW_nglfwSetShowingWindow(JNIEnv* env, jclass clazz, jlong window) {
    showingWindow = (long) window;
}

void CallbackBridge_pauseGameIfNeed() {
    if (isGrabbing) {
        CallbackBridge_nativeSendKey(GLFW_KEY_ESCAPE, 0, 1, 0);
        CallbackBridge_nativeSendKey(GLFW_KEY_ESCAPE, 0, 0, 0);
    }
}

// JNI bridge: MC 26.1/26.2 use LWJGL 3.4.1 Java bindings which declare
// native method "nsetupEnvData" (with "n" prefix), but the prebuilt
// liblwjgl.dylib built from 3.4.1 sources exports "setupEnvData"
// (without "n" prefix) — 3.4.1 dropped the "n" on the C side only.
// This function bridges the name mismatch by forwarding to the real
// implementation.
JNIEXPORT jlong JNICALL Java_org_lwjgl_system_ThreadLocalUtil_nsetupEnvData(
    JNIEnv *env, jclass clazz, jint functionCount) {
    typedef jlong (*SetupEnvDataFunc)(JNIEnv*, jclass, jint);
    static SetupEnvDataFunc realFunc = NULL;
    static bool resolved = false;
    if (!resolved) {
        realFunc = (SetupEnvDataFunc)dlsym(RTLD_DEFAULT,
            "Java_org_lwjgl_system_ThreadLocalUtil_setupEnvData");
        resolved = true;
        if (!realFunc) {
            NSLog(@"[LWJGL Bridge] nsetupEnvData: setupEnvData not found in loaded libraries!");
        }
    }
    if (realFunc) {
        return realFunc(env, clazz, functionCount);
    }
    NSLog(@"[LWJGL Bridge] nsetupEnvData: FATAL - no implementation found");
    return 0;
}
