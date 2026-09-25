


#include <stdio.h>
// Task173 (iOS port): android/log.h does not exist outside the NDK; the
// android Printf variant above stays retired, printf routes to the
// launcher-redirected stdout.
#define Printf(...) printf(__VA_ARGS__)