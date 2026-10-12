#ifndef UP60P_COMMON_H
#define UP60P_COMMON_H

#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <strings.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <limits.h>

#include <mach-o/dyld.h>
#include "up60p.h"
#include "Up60PBridging.h"


#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define ARR_LEN(a) ((int)(sizeof(a)/sizeof((a)[0])))


typedef struct Settings Settings;


#endif
