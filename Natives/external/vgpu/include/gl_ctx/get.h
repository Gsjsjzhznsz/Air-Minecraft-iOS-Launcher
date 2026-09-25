


#define TLS_SLOT_OPENGL_API         3
#define TLS_SLOT_OPENGL             4

#if defined(__aarch64__)
# define __get_tls() ({ void** __val; __asm__("mrs %0, tpidr_el0" : "=r"(__val)); __val; })
#elif defined(__arm__)
# define __get_tls() ({ void** __val; __asm__("mrc p15, 0, %0, c13, c0, 3" : "=r"(__val)); __val; })
#elif defined(__x86__)
# define __get_tls() ({ void** __val; __asm__("movl %%gs:0, %0" : "=r"(__val)); __val; })
#elif defined(__x86_64__)
# define __get_tls() ({ void** __val; __asm__("mov %%fs:0, %0" : "=r"(__val)); __val; })
#else
#error unsupported architecture
#endif

static inline void setGlThreadSpecific(void* ptr) {
	(__get_tls()[TLS_SLOT_OPENGL]) = ptr;
    //return (void*)(__get_tls()[TLS_SLOT_OPENGL]);
}

static inline void* getGlThreadSpecific() {
	//return static_cast<void*>(__get_tls()[TLS_SLOT_OPENGL]);
    return (void*)(__get_tls()[TLS_SLOT_OPENGL]);
}