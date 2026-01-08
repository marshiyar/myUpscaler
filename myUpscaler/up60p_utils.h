#ifndef UP60P_UTILS_H
#define UP60P_UTILS_H

#include "up60p.h"
#include "up60p_common.h"

typedef struct {
    char *buf;
    size_t len,
    cap;
} SB;


void safe_copy(char *dst, const char *src, size_t size);

void mkdir_p(const char *path);
void sanitize_path(char *p);

void sb_append(SB *s, const char *str);
void sb_fmt(SB *s, const char *fmt, ...);

double parse_strength(const char *strength);

bool is_image(const char *path);



bool up60p_is_cancelled(void);
void up60p_request_cancel(void);


extern up60p_log_callback global_log_cb;

#endif
