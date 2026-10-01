#include "up60p_settings.h"
#include "up60p_utils.h"
#include "up60p.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <termios.h>
#include "up60p_ffmpeg_path.h"
#include "up60p_process.h"
#include <pthread.h>

Settings DEF;
Settings S;

int execute_ffmpeg_command(char *const argv[]) {
    const char *bundled_ffmpeg = up60p_bundled_ffmpeg_path();
    if (!bundled_ffmpeg || !argv || !argv[0] ||
        strcmp(argv[0], bundled_ffmpeg) != 0) {
        if (global_log_cb) global_log_cb("Bundled FFmpeg is missing or invalid; external executables are not supported.\n");
        return -1;
    }
    char executable[PATH_MAX], supervisor[PATH_MAX];
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size) != 0 ||
        !up60p_resolve_bundled_executable(executable, "up60p-ffmpeg-supervisor", supervisor, sizeof(supervisor))) {
        if (global_log_cb) global_log_cb("Bundled FFmpeg supervisor is missing or invalid. Reinstall the app.\n");
        return -1;
    }
    return up60p_execute_owned_process(supervisor, argv, global_log_cb);
}

static pthread_mutex_t processing_lock = PTHREAD_MUTEX_INITIALIZER;
static char FFMPEG_PATH[PATH_MAX] = {0};
int DRY_RUN = 0;

const char *up60p_bundled_ffmpeg_path(void) {
    char exe_path[PATH_MAX];
    uint32_t size = sizeof(exe_path);
    if (_NSGetExecutablePath(exe_path, &size) != 0 ||
        !up60p_resolve_bundled_ffmpeg(exe_path, FFMPEG_PATH, sizeof(FFMPEG_PATH))) {
        FFMPEG_PATH[0] = '\0';
        return NULL;
    }
    
    return FFMPEG_PATH;
}

static up60p_error process_file(const char *in, const char *ffmpeg, bool batch);
static up60p_error process_directory(const char *dir, const char *ffmpeg);
//static int ar_menu_choose(const char *prompt, const char **items, int n, int start_index);

typedef struct { struct termios orig; int fd; bool ok; } TermCtx;


static void prompt_edit(const char *name, char *buf, size_t sz) {
    fprintf(stderr, "Enter value for %s [current: %s]: ", name, buf);
    char line[1024];
    if (fgets(line, sizeof(line), stdin)) {
        size_t n = strlen(line); while(n > 0 && isspace(line[n-1])) line[--n] = 0;
        if (n > 0) snprintf(buf, sz, "%s", line);
    }
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


static up60p_error process_file(const char *in, const char *ffmpeg, bool batch) {
    (void)batch; char outdir[PATH_MAX], base[PATH_MAX], out[PATH_MAX];
    bool img = is_image(in);
    
    if (up60p_is_cancelled()) return UP60P_ERR_CANCELLED;
    
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
    
    sb_fmt(&vf, "scale=trunc(iw*%s/2)*2:trunc(ih*%s/2)*2:flags=lanczos+accurate_rnd,", S.scale_factor, S.scale_factor);

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
    
    if (global_log_cb) global_log_cb(msg_buf);
    up60p_error status = UP60P_OK;
    if (DRY_RUN) {
        char cmd_buf[8192];
        size_t pos = (size_t)snprintf(cmd_buf, sizeof(cmd_buf), "CMD: ");
        for (int i = 0; args[i] && pos < sizeof(cmd_buf) - 1; i++) {
            int n = snprintf(cmd_buf + pos, sizeof(cmd_buf) - pos, "%s ", args[i]);
            if (n < 0 || (size_t)n >= sizeof(cmd_buf) - pos) break;
            pos += (size_t)n;
        }
        if (global_log_cb) global_log_cb(cmd_buf);
    } else {
        int result = execute_ffmpeg_command(args);
        if (result == UP60P_PROCESS_CANCELLED || up60p_is_cancelled()) {
            status = UP60P_ERR_CANCELLED;
            if (global_log_cb) global_log_cb("Processing cancelled.\n");
        } else if (result != 0) {
            char message[128];
            snprintf(message, sizeof(message), "FFmpeg failed with exit code %d\n", result);
            if (global_log_cb) global_log_cb(message);
            status = UP60P_ERR_IO;
        } else if (global_log_cb) {
            global_log_cb("Done.\n");
        }
    }
    free(vf.buf);
    return status;
}

static up60p_error process_directory(const char *dir, const char *ffmpeg) {
    DIR *d = opendir(dir);
    if (!d) return UP60P_ERR_IO;
    up60p_error status = UP60P_OK;
    struct dirent *entry;
    while ((entry = readdir(d))) {
        if (up60p_is_cancelled()) { status = UP60P_ERR_CANCELLED; break; }
        if (entry->d_name[0] == '.') continue;
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s/%s", dir, entry->d_name);
        struct stat st;
        if (stat(path, &st) != 0) { status = UP60P_ERR_IO; break; }
        if (S_ISDIR(st.st_mode)) status = process_directory(path, ffmpeg);
        else if (strstr(path, ".mp4") || strstr(path, ".mkv") || strstr(path, ".mov") || is_image(path)) {
            status = process_file(path, ffmpeg, true);
        }
        if (status != UP60P_OK) break;
    }
    closedir(d);
    return status;
}


void up60p_set_dry_run(int enable) {
    DRY_RUN = enable;
}

up60p_error up60p_init(const char *app_support_dir, up60p_log_callback log_cb) {
    (void)app_support_dir;
    global_log_cb = log_cb;
    init_paths();
    set_defaults();
    const char *ffmpeg = up60p_bundled_ffmpeg_path();
    if (!ffmpeg) {
        if (global_log_cb) global_log_cb("Bundled FFmpeg is missing or invalid at Contents/MacOS/ThirdParty/FFmpeg/ffmpeg. Reinstall the app; external FFmpeg is not supported.\n");
        return UP60P_ERR_FFMPEG_NOT_FOUND;
    }
    if (global_log_cb) {
        char message[PATH_MAX + 32];
        snprintf(message, sizeof(message), "Using bundled FFmpeg: %s\n", ffmpeg);
        global_log_cb(message);
    }
    
//    char name[64];
    
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
    /* Only Lanczos is supported by this app's pinned FFmpeg engine. CoreML
     * runs in Swift. Do not execute legacy SR/DNN, zscale, or hardware modes. */
    if (strncmp(opts->scaler, "lanczos", sizeof(opts->scaler)) != 0) {
        if (global_log_cb) global_log_cb("Selected upscaling mode is unsupported by the bundled FFmpeg engine. Choose Lanczos.\n");
        return UP60P_ERR_UNSUPPORTED_SCALER;
    }
    const char *ffmpeg = up60p_bundled_ffmpeg_path();
    if (!ffmpeg) return UP60P_ERR_FFMPEG_NOT_FOUND;
    
    if (pthread_mutex_trylock(&processing_lock) != 0) return UP60P_ERR_INTERNAL;
    up60p_reset_cancel();
    settings_from_up60p_options(&S, opts);
    up60p_error result = UP60P_ERR_INVALID_OPTIONS;
    struct stat st;
    if (stat(input_path, &st) == 0) {
        result = S_ISDIR(st.st_mode) ? process_directory(input_path, ffmpeg) : process_file(input_path, ffmpeg, false);
    }
    pthread_mutex_unlock(&processing_lock);
    return result;
}

void up60p_shutdown(void) {
    up60p_request_cancel();
    up60p_stop_processes();
}
