#ifndef UP60P_COMMON_H
#define UP60P_COMMON_H

#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <libgen.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <strings.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <limits.h>

#include <mach-o/dyld.h>


// MARK: - Bridging Headers
#include "up60p.h"
#include "Up60PBridging.h"
// MARK: Bridging Headers -

// MARK: - Constants
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif



#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define ARR_LEN(a) ((int)(sizeof(a)/sizeof((a)[0])))
// MARK: Constants-

// MARK: - COLOR

#define C_RESET   "\033[0m"
#define C_BOLD    "\033[1m"
#define C_RED     "\033[31m"
#define C_GREEN   "\033[32m"
#define C_YELLOW  "\033[33m"
#define C_CYAN    "\033[36m"

// MARK: COLOR -

typedef struct Settings Settings;


#endif
