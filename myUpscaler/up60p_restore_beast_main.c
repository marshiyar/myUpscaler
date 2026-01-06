#include "up60p_settings.h"
#include "up60p_utils.h"
#include "up60p.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <termios.h>

Settings DEF;
Settings S;

int execute_ffmpeg_command(char *const argv[]) {
    int stdout_pipe[2];
    int stderr_pipe[2];
    pid_t pid;
    int status;
    
    if (pipe(stdout_pipe) < 0 || pipe(stderr_pipe) < 0) {
        return -1;
    }
    
    pid = fork();
    if (pid == 0) {
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        close(stderr_pipe[0]);
        close(stderr_pipe[1]);
        
        execvp(argv[0], argv);
        
        // exec failed
        fprintf(stderr, "execvp failed: %s (%d)\n", strerror(errno), errno);
        _exit(127);
    }
    
    if (pid < 0) {
        fprintf(stderr, "fork failed: %s (%d)\n", strerror(errno), errno);
        return -1;
    }
    
    close(stdout_pipe[1]);
    close(stderr_pipe[1]);
    
    char buf[1024];
    ssize_t n;
    
    while ((n = read(stderr_pipe[0], buf, sizeof(buf) - 1)) > 0) {
        buf[n] = 0;
        if (global_log_cb) global_log_cb(buf);
    }
    
    close(stdout_pipe[0]);
    close(stderr_pipe[0]);
    
    if (waitpid(pid, &status, 0) < 0) {
        return -1;
    }
    
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    
    return -1;
}

static volatile sig_atomic_t cancel_requested = 0;

static const char *SCRIPT_NAME = "up60p_restore_beast";
static char NULL_BUF[PATH_MAX];
static char FFMPEG_PATH[PATH_MAX] = {0};
int DRY_RUN = 0;

static const char* get_bundled_ffmpeg_path(void) {
    if (FFMPEG_PATH[0] != '\0') {
        return FFMPEG_PATH;
    }
    
    char exe_path[PATH_MAX];
    uint32_t size = sizeof(exe_path);
    
    if (_NSGetExecutablePath(exe_path, &size) != 0) {
        return NULL;
    }
    
    char exe_dir_buf[PATH_MAX];
    strncpy(exe_dir_buf, exe_path, sizeof(exe_dir_buf) - 1);
    exe_dir_buf[sizeof(exe_dir_buf) - 1] = '\0';
    
    char *exe_dir = dirname(exe_dir_buf);
    
    snprintf(FFMPEG_PATH, sizeof(FFMPEG_PATH), "%s/ThirdParty/FFmpeg/ffmpeg", exe_dir);
    
    if (access(FFMPEG_PATH, X_OK) != 0) {
        FFMPEG_PATH[0] = '\0';
        return NULL;
    }
    
    return FFMPEG_PATH;
}

static void process_file(const char *in, const char *ffmpeg, bool batch);
static void process_directory(const char *dir, const char *ffmpeg);
static int ar_menu_choose(const char *prompt, const char **items, int n, int start_index);

typedef struct { struct termios orig; int fd; bool ok; } TermCtx;

static TermCtx term_enter_raw(int fd) {
    TermCtx t = { .fd = fd, .ok=false };
    if (!isatty(fd)) return t;
    if (tcgetattr(fd, &t.orig)==-1) return t;
    struct termios raw = t.orig;
    raw.c_lflag &= ~(ICANON|ECHO); raw.c_cc[VMIN] = 1; raw.c_cc[VTIME] = 0;
    if (tcsetattr(fd, TCSAFLUSH, &raw)==-1) return t;
    t.ok=true; return t;
}
static void term_leave_raw(TermCtx *t) { if (t->ok) tcsetattr(t->fd, TCSAFLUSH, &t->orig); }

static void play_ui_sound(const char *sound_name) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "afplay /System/Library/Sounds/%s.aiff > /dev/null 2>&1 &", sound_name);
    system(cmd);
}

static void prompt_edit(const char *name, char *buf, size_t sz) {
    fprintf(stderr, "Enter value for %s [current: %s]: ", name, buf);
    char line[1024];
    if (fgets(line, sizeof(line), stdin)) {
        size_t n = strlen(line); while(n > 0 && isspace(line[n-1])) line[--n] = 0;
        if (n > 0) snprintf(buf, sz, "%s", line);
    }
}

static void cycle_string(char *current, const char **options, int count) {
    int idx = 0;
    for (int i = 0; i < count; i++) {
        if (!strcmp(current, options[i])) { idx = i; break; }
    }
    strcpy(current, options[(idx + 1) % count]);
}

static void submenu_edit_group(const char *title, const char **keys, char **vals, size_t *sizes, int n) {
    int cursor = 0;
    for (;;) {
        char **items = malloc((n+1)*sizeof(char*));
        for(int i=0; i<n; i++) { items[i] = malloc(256); snprintf(items[i], 256, "%s = '%s'", keys[i], vals[i]); }
        items[n] = strdup("← Back");
        int sel = ar_menu_choose(title, (const char**)items, n+1, cursor);
        for(int i=0; i<=n; i++) free(items[i]); free(items);
        if (sel < 0 || sel == n) break;
        cursor = sel; prompt_edit(keys[sel], vals[sel], sizes[sel]);
    }
}

static int parse_command_line(char *command_line, char ***argv_out) {
    if (!command_line || !argv_out) return -1;
    
    int argc = 0;
    int max_args = 64;
    
    char **argv = malloc(sizeof(char*) * (size_t)max_args);
    if (!argv) return -1;
    
    char *p = command_line;
    bool in_q = false, in_dq = false;
    
    while (*p) {
        while (*p && isspace((unsigned char)*p) && !in_q && !in_dq) p++;
        if (!*p) break;
        
        char *start = p;
        while (*p) {
            if (*p == '\\' && p[1]) {
                memmove(p, p + 1, strlen(p));
                p++;
            }
            else if (*p == '\'') {
                in_q = !in_q;
                memmove(p, p + 1, strlen(p));
            }
            else if (*p == '"') {
                in_dq = !in_dq;
                memmove(p, p + 1, strlen(p));
            }
            else if (isspace((unsigned char)*p) && !in_q && !in_dq) {
                break;
            }
            else {
                p++;
            }
        }
        
        if (*p) *p++ = 0;
        
        if (argc >= max_args - 1) {
            int new_max = max_args * 2;
            char **tmp = realloc(argv, sizeof(char*) * (size_t)new_max);
            if (!tmp) {
                for (int i = 0; i < argc; i++) free(argv[i]);
                free(argv);
                return -1;
            }
            argv = tmp;
            max_args = new_max;
        }
        
        argv[argc] = strdup(start);
        if (!argv[argc]) {
            for (int i = 0; i < argc; i++) free(argv[i]);
            free(argv);
            return -1;
        }
        argc++;
    }
    
    argv[argc] = NULL;
    *argv_out = argv;
    return argc;
}

static void build_hqdn3d_filter(SB *vf, const char *strength_str) {
    double strength = parse_strength(strength_str);
    if (strength <= 0) strength = 4.0;
    
    
    double luma_spatial = strength;
    if (luma_spatial < 1.0) luma_spatial = 1.0;
    if (luma_spatial > 10.0) luma_spatial = 10.0;
    
    
    double chroma_spatial = luma_spatial * 0.75;
    double luma_tmp = luma_spatial * 1.5;
    double chroma_tmp = luma_tmp * 0.75;
    
    sb_fmt(vf, "hqdn3d=%.2f:%.2f:%.2f:%.2f,", luma_spatial, chroma_spatial, luma_tmp, chroma_tmp);
}


static void build_nlmeans_filter(SB *vf, const char *strength_str) {
    double strength = parse_strength(strength_str);
    if (strength <= 0) strength = 1.0;
    
    
    if (strength < 1.0) strength = 1.0;
    if (strength > 30.0) strength = 30.0;
    
    
    int patch_size = 7;
    if (strength > 5.0) patch_size = 9;
    if (strength > 10.0) patch_size = 11;
    if (strength > 15.0) patch_size = 13;
    if (strength > 20.0) patch_size = 15;
    
    
    int research_size = 15;
    if (strength > 5.0) research_size = 17;
    if (strength > 10.0) research_size = 19;
    if (strength > 15.0) research_size = 21;
    if (strength > 20.0) research_size = 23;
    if (strength > 25.0) research_size = 25;
    
    sb_fmt(vf, "nlmeans=s=%.2f:p=%d:r=%d,", strength, patch_size, research_size);
}


static void build_atadenoise_filter(SB *vf, const char *strength_str) {
    double strength = parse_strength(strength_str);
    if (strength <= 0) strength = 9.0;
    
    
    double threshold = strength;
    if (threshold < 1.0) threshold = 1.0;
    if (threshold > 20.0) threshold = 20.0;
    
    
    
    double param_a = 0.01 + (threshold / 20.0) * 0.03;
    double param_b = 0.02 + (threshold / 20.0) * 0.06;
    
    sb_fmt(vf, "atadenoise=s=%.2f:0a=%.3f:0b=%.3f,", threshold, param_a, param_b);
}


static void build_dering_filter(SB *vf, const char *strength_str) {
    double dstr = parse_strength(strength_str);
    if (dstr <= 0) dstr = 0.5;
    double luma = dstr * 8.0;
    double chroma = luma * 0.75;
    double luma_tmp = luma * 1.5;
    double chroma_tmp = luma_tmp * 0.75;
    if (luma > 15.0) luma = 15.0;
    sb_fmt(vf, "hqdn3d=%.2f:%.2f:%.2f:%.2f,", luma, chroma, luma_tmp, chroma_tmp);
}

static void build_deblock_filter(SB *vf, const char *mode, const char *thresh) {
    if (*thresh) {
        sb_fmt(vf, "deblock=filter=%s:block=8:%s,", mode, thresh);
    } else {
        sb_fmt(vf, "deblock=filter=%s:block=8,", mode);
    }
}


static void process_file(const char *in, const char *ffmpeg, bool batch) {
    (void)batch; char outdir[PATH_MAX], base[PATH_MAX], out[PATH_MAX];
    bool img = is_image(in);
    
    if (up60p_is_cancelled()) return;
    
    {
        char t[PATH_MAX];
        safe_copy(t, in, sizeof(t));
        char *b = basename(t);
        safe_copy(base, b, sizeof(base));
        
        char *dot = strrchr(base, '.');
        if (dot) *dot = 0;
        
        if (*S.outdir) {
            safe_copy(outdir, S.outdir, sizeof(outdir));
        } else {
            safe_copy(t, in, sizeof(t));
            char *d = dirname(t);
            safe_copy(outdir, d, sizeof(outdir));
        }
    }
    
    if (img) snprintf(out, sizeof(out), "%s/%s_[restored].png", outdir, base);
    else snprintf(out, sizeof(out), "%s/%s_[restored].mp4", outdir, base);
    
    SB vf = {0};
    
    
    if (!img) {
        if (S.pci_safe_mode) sb_append(&vf, "format=yuv420p,");
        else sb_append(&vf, "format=yuv444p16le,");
        
        if (!S.no_decimate) sb_append(&vf, "mpdecimate=hi=64*12,setpts=PTS,");
    }
    
    if (!S.no_deblock) {
        build_deblock_filter(&vf, S.deblock_mode, S.deblock_thresh);
    }
    
    if (!S.no_denoise) {
        if (!strcmp(S.denoiser, "bm3d")) {
            if (!strcmp(S.denoise_strength, "auto")) sb_append(&vf, "bm3d=estim=final:planes=1,");
            else {
                double sigma = parse_strength(S.denoise_strength);
                if (sigma <= 0) sigma = 2.5;
                if (sigma > 20.0) sigma = 20.0;
                sb_fmt(&vf, "bm3d=sigma=%.2f:estim=basic:planes=1,", sigma);
            }
        }
        else if (!strcmp(S.denoiser, "hqdn3d")) {
            build_hqdn3d_filter(&vf, S.denoise_strength);
        }
        else if (!strcmp(S.denoiser, "nlmeans")) {
            build_nlmeans_filter(&vf, S.denoise_strength);
        }
        else if (!strcmp(S.denoiser, "atadenoise")) {
            build_atadenoise_filter(&vf, S.denoise_strength);
        }
    }
    
    
    if (!img && !S.no_interpolate) {
        if (!strcmp(S.fps, "source") || !strcmp(S.fps, "lock")) {
            sb_fmt(&vf, "minterpolate=mi_mode=%s:mc_mode=aobmc:me_mode=bidir:vsbmc=1,", S.mi_mode);
        } else {
            sb_fmt(&vf, "minterpolate=fps=%s:mi_mode=%s:mc_mode=aobmc:me_mode=bidir:vsbmc=1,", S.fps, S.mi_mode);
        }
    }
    
    if (!strcmp(S.scaler, "zscale")) {
        sb_fmt(&vf, "zscale=w=trunc(iw*%s/2)*2:h=trunc(ih*%s/2)*2:filter=lanczos:dither=error_diffusion,", S.scale_factor, S.scale_factor);
    } else if (!strcmp(S.scaler, "ai")) {
        if (!strcmp(S.ai_backend, "sr")) {
            sb_fmt(&vf, "sr=dnn_backend=%s:model='%s'", S.dnn_backend, S.ai_model);
            if (!strcmp(S.ai_model_type, "srcnn")) sb_fmt(&vf, ":scale_factor=%s", S.scale_factor);
            sb_append(&vf, ",");
        } else {
            sb_fmt(&vf, "dnn_processing=dnn_backend=%s:model='%s':input=x:output=y,", S.dnn_backend, S.ai_model);
        }
    } else if (!strcmp(S.scaler, "hw")) {
        if (!strcmp(S.hwaccel,"cuda")) {
            sb_fmt(&vf, "scale_npp=trunc(iw*%s/2)*2:trunc(ih*%s/2)*2,", S.scale_factor, S.scale_factor);
        } else {
            sb_fmt(&vf, "scale=trunc(iw*%s/2)*2:trunc(ih*%s/2)*2:flags=lanczos,", S.scale_factor, S.scale_factor);
        }
    } else {
        sb_fmt(&vf, "scale=trunc(iw*%s/2)*2:trunc(ih*%s/2)*2:flags=lanczos+accurate_rnd,", S.scale_factor, S.scale_factor);
    }
    
    if (!S.no_sharpen) {
        if (!strcmp(S.sharpen_method, "unsharp")) {
            sb_fmt(&vf, "unsharp=%s:%s:%s,", S.usm_radius, S.usm_radius, S.usm_amount);
        }
        else sb_fmt(&vf, "cas=strength=%s,", S.sharpen_strength);
    }
    
    if (!S.no_deband) {
        if (!strcmp(S.deband_method, "gradfun")) sb_fmt(&vf, "gradfun=%s,", S.deband_strength);
        else if (!strcmp(S.deband_method, "f3kdb")) {
            
            double y = atof(S.f3kdb_y);
            double cb = atof(S.f3kdb_cbcr);
            double range = atof(S.f3kdb_range);
            
            double thr_y = y > 0 ? y / 2000.0 : 0.03;
            double thr_c = cb > 0 ? cb / 2000.0 : 0.015;
            
            if (thr_y > 0.5) thr_y = 0.5;
            if (thr_c > 0.5) thr_c = 0.5;
            if (thr_y < 0.001) thr_y = 0.001;
            
            int r = (int)range;
            if (r < 1) r = 16;
            
            sb_fmt(&vf, "deband=1thr=%.5f:2thr=%.5f:3thr=%.5f:range=%d:blur=0,", thr_y, thr_c, thr_c, r);
        }
        else sb_fmt(&vf, "deband=1thr=%s:b=1,", S.deband_strength);
    }
        if (S.use_dering_2 && S.dering_active_2) {
            build_dering_filter(&vf, S.dering_strength_2);
        }
        
    if (S.use_denoise_2 && !S.no_denoise) {
        if (!strcmp(S.denoiser_2, "bm3d")) {
            if (!strcmp(S.denoise_strength_2, "auto")) sb_append(&vf, "bm3d=estim=final:planes=1,");
            else {
                double sigma = parse_strength(S.denoise_strength_2);
                if (sigma <= 0) sigma = 2.5;
                if (sigma > 20.0) sigma = 20.0;
                sb_fmt(&vf, "bm3d=sigma=%.2f:estim=basic:planes=1,", sigma);
            }
        }
        else if (!strcmp(S.denoiser_2, "hqdn3d")) {
            build_hqdn3d_filter(&vf, S.denoise_strength_2);
        }
        else if (!strcmp(S.denoiser_2, "nlmeans")) {
            build_nlmeans_filter(&vf, S.denoise_strength_2);
        }
        else if (!strcmp(S.denoiser_2, "atadenoise")) {
            build_atadenoise_filter(&vf, S.denoise_strength_2);
        }
    }
    
    if (S.use_sharpen_2 && !S.no_sharpen) {
        if (!strcmp(S.sharpen_method_2, "unsharp")) {
            sb_fmt(&vf, "unsharp=%s:%s:%s,", S.usm_radius_2, S.usm_radius_2, S.usm_amount_2);
        }
        else sb_fmt(&vf, "cas=strength=%s,", S.sharpen_strength_2);
    }
    
    if (S.use_deband_2 && !S.no_deband) {
        if (!strcmp(S.deband_method_2, "gradfun")) sb_fmt(&vf, "gradfun=%s,", S.deband_strength_2);
        else if (!strcmp(S.deband_method_2, "f3kdb")) {
            
            double y = atof(S.f3kdb_y_2);
            double cb = atof(S.f3kdb_cbcr_2);
            double range = atof(S.f3kdb_range_2);
            
            double thr_y = y > 0 ? y / 2000.0 : 0.03;
            double thr_c = cb > 0 ? cb / 2000.0 : 0.015;
            
            if (thr_y > 0.5) thr_y = 0.5;
            if (thr_c > 0.5) thr_c = 0.5;
            if (thr_y < 0.001) thr_y = 0.001;
            
            int r = (int)range;
            if (r < 1) r = 16;
            
            sb_fmt(&vf, "deband=1thr=%.5f:2thr=%.5f:3thr=%.5f:range=%d:blur=0,", thr_y, thr_c, thr_c, r);
        }
        else sb_fmt(&vf, "deband=1thr=%s:b=1,", S.deband_strength_2);
    }
    if (!S.no_grain) {
        if (S.use_grain_2) sb_fmt(&vf, "noise=alls=%s:allf=t,", S.grain_strength_2);
        else sb_fmt(&vf, "noise=alls=%s:allf=t,", S.grain_strength);
    }
    
    
    const char *pix = S.use10 ? "yuv420p10le" : "yuv420p";
    if (S.use10 && (!strcmp(S.encoder,"nvenc") || !strcmp(S.encoder,"hevc_nvenc"))) pix="p010le";
    if (S.pci_safe_mode) pix = "yuv420p";
    
    if (!img) {
        
        sb_fmt(&vf, "format=%s,", pix);
        if (S.use10 && !S.pci_safe_mode) {
            
            sb_append(&vf, "limiter=min=64:max=940:planes=15,");
        } else {
            
            sb_append(&vf, "limiter=min=16:max=235:planes=15,");
        }
        sb_append(&vf, "setsar=1,");
    } else {
        
        
    }
    
    
    if (vf.buf && vf.len > 0 && vf.buf[vf.len-1] == ',') {
        vf.buf[vf.len-1] = '\0';
        vf.len--;
    }
    
    char *args[128]; int a=0;
    args[a++] = (char*)ffmpeg; args[a++] = "-hide_banner"; args[a++] = "-loglevel"; args[a++] = "error"; args[a++] = "-stats"; args[a++] = "-y";
    if (strcmp(S.hwaccel,"none")) {
        args[a++] = "-hwaccel"; args[a++] = S.hwaccel;
        if (!strcmp(S.hwaccel, "videotoolbox")) {
        }
    }
    args[a++] = "-i"; args[a++] = (char*)in;
    
    char complex_filter[8192];
    if (S.preview) {
        snprintf(complex_filter, sizeof(complex_filter), "[0:v]%s,split=2[main][prev]", vf.buf);
        args[a++] = "-filter_complex"; args[a++] = complex_filter;
        args[a++] = "-map"; args[a++] = "[main]";
        args[a++] = "-map"; args[a++] = "0:a?";
    } else {
        args[a++] = "-vf"; args[a++] = vf.buf;
        args[a++] = "-map"; args[a++] = "0:v:0";
        args[a++] = "-map"; args[a++] = "0:a?";
    }
    if (!img) {
        char *cod = "libx264";
        if (!strcmp(S.codec, "hevc")) {
            if (!strcmp(S.encoder, "nvenc")) cod = "hevc_nvenc"; else if (!strcmp(S.encoder, "qsv")) cod = "hevc_qsv"; else if (!strcmp(S.encoder, "vaapi")) cod = "hevc_vaapi"; else cod = "libx265";
        } else { if (!strcmp(S.encoder, "nvenc")) cod = "h264_nvenc"; else if (!strcmp(S.encoder, "qsv")) cod = "h264_qsv"; else if (!strcmp(S.encoder, "vaapi")) cod = "h264_vaapi"; }
        
        args[a++] = "-c:v"; args[a++] = cod;
        if (strstr(cod, "hevc") || strstr(cod, "265")) { args[a++] = "-tag:v"; args[a++] = "hvc1"; }
        args[a++] = "-pix_fmt"; args[a++] = (char*)pix;
        if (*S.threads) { args[a++] = "-threads"; args[a++] = S.threads; }
        
        char x265_fixed[256];
        if (!strstr(cod, "vaapi")) { args[a++] = "-preset"; args[a++] = S.preset; args[a++] = "-crf"; args[a++] = S.crf; }
        if (!strcmp(cod, "libx265") && *S.x265_params) {
            safe_copy(x265_fixed, S.x265_params, sizeof(x265_fixed));
            
            for (char *p = x265_fixed; *p; p++) {
                if (*p == ',') {
                    char *next = p + 1;
                    while (*next == ' ' || *next == '\t') next++;
                    int is_param_separator = 0;
                    char *check = next;
                    while (*check && *check != ',' && *check != ':') {
                        if (*check == '=') {
                            is_param_separator = 1;
                            break;
                        }
                        check++;
                    }
                    if (is_param_separator) {
                        *p = ':';
                    }
                    
                }
            }
            args[a++] = "-x265-params";
            args[a++] = x265_fixed;
        }
        
        args[a++] = "-c:a"; args[a++] = "aac"; args[a++] = "-b:a"; args[a++] = S.audio_bitrate;
        if (*S.movflags) { args[a++] = "-movflags"; args[a++] = S.movflags; }
    } else {
        args[a++] = "-frames:v"; args[a++] = "1";
    }
    args[a++] = out;
    
    if (S.preview) {
        args[a++] = "-map"; args[a++] = "[prev]";
        args[a++] = "-c:v"; args[a++] = "rawvideo";
        args[a++] = "-f"; args[a++] = "sdl";
        args[a++] = "Live Preview";
    }
    args[a] = NULL;
    
    char msg_buf[1024];
    snprintf(msg_buf, sizeof(msg_buf), "Processing: %s\n", in);
    
    if (global_log_cb) {
        // === MODE: LIBRARY (Swift App) ===
        global_log_cb(msg_buf);
        
        if (DRY_RUN) {
            char cmd_buf[8192];
            int pos = snprintf(cmd_buf, sizeof(cmd_buf), "CMD: ");
            for(int i=0; args[i]; i++) {
                pos += snprintf(cmd_buf + pos, sizeof(cmd_buf) - pos, "%s ", args[i]);
            }
            snprintf(cmd_buf + pos, sizeof(cmd_buf) - pos, "\n");
            global_log_cb(cmd_buf);
        } else {
            int result = execute_ffmpeg_command(args);
            
            if (result != 0) {
                char err[128];
                snprintf(err, sizeof(err), "FFmpeg failed with exit code %d\n", result);
                global_log_cb(err);
            } else {
                global_log_cb("Done.\n");
            }
        }
    }
    free(vf.buf);
}


void process_directory(const char *dir, const char *ffmpeg) {
    DIR *d = opendir(dir); if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (up60p_is_cancelled()) break;
        if (e->d_name[0] == '.') continue;
        char path[PATH_MAX]; snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);
        struct stat st;
        if (stat(path, &st) == 0) {
            if (S_ISDIR(st.st_mode)) process_directory(path, ffmpeg);
            else if (strstr(path, ".mp4") || strstr(path, ".mkv") || strstr(path, ".mov") || is_image(path)) process_file(path, ffmpeg, true);
        }
    } closedir(d);
}


void up60p_set_dry_run(int enable) {
    DRY_RUN = enable;
}

up60p_error up60p_init(const char *app_support_dir, up60p_log_callback log_cb) {
    (void)app_support_dir;
    global_log_cb = log_cb;
    init_paths();
    set_defaults();
    if (!get_bundled_ffmpeg_path()) {
        fprintf(stderr, "Fatal: bundled ffmpeg binary not found\n");
        return 1;
    }
    
    char name[64];
    
    return UP60P_OK;
}

void up60p_default_options(up60p_options *out_opts) {
    if (!out_opts) return;
    up60p_options_from_settings(out_opts, &S);
}

up60p_error up60p_process_path(const char *input_path,
                               const up60p_options *opts)
{
    if (!input_path || !opts) return UP60P_ERR_INVALID_OPTIONS;
    
    cancel_requested = 0;
    
    settings_from_up60p_options(&S, opts);
    
    struct stat st;
    if (stat(input_path, &st) == 0) {
        if (S_ISDIR(st.st_mode)) {
            process_directory(input_path, get_bundled_ffmpeg_path());
        } else {
            process_file(input_path, get_bundled_ffmpeg_path(), false);
        }
        return UP60P_OK;
    }
    
    return UP60P_ERR_INVALID_OPTIONS;
}

void up60p_shutdown(void) {}
