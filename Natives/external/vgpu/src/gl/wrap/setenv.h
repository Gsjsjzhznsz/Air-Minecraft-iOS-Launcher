

extern void SetEnv(char *envname, int value);
extern void allSetEnv(void);
/*
#define LIBGL_FB "LIBGL_FB"
#define LIBGL_MIPMAP "LIBGL_MIPMAP"
#define LIBGL_NOTEST "LIBGL_NOTEST"
#define LIBGL_NOVAOCACHE "LIBGL_NOVAOCACHE"
#define LIBL_FBOUNBIND "LIBL_FBOUNBIND"
#define LIBGL_FBOFORCETEX "LIBGL_FBOFORCETEX"
#define LIBGL_NORMALIZE "LIBGL_NORMALIZE"
*/
#define ENV_NUM 2
char * SETENVS[ENV_NUM] = {
	"LIBGL_NORMALIZE=1",
	"LIBGL_MIPMAP=0"
	//"LIBGL_FB=2"
};

#include "setenv.c"