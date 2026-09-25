#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void SetEnv(char *envname, int value){
	int len = snprintf(NULL, 0, "%d", value);
	len++;
	char * value_ = (char *)malloc(len);
	len = snprintf(value_, len, "%d", value);
	int succeed = setenv((const char *)envname, (const char *)value_, 1);
	free(value_);
}

void allSetEnv(void){
	int succeed;
	for(int n=0; n<ENV_NUM; n++){
		succeed = putenv(SETENVS[n]);
	}
}