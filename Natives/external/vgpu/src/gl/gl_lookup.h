#ifndef _GL_LOOKUP_H_
#define _GL_LOOKUP_H_

#ifdef DEBUG
#define MAP(func_name, func) \
    if (strcmp(name, func_name) == 0) {printf("%p (%s)\n", (void*)func, #func) ;return (void *)func;}
#else
#define MAP(func_name, func) \
    if (strcmp(name, func_name) == 0) return (void *)func;		// strcmp() string comparison returns 0 if they are the same.
#endif

#define EX(func_name) MAP(#func_name, func_name)      \
						MAP(#func_name "ARB", func_name) \
						MAP(#func_name "EXT", func_name)

#define ARB(func_name) MAP(#func_name "ARB", func_name)

#define EXT(func_name) MAP(#func_name "EXT", func_name)		// This is provided to the outside world to query gl4es internal whether there is a (gl4es) function;
																	// If so, the address of the gl4es function is returned.
																	
#define _EX(func_name) MAP(#func_name, gl4es_ ## func_name)	// if (strcmp(name, "glFunc") == 0) return (void *)gl4es_glFunc;
//#define _EX(func_name) MAP(#func_name, func_name)	// if (strcmp(name, "glFunc") == 0) return (void *)glFunc;
#define __ARB(func_name) MAP(#func_name "ARB", func_name)	// glDrawBuffersARB()

#define _ARB(func_name) MAP(#func_name "ARB", gl4es_ ## func_name)	// gl4es_glCreateShaderObject

#define _EXT(func_name) MAP(#func_name "EXT", gl4es_ ## func_name)

#ifndef STUB_FCT
#error STUB_FCT is not defined
#endif

#ifdef DEBUG
#define STUB(func_name)                       \
    if (strcmp(name, #func_name) == 0) {      \
        printf("=> STUB\n");                  \
        if(!globals4es.silentstub) LOGD("GL4ES stub: %s\n", #func_name); \
        return (void *)STUB_FCT;              \
    }
#else
#define STUB(func_name)                       \
    if (strcmp(name, #func_name) == 0) {      \
        if(!globals4es.silentstub) LOGD("GL4ES stub: %s\n", #func_name); \
        return (void *)STUB_FCT;              \
    }
#endif

void *gl4es_GetProcAddress(const char *name);

#endif //_GL_LOOKUP_H_