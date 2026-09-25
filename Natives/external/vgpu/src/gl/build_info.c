#include <stdio.h>
#include "build_info.h"
#include "logs.h"
#include "../../version.h"

void print_build_infos()
{
	SHUT_LOGD("vgpu %d.%d.%d gl4es %d.%d.%d built on %s %s\n", MAJOR_, MINOR_, REVISION_, MAJOR, MINOR, REVISION, __DATE__, __TIME__);
}
