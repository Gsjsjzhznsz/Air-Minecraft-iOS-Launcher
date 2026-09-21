#include <Foundation/Foundation.h>
#include <AVFoundation/AVFoundation.h>
#include <pthread.h>
#include "jni.h"

#define CIRCULAR_BUFFER_SIZE (48000 * 2 * 8)

typedef struct {
    uint8_t *buffer;
    size_t size;
    size_t write_pos;
    size_t read_pos;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    volatile BOOL running;
    volatile BOOL destroyed;
} AudioCaptureCtx;

static AudioCaptureCtx *ctx_init() {
    AudioCaptureCtx *ctx = calloc(1, sizeof(AudioCaptureCtx));
    ctx->buffer = malloc(CIRCULAR_BUFFER_SIZE);
    ctx->size = CIRCULAR_BUFFER_SIZE;
    ctx->write_pos = 0;
    ctx->read_pos = 0;
    ctx->running = NO;
    ctx->destroyed = NO;
    pthread_mutex_init(&ctx->mutex, NULL);
    pthread_cond_init(&ctx->cond, NULL);
    return ctx;
}

static void ctx_destroy(AudioCaptureCtx *ctx) {
    if (!ctx) return;
    pthread_mutex_destroy(&ctx->mutex);
    pthread_cond_destroy(&ctx->cond);
    free(ctx->buffer);
    free(ctx);
}

static size_t ctx_available(AudioCaptureCtx *ctx) {
    size_t wp = ctx->write_pos;
    size_t rp = ctx->read_pos;
    return wp >= rp ? wp - rp : 0;
}

static void ctx_write(AudioCaptureCtx *ctx, const uint8_t *data, size_t len) {
    pthread_mutex_lock(&ctx->mutex);
    size_t avail = ctx_available(ctx);
    size_t space = ctx->size - avail;
    if (len > space) len = space;
    if (len > 0) {
        size_t remaining = len;
        while (remaining > 0) {
            size_t pos = ctx->write_pos % ctx->size;
            size_t chunk = ctx->size - pos;
            if (chunk > remaining) chunk = remaining;
            memcpy(ctx->buffer + pos, data, chunk);
            ctx->write_pos += chunk;
            data += chunk;
            remaining -= chunk;
        }
        pthread_cond_broadcast(&ctx->cond);
    }
    pthread_mutex_unlock(&ctx->mutex);
}

static size_t ctx_read(AudioCaptureCtx *ctx, uint8_t *data, size_t len, BOOL block) {
    pthread_mutex_lock(&ctx->mutex);
    while (ctx_available(ctx) == 0) {
        if (!block || !ctx->running || ctx->destroyed) {
            pthread_mutex_unlock(&ctx->mutex);
            return 0;
        }
        pthread_cond_wait(&ctx->cond, &ctx->mutex);
    }
    size_t avail = ctx_available(ctx);
    if (len > avail) len = avail;
    size_t remaining = len;
    while (remaining > 0) {
        size_t pos = ctx->read_pos % ctx->size;
        size_t chunk = ctx->size - pos;
        if (chunk > remaining) chunk = remaining;
        memcpy(data, ctx->buffer + pos, chunk);
        ctx->read_pos += chunk;
        data += chunk;
        remaining -= chunk;
    }
    pthread_mutex_unlock(&ctx->mutex);
    return len;
}

typedef struct {
    void *engine;
    void *outputFormat;
    AudioCaptureCtx *ctx;
    // Task 139：重采样状态（native 采样率/声道 -> 请求的采样率单声道）。
    // iOS 输入节点的原生格式由硬件决定（常见 1ch/24kHz 或 1ch/48kHz），
    // installTapOnBus 的 format 参数必须与节点原生输出格式完全一致，
    // 强制传入请求格式（如 1ch/48kHz Float32）会在不匹配的设备上抛
    // com.apple.coreaudio.avfaudio "Failed to create tap due to format
    // mismatch" NSException —— 26.1.2 装机日志实锤：voicechat 的
    // MicrophoneThread 走 macOS 路径（Platform.isMac 伪装）打开本采集器，
    // 强制 1ch/48000 在该设备上与原生格式不符 → 未捕获异常 → 整个 app
    // 终止（用户侧表现为“启动存档即闪退”）。修法：tap 按原生格式安装，
    // 回调里线性插值重采样到请求的采样率，多声道时取均值混成单声道。
    double srcRate;      // 原生采样率（tap 实际交付的缓冲区速率）
    double dstRate;      // 请求采样率（Java 侧 TargetDataLine 期望值）
    uint32_t srcChannels; // 原生声道数
    double nextOutPos;   // 下一个输出样本对应的输入帧绝对位置（防跨缓冲漂移）
    double totalIn;      // 已接收的输入帧总数（绝对坐标）
    float tail[8];       // 上一缓冲末帧样本（逐声道，插值连续性）
} CaptureHandle;

#define HANDLE_ENGINE(h) ((__bridge AVAudioEngine*)(h)->engine)
#define HANDLE_FORMAT(h) ((__bridge AVAudioFormat*)(h)->outputFormat)

static void tapCallback(AVAudioPCMBuffer *buffer, AudioCaptureCtx *ctx, CaptureHandle *rs) {
    if (!ctx->running || ctx->destroyed) return;
    if (buffer.frameLength == 0) return;

    float * const *floatData = buffer.floatChannelData;
    if (!floatData || !floatData[0]) return;

    size_t frameCount = buffer.frameLength;
    uint32_t channels = rs ? rs->srcChannels : 1;
    if (channels < 1) channels = 1;
    if (channels > 8) channels = 8;

    // ---- Task 139：先重采样到请求速率（单声道），再量化为 int16 ----
    // 输出样本数按绝对坐标累计（nextOutPos / totalIn），跨缓冲不漂移、
    // 不丢帧；srcRate == dstRate 时退化为逐帧直通（frac 恒 0）。
    double srcRate = rs ? rs->srcRate : 0;
    double dstRate = rs ? rs->dstRate : 0;
    size_t outFrames;
    if (!rs || srcRate <= 0 || dstRate <= 0) {
        outFrames = frameCount;                 // 无重采样状态（防御）：直通
    } else {
        double totalInPrev = rs->totalIn;
        rs->totalIn += (double)frameCount;
        double ratio = srcRate / dstRate;
        // 先数出本缓冲能产出的输出帧数
        size_t count = 0;
        double probe = rs->nextOutPos;
        while (probe < rs->totalIn) {
            count++;
            probe += ratio;
        }
        outFrames = count;
        if (outFrames == 0) {
            // 本缓冲太短不足以产出样本：缓存末帧供下轮插值
            for (uint32_t c = 0; c < channels; c++) {
                rs->tail[c] = floatData[c][frameCount - 1];
            }
            return;
        }

        size_t byteCountOut = outFrames * 2;
        uint8_t *intData = malloc(byteCountOut);
        if (!intData) return;
        int16_t *samples = (int16_t *)intData;

        for (size_t k = 0; k < outFrames; k++) {
            double idx = rs->nextOutPos - totalInPrev;   // 在本缓冲内的位置
            if (idx < 0) idx = 0;
            size_t i0 = (size_t)idx;
            double frac = idx - (double)i0;
            float mixed = 0.0f;
            for (uint32_t c = 0; c < channels; c++) {
                float s0 = (i0 < frameCount) ? floatData[c][i0] : rs->tail[c];
                float s1;
                if (i0 + 1 < frameCount) {
                    s1 = floatData[c][i0 + 1];
                } else if (i0 + 1 == frameCount) {
                    s1 = rs->tail[c];
                } else {
                    s1 = s0;
                }
                mixed += (float)((double)s0 + ((double)s1 - (double)s0) * frac);
            }
            mixed /= (float)channels;                     // 多声道均值混单声道
            if (mixed > 1.0f) mixed = 1.0f;
            else if (mixed < -1.0f) mixed = -1.0f;
            samples[k] = (int16_t)(mixed * 32767.0f);
            rs->nextOutPos += ratio;
        }

        for (uint32_t c = 0; c < channels; c++) {
            rs->tail[c] = floatData[c][frameCount - 1];
        }
        ctx_write(ctx, intData, byteCountOut);
        free(intData);
        return;
    }

    // ---- 无重采样直通（保持旧路径：单声道浮点 -> int16）----
    size_t byteCount = frameCount * 2;
    uint8_t *intData = malloc(byteCount);
    if (!intData) return;

    int16_t *samples = (int16_t *)intData;
    for (size_t i = 0; i < frameCount; i++) {
        float sample = floatData[0][i];
        if (sample > 1.0f) sample = 1.0f;
        else if (sample < -1.0f) sample = -1.0f;
        samples[i] = (int16_t)(sample * 32767.0f);
    }

    ctx_write(ctx, intData, byteCount);
    free(intData);
}

static CaptureHandle *createCapture(int sampleRate) {
    @try {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        if (!session.inputAvailable) {
            NSLog(@"[AudioCapture] No input available");
            return NULL;
        }

        AVAudioEngine *engine = [[AVAudioEngine alloc] init];
        AVAudioInputNode *inputNode = engine.inputNode;

        // Task 139：tap 格式必须用输入节点的【原生】输出格式。
        // 强制传入构造格式（1ch/请求速率）在不匹配的硬件上会让
        // installTapOnBus 抛 NSException（avfaudio format mismatch）。
        AVAudioFormat *nativeFormat = [inputNode outputFormatForBus:0];
        if (!nativeFormat || nativeFormat.sampleRate <= 0 || nativeFormat.channelCount < 1) {
            NSLog(@"[AudioCapture] Task139: invalid native input format, giving up gracefully");
            return NULL;
        }
        if (nativeFormat.channelCount > 8) {
            NSLog(@"[AudioCapture] Task139: native input has %lu channels, clamping to 8",
                  (unsigned long)nativeFormat.channelCount);
        }

        NSLog(@"[AudioCapture] Task139: tap installed with native format %@ (requested %d Hz mono) -- resampling in callback",
              nativeFormat, sampleRate);

        AudioCaptureCtx *ctx = ctx_init();
        ctx->running = YES;

        CaptureHandle *handle = calloc(1, sizeof(CaptureHandle));
        handle->srcRate = (double)nativeFormat.sampleRate;
        handle->dstRate = (double)sampleRate;
        handle->srcChannels = nativeFormat.channelCount;
        handle->nextOutPos = 0.0;
        handle->totalIn = 0.0;
        handle->ctx = ctx;

        AVAudioFrameCount tapBuffer = (AVAudioFrameCount)(nativeFormat.sampleRate / 10.0);
        if (tapBuffer == 0) tapBuffer = 480;   // ~10ms @48k，防御原生速率极低
        [inputNode installTapOnBus:0
                        bufferSize:tapBuffer
                            format:nativeFormat
                             block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            tapCallback(buffer, ctx, handle);
            (void)when;
        }];

        [engine prepare];

        handle->engine = (__bridge_retained void*)engine;
        handle->outputFormat = (__bridge_retained void*)nativeFormat;
        return handle;
    }
    @catch (NSException *e) {
        // 任何 AVAudioEngine 异常都不允许杀死整个 app：返回 NULL 让 Java 侧
        // 抛 LineUnavailableException，voicechat 优雅降级为“无麦克风”。
        NSLog(@"[AudioCapture] Task139: capture creation failed with exception %@: %@",
              e.name, e.reason);
        return NULL;
    }
}

static void destroyCapture(CaptureHandle *handle) {
    if (!handle) return;
    // Task 139：必须先停引擎/移除 tap 再释放 ctx —— 旧顺序（先 ctx_destroy
    // 后 removeTap）在两者之间到达的 tap 回调里解引用已释放的 ctx，是
    // use-after-free 竞态。先摘回调源，再拆状态。
    if (handle->engine) {
        AVAudioEngine *e = (__bridge_transfer AVAudioEngine*)handle->engine;
        [e.inputNode removeTapOnBus:0];
        [e stop];
        handle->engine = NULL;
    }
    if (handle->ctx) {
        pthread_mutex_lock(&handle->ctx->mutex);
        handle->ctx->running = NO;
        handle->ctx->destroyed = YES;
        pthread_cond_broadcast(&handle->ctx->cond);
        pthread_mutex_unlock(&handle->ctx->mutex);
        ctx_destroy(handle->ctx);
        handle->ctx = NULL;
    }
    if (handle->outputFormat) {
        AVAudioFormat *f = (__bridge_transfer AVAudioFormat*)handle->outputFormat;
        (void)f;
        handle->outputFormat = NULL;
    }
    free(handle);
}

#pragma mark - JNI

JNIEXPORT jlong JNICALL Java_com_apple_ios_audio_NativeAudioCapture_init(
    JNIEnv *env, jclass clazz, jint sampleRate, jint channels, jint bitsPerSample, jboolean bigEndian) {

    CaptureHandle *handle = createCapture((int)sampleRate);
    if (!handle || !HANDLE_ENGINE(handle)) {
        NSLog(@"[AudioCapture] Failed to create audio capture");
        if (handle) destroyCapture(handle);
        return 0;
    }

    (void)channels;
    (void)bitsPerSample;
    (void)bigEndian;
    (void)env;
    (void)clazz;

    return (jlong)(intptr_t)handle;
}

JNIEXPORT void JNICALL Java_com_apple_ios_audio_NativeAudioCapture_start(
    JNIEnv *env, jclass clazz, jlong handlePtr) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    if (!handle || !HANDLE_ENGINE(handle)) return;
    NSError *error = nil;
    @try {
        [HANDLE_ENGINE(handle) startAndReturnError:&error];
    }
    @catch (NSException *e) {
        NSLog(@"[AudioCapture] Task139: engine start threw %@: %@", e.name, e.reason);
    }
    if (error) {
        NSLog(@"[AudioCapture] Failed to start engine: %@", error);
    }
    if (handle->ctx) {
        handle->ctx->running = YES;
    }
    (void)env;
    (void)clazz;
}

JNIEXPORT void JNICALL Java_com_apple_ios_audio_NativeAudioCapture_stop(
    JNIEnv *env, jclass clazz, jlong handlePtr) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    if (!handle || !HANDLE_ENGINE(handle)) return;
    [HANDLE_ENGINE(handle) pause];
    if (handle->ctx) {
        handle->ctx->running = NO;
        pthread_cond_broadcast(&handle->ctx->cond);
    }
    (void)env;
    (void)clazz;
}

JNIEXPORT void JNICALL Java_com_apple_ios_audio_NativeAudioCapture_release(
    JNIEnv *env, jclass clazz, jlong handlePtr) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    destroyCapture(handle);
    (void)env;
    (void)clazz;
}

JNIEXPORT jint JNICALL Java_com_apple_ios_audio_NativeAudioCapture_read(
    JNIEnv *env, jclass clazz, jlong handlePtr, jbyteArray buffer, jint offset, jint length) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    if (!handle || !handle->ctx || !handle->ctx->running) return -1;
    jbyte *elements = (*env)->GetByteArrayElements(env, buffer, NULL);
    if (!elements) return -1;
    int n = (int)ctx_read(handle->ctx, (uint8_t *)(elements + offset), (size_t)length, YES);
    (*env)->ReleaseByteArrayElements(env, buffer, elements, 0);
    return n;
    (void)clazz;
}

JNIEXPORT jint JNICALL Java_com_apple_ios_audio_NativeAudioCapture_available(
    JNIEnv *env, jclass clazz, jlong handlePtr) {
    CaptureHandle *handle = (CaptureHandle *)(intptr_t)handlePtr;
    if (!handle || !handle->ctx) return 0;
    pthread_mutex_lock(&handle->ctx->mutex);
    size_t avail = ctx_available(handle->ctx);
    pthread_mutex_unlock(&handle->ctx->mutex);
    return (jint)avail;
    (void)env;
    (void)clazz;
}
