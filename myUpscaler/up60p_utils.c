#include "up60p_utils.h"
#include "up60p_common.h"
#include "up60p_cli.h"

up60p_log_callback global_log_cb = NULL;

volatile sig_atomic_t cancel_requested = 0;

 void mkdir_p(const char *path) {
    char tmp[PATH_MAX]; snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) { if (*p == '/') { *p = 0; mkdir(tmp, 0775); *p = '/'; } }
    mkdir(tmp, 0775);
}


void safe_copy(char *dst, const char *src, size_t size) {
    if (size == 0) return;
    strncpy(dst, src, size - 1);
    dst[size - 1] = '\0';
}

void sanitize_path(char *p) {
    while (*p && isspace((unsigned char)*p)) p++;
    size_t len = strlen(p);
    while (len > 0 && isspace((unsigned char)p[len-1])) p[--len] = '\0';
    if (len > 2 && ((p[0] == '"' && p[len-1] == '"') || (p[0] == '\'' && p[0] == p[len-1]))) {
        memmove(p, p+1, len-2); p[len-2] = '\0'; len -= 2;
    }
    char *src = p, *dst = p;
    while (*src) {
        if (*src == '\\' && src[1] == ' ') { *dst++ = ' '; src += 2; } else *dst++ = *src++;
    } *dst = '\0';
}



void sb_append(SB *s, const char *str) {
    if (!s || !str) return;
    
    if (!s->buf) {
        s->cap = 1024;
        s->buf = malloc(s->cap);
        s->len = 0;
        if (!s->buf) {
            s->cap = 0;
            return;
        }
        s->buf[0] = '\0';
    }
    
    size_t l = strlen(str);
    
    if (s->len + l + 1 >= s->cap) {
        size_t new_cap = (s->cap + l) * 2;
        char *tmp = realloc(s->buf, new_cap);
        if (!tmp) return;
        s->buf = tmp;
        s->cap = new_cap;
    }
    
    memcpy(s->buf + s->len, str, l + 1);
    s->len += l;
}




void sb_fmt(SB *s, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    char tmp[2048]; vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap); sb_append(s, tmp);
}




double parse_strength(const char *strength) {
    if (!strength || !strcmp(strength, "auto")) return 0.0;
    char *end;
    double val = strtod(strength, &end);
    if (*end != '\0' || val < 0) return 0.0;
    return val;
}



bool is_image(const char *path) {
    const char *ext = strrchr(path, '.');
    if (!ext) return false;
    if (!strcasecmp(ext, ".png") || !strcasecmp(ext, ".jpg") ||
        !strcasecmp(ext, ".jpeg") || !strcasecmp(ext, ".tif") ||
        !strcasecmp(ext, ".tiff") || !strcasecmp(ext, ".bmp") ||
        !strcasecmp(ext, ".webp")) return true;
    return false;
}


bool up60p_is_cancelled(void) { return cancel_requested != 0; }


void up60p_request_cancel(void) {
    cancel_requested = 1;
}


