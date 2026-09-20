/*
 * ring_buffer.h
 * Angel Aura Amethyst
 *
 * TouchController iOS transport 的消息环形队列（忠实移植自
 * TouchController mod 仓库 touchcontroller/proxy/server/util/ringbuffer/
 * ring_buffer.{h,c}——上游 LGPL-3.0，版权 fifth_light）。
 *
 * 队列承载 void* 指针（调用方自管生命周期）；本传输层用它搬运
 * message_t（size + malloc 数据）指针。头尾相等 = 空；容量满时
 * ring_buffer_enqueue 自动倍增扩容，ring_buffer_try_enqueue 拒绝入队。
 */

#ifndef RING_BUFFER_H
#define RING_BUFFER_H

#include <stddef.h>

typedef struct ring_buffer {
    void **queue;
    size_t capacity;
    size_t head;
    size_t tail;
} ring_buffer_t;

ring_buffer_t *ring_buffer_alloc(size_t capacity);
void ring_buffer_free(ring_buffer_t *buf);
int ring_buffer_enqueue(ring_buffer_t *buf, void *data);
int ring_buffer_try_enqueue(ring_buffer_t *buf, void *data);
void *ring_buffer_dequeue(ring_buffer_t *buf);

#endif
