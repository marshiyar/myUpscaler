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
#include <mach-o/dyld.h>
#include <limits.h>


#include "upscaler/up60p.h"


#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

static volatile sig_atomic_t cancel_requested = 0;

static const char *SCRIPT_NAME = "up60p_restore_beast";
static char FFMPEG_PATH_BUF[PATH_MAX];
int DRY_RUN = 0;


static void safe_copy(char *dst, const char *src, size_t size) {
    if (size == 0) return;
    strncpy(dst, src, size - 1);
    dst[size - 1] = '\0';
}


static const char* get_bundled_ffmpeg_path(void) {
    char bundle_path[PATH_MAX];
    uint32_t size = sizeof(bundle_path);
    
    
    const char *env = getenv("UP60P_FFMPEG");
    if (!env || !*env) {
        env = getenv("FFMPEG_PATH");
    }
    if (env && *env && access(env, X_OK) == 0) {
        safe_copy(FFMPEG_PATH_BUF, env, sizeof(FFMPEG_PATH_BUF));
        return FFMPEG_PATH_BUF;
    }

    
    
    if (_NSGetExecutablePath(bundle_path, &size) == 0) {
        char *exe_dir = dirname(bundle_path);
        
        
        char resources_ffmpeg[PATH_MAX];
        snprintf(resources_ffmpeg, sizeof(resources_ffmpeg), "%s/../../Contents/Resources/ffmpeg", exe_dir);
        if (access(resources_ffmpeg, X_OK) == 0) {
            
            char resolved[PATH_MAX];
            if (realpath(resources_ffmpeg, resolved) != NULL) {
                safe_copy(FFMPEG_PATH_BUF, resolved, sizeof(FFMPEG_PATH_BUF));
                return FFMPEG_PATH_BUF;
            }
        }
        
        
        char macos_ffmpeg[PATH_MAX];
        snprintf(macos_ffmpeg, sizeof(macos_ffmpeg), "%s/../../Contents/MacOS/ffmpeg", exe_dir);
        if (access(macos_ffmpeg, X_OK) == 0) {
            char resolved[PATH_MAX];
            if (realpath(macos_ffmpeg, resolved) != NULL) {
                safe_copy(FFMPEG_PATH_BUF, resolved, sizeof(FFMPEG_PATH_BUF));
                return FFMPEG_PATH_BUF;
            }
        }
        
        
        char lib_ffmpeg[PATH_MAX];
        snprintf(lib_ffmpeg, sizeof(lib_ffmpeg), "%s/../../Contents/Resources/lib/ffmpeg", exe_dir);
        if (access(lib_ffmpeg, X_OK) == 0) {
            char resolved[PATH_MAX];
            if (realpath(lib_ffmpeg, resolved) != NULL) {
                safe_copy(FFMPEG_PATH_BUF, resolved, sizeof(FFMPEG_PATH_BUF));
                return FFMPEG_PATH_BUF;
            }
        }
    }

    
    const char *candidates[] = {
        "/opt/homebrew/bin/ffmpeg",  
        "/usr/local/bin/ffmpeg",     
        "/usr/bin/ffmpeg"           
    };

    for (int i = 0; i < (int)(sizeof(candidates) / sizeof(candidates[0])); i++) {
        if (access(candidates[i], X_OK) == 0) {
            safe_copy(FFMPEG_PATH_BUF, candidates[i], sizeof(FFMPEG_PATH_BUF));
            return FFMPEG_PATH_BUF;
        }
    }

    
    
    FILE *fp = popen("which ffmpeg 2>/dev/null", "r");
    if (fp != NULL) {
        char path[PATH_MAX];
        if (fgets(path, sizeof(path), fp) != NULL) {
            
            size_t len = strlen(path);
            if (len > 0 && path[len - 1] == '\n') {
                path[len - 1] = '\0';
            }
            
            if (len > 1 && access(path, X_OK) == 0) {
                pclose(fp);
                safe_copy(FFMPEG_PATH_BUF, path, sizeof(FFMPEG_PATH_BUF));
                return FFMPEG_PATH_BUF;
            }
        }
        pclose(fp);
    }
    
    
    FFMPEG_PATH_BUF[0] = '\0';
    return NULL;
}


#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
#define ARR_LEN(a) ((int)(sizeof(a)/sizeof((a)[0])))

#define C_RESET   "\033[0m"
#define C_BOLD    "\033[1m"
#define C_RED     "\033[31m"
#define C_GREEN   "\033[32m"
#define C_YELLOW  "\033[33m"
#define C_CYAN    "\033[36m"



static const char *HELP_TEXT =
"%s v4.9 — The Ultimate AI Restoration Pipeline\n"
"\n"
"USAGE:\n"
"  ./%s <input> [options]\n"
"  ./%s --settings\n"
"\n"
"CODEC / RATE CONTROL:\n"
"  --hevc                   Use HEVC/H.265 (default: H.264)\n"
"  --crf <0-51>             Constant Rate Factor (default 16)\n"
"  --preset <name>          Encoder preset (default slow)\n"
"  --10bit                  Output yuv420p10le (or p010le for HW)\n"
"  --x265-params <str>      Pass args to x265 (e.g. 'aq-mode=3:psy-rd=2.0')\n"
"\n"
"FRAME / SCALE:\n"
"  --fps <1-240|source>     Target FPS (default: 60). Use 'source' to lock FPS.\n"
"  --scale <0.1-10>         Upscale factor (default: 2).\n"
"  --mi-mode <mci|blend>    Interpolation method (default: mci)\n"
"\n"
"AI UPSCALING:\n"
"  --scaler <ai|lanczos|zscale|hw> Select upscaler (default: ai)\n"
"  --ai-backend <sr|dnn>    AI filter choice (default: sr).\n"
"  --ai-model <file>        Path to model (.pb/.model). Required for --scaler ai.\n"
"  --dnn-backend <name>     native|tensorflow|openvino\n"
"\n"
"FILTERS (Denoise/Deblock/Sharpen):\n"
"  --denoiser <bm3d|nlmeans|hqdn3d|atadenoise> (default: bm3d)\n"
"  --denoise-strength <f|auto>  Sigma value or 'auto' (default: 2.5)\n"
"  --dering                 Enable ringing artifact removal\n"
"  --sharpen-method <cas|unsharp>\n"
"  --usm-radius <3-23>      Unsharp Mask Radius (default: 5)\n"
"  --deband-method <deband|gradfun|f3kdb>\n"
"  --f3kdb-range <1-50>     F3KDB Range (default: 15)\n"
"\n"
"COLOR / I/O:\n"
"  --lut <file>             Path to .cube 3D LUT\n"
"  --movflags <flags>       MOV container flags (default: +faststart)\n"
"  --preview                Enable Live View window during processing\n"
"  --pci-safe               Force yuv420p 8-bit for compatibility\n"
"\n"
"SETTINGS MODE:\n"
"  --settings               Launch interactive menu.\n";

static const char *MANUAL_TEXT = "Refer to interactive settings for full documentation.\n";


typedef struct {
    
    char codec[8]; char crf[16]; char preset[32];
    char fps[16]; 
    char scale_factor[16];
    
    
    char scaler[16]; char ai_backend[16]; char ai_model[PATH_MAX];
    char ai_model_type[16]; char dnn_backend[32];

    
    char denoiser[16]; char denoise_strength[16];
    char deblock_mode[16]; char deblock_thresh[64];
    int  dering_active; char dering_strength[16];

    char sharpen_method[16]; char sharpen_strength[32];
    char usm_radius[16]; char usm_amount[16]; char usm_threshold[16];

    char deband_method[16]; 
    char deband_strength[32];
    char f3kdb_range[16]; char f3kdb_y[16]; char f3kdb_cbcr[16];

    char grain_strength[16];
    
    
    char denoiser_2[16]; char denoise_strength_2[16];
    char deblock_mode_2[16]; char deblock_thresh_2[64];
    int  dering_active_2; char dering_strength_2[16];

    char sharpen_method_2[16]; char sharpen_strength_2[32];
    char usm_radius_2[16]; char usm_amount_2[16]; char usm_threshold_2[16];

    char deband_method_2[16];
    char deband_strength_2[32];
    char f3kdb_range_2[16]; char f3kdb_y_2[16]; char f3kdb_cbcr_2[16];

    char grain_strength_2[16];
    
    
    int use_denoise_2;
    int use_deblock_2;
    int use_dering_2;
    int use_sharpen_2;
    int use_deband_2;
    int use_grain_2;

    char mi_mode[16];

    char eq_contrast[16]; char eq_brightness[16]; char eq_saturation[16];
    char lut3d_file[PATH_MAX];

    char x265_params[256];

    
    char outdir[PATH_MAX]; char audio_bitrate[32]; char threads[16];
    char movflags[32];
    int  use10;
    int  preview;

    
    int no_deblock, no_denoise, no_decimate, no_interpolate;
    int no_sharpen, no_deband, no_eq, no_grain;
    int pci_safe_mode;

    
    char hwaccel[16]; char encoder[16];
} Settings;

static Settings DEF;
static Settings S;

static char GPTPRO_PRESET_DIR[PATH_MAX];
static char GPTPRO_ACTIVE_FILE[PATH_MAX];

#ifdef UP60P_LIBRARY_MODE

void (*global_log_cb)(const char *) = NULL;


void log_message(const char *format, ...) {
    if (global_log_cb) {
        char buffer[4096];
        va_list args;
        va_start(args, format);
        vsnprintf(buffer, sizeof(buffer), format, args);
        va_end(args);
        global_log_cb(buffer);
    } else {
        va_list args;
        va_start(args, format);
        vprintf(format, args);
        va_end(args);
    }
}
#endif


static void up60p_options_from_settings(up60p_options *dst, const Settings *src) {
    if (!dst || !src) return;
    memset(dst, 0, sizeof(*dst));

    
    snprintf(dst->codec,        sizeof(dst->codec),        "%s", src->codec);
    snprintf(dst->crf,          sizeof(dst->crf),          "%s", src->crf);
    snprintf(dst->preset,       sizeof(dst->preset),       "%s", src->preset);
    snprintf(dst->fps,          sizeof(dst->fps),          "%s", src->fps);
    snprintf(dst->scale_factor, sizeof(dst->scale_factor), "%s", src->scale_factor);

    
    snprintf(dst->scaler,       sizeof(dst->scaler),       "%s", src->scaler);
    snprintf(dst->ai_backend,   sizeof(dst->ai_backend),   "%s", src->ai_backend);
    snprintf(dst->ai_model,     sizeof(dst->ai_model),     "%s", src->ai_model);
    snprintf(dst->ai_model_type,sizeof(dst->ai_model_type),"%s", src->ai_model_type);
    snprintf(dst->dnn_backend,  sizeof(dst->dnn_backend),  "%s", src->dnn_backend);

    
    snprintf(dst->denoiser,         sizeof(dst->denoiser),         "%s", src->denoiser);
    snprintf(dst->denoise_strength, sizeof(dst->denoise_strength), "%s", src->denoise_strength);
    snprintf(dst->deblock_mode,     sizeof(dst->deblock_mode),     "%s", src->deblock_mode);
    snprintf(dst->deblock_thresh,   sizeof(dst->deblock_thresh),   "%s", src->deblock_thresh);
    dst->dering_active = src->dering_active;
    snprintf(dst->dering_strength,  sizeof(dst->dering_strength),  "%s", src->dering_strength);

    snprintf(dst->sharpen_method,   sizeof(dst->sharpen_method),   "%s", src->sharpen_method);
    snprintf(dst->sharpen_strength, sizeof(dst->sharpen_strength), "%s", src->sharpen_strength);
    snprintf(dst->usm_radius,       sizeof(dst->usm_radius),       "%s", src->usm_radius);
    snprintf(dst->usm_amount,       sizeof(dst->usm_amount),       "%s", src->usm_amount);
    snprintf(dst->usm_threshold,    sizeof(dst->usm_threshold),    "%s", src->usm_threshold);

    snprintf(dst->deband_method,    sizeof(dst->deband_method),    "%s", src->deband_method);
    snprintf(dst->deband_strength,  sizeof(dst->deband_strength),  "%s", src->deband_strength);
    snprintf(dst->f3kdb_range,      sizeof(dst->f3kdb_range),      "%s", src->f3kdb_range);
    snprintf(dst->f3kdb_y,          sizeof(dst->f3kdb_y),          "%s", src->f3kdb_y);
    snprintf(dst->f3kdb_cbcr,       sizeof(dst->f3kdb_cbcr),       "%s", src->f3kdb_cbcr);

    snprintf(dst->grain_strength,   sizeof(dst->grain_strength),   "%s", src->grain_strength);

    
    snprintf(dst->denoiser_2,         sizeof(dst->denoiser_2),         "%s", src->denoiser_2);
    snprintf(dst->denoise_strength_2, sizeof(dst->denoise_strength_2), "%s", src->denoise_strength_2);
    snprintf(dst->deblock_mode_2,     sizeof(dst->deblock_mode_2),     "%s", src->deblock_mode_2);
    snprintf(dst->deblock_thresh_2,   sizeof(dst->deblock_thresh_2),   "%s", src->deblock_thresh_2);
    dst->dering_active_2 = src->dering_active_2;
    snprintf(dst->dering_strength_2,  sizeof(dst->dering_strength_2),  "%s", src->dering_strength_2);

    snprintf(dst->sharpen_method_2,   sizeof(dst->sharpen_method_2),   "%s", src->sharpen_method_2);
    snprintf(dst->sharpen_strength_2, sizeof(dst->sharpen_strength_2), "%s", src->sharpen_strength_2);
    snprintf(dst->usm_radius_2,       sizeof(dst->usm_radius_2),       "%s", src->usm_radius_2);
    snprintf(dst->usm_amount_2,       sizeof(dst->usm_amount_2),       "%s", src->usm_amount_2);
    snprintf(dst->usm_threshold_2,    sizeof(dst->usm_threshold_2),    "%s", src->usm_threshold_2);

    snprintf(dst->deband_method_2,    sizeof(dst->deband_method_2),    "%s", src->deband_method_2);
    snprintf(dst->deband_strength_2,  sizeof(dst->deband_strength_2),  "%s", src->deband_strength_2);
    snprintf(dst->f3kdb_range_2,      sizeof(dst->f3kdb_range_2),      "%s", src->f3kdb_range_2);
    snprintf(dst->f3kdb_y_2,          sizeof(dst->f3kdb_y_2),          "%s", src->f3kdb_y_2);
    snprintf(dst->f3kdb_cbcr_2,       sizeof(dst->f3kdb_cbcr_2),       "%s", src->f3kdb_cbcr_2);

    snprintf(dst->grain_strength_2,   sizeof(dst->grain_strength_2),   "%s", src->grain_strength_2);

    dst->use_denoise_2 = src->use_denoise_2;
    dst->use_deblock_2 = src->use_deblock_2;
    dst->use_dering_2  = src->use_dering_2;
    dst->use_sharpen_2 = src->use_sharpen_2;
    dst->use_deband_2  = src->use_deband_2;
    dst->use_grain_2   = src->use_grain_2;

    snprintf(dst->mi_mode, sizeof(dst->mi_mode), "%s", src->mi_mode);

    snprintf(dst->eq_contrast,   sizeof(dst->eq_contrast),   "%s", src->eq_contrast);
    snprintf(dst->eq_brightness, sizeof(dst->eq_brightness), "%s", src->eq_brightness);
    snprintf(dst->eq_saturation, sizeof(dst->eq_saturation), "%s", src->eq_saturation);
    snprintf(dst->lut3d_file,    sizeof(dst->lut3d_file),    "%s", src->lut3d_file);

    snprintf(dst->x265_params,   sizeof(dst->x265_params),   "%s", src->x265_params);

    snprintf(dst->outdir,        sizeof(dst->outdir),        "%s", src->outdir);
    snprintf(dst->audio_bitrate, sizeof(dst->audio_bitrate), "%s", src->audio_bitrate);
    snprintf(dst->threads,       sizeof(dst->threads),       "%s", src->threads);
    snprintf(dst->movflags,      sizeof(dst->movflags),      "%s", src->movflags);

    dst->use10    = src->use10;
    dst->preview  = src->preview;

    dst->no_deblock     = src->no_deblock;
    dst->no_denoise     = src->no_denoise;
    dst->no_decimate    = src->no_decimate;
    dst->no_interpolate = src->no_interpolate;
    dst->no_sharpen     = src->no_sharpen;
    dst->no_deband      = src->no_deband;
    dst->no_eq          = src->no_eq;
    dst->no_grain       = src->no_grain;
    dst->pci_safe_mode  = src->pci_safe_mode;

    snprintf(dst->hwaccel, sizeof(dst->hwaccel), "%s", src->hwaccel);
    snprintf(dst->encoder, sizeof(dst->encoder), "%s", src->encoder);
}

static void settings_from_up60p_options(Settings *dst, const up60p_options *src) {
    if (!dst || !src) return;

    *dst = DEF; 

    
    snprintf(dst->codec,        sizeof(dst->codec),        "%s", src->codec);
    snprintf(dst->crf,          sizeof(dst->crf),          "%s", src->crf);
    snprintf(dst->preset,       sizeof(dst->preset),       "%s", src->preset);
    snprintf(dst->fps,          sizeof(dst->fps),          "%s", src->fps);
    snprintf(dst->scale_factor, sizeof(dst->scale_factor), "%s", src->scale_factor);

    
    snprintf(dst->scaler,       sizeof(dst->scaler),       "%s", src->scaler);
    snprintf(dst->ai_backend,   sizeof(dst->ai_backend),   "%s", src->ai_backend);
    snprintf(dst->ai_model,     sizeof(dst->ai_model),     "%s", src->ai_model);
    snprintf(dst->ai_model_type,sizeof(dst->ai_model_type),"%s", src->ai_model_type);
    snprintf(dst->dnn_backend,  sizeof(dst->dnn_backend),  "%s", src->dnn_backend);

    
    snprintf(dst->denoiser,         sizeof(dst->denoiser),         "%s", src->denoiser);
    snprintf(dst->denoise_strength, sizeof(dst->denoise_strength), "%s", src->denoise_strength);
    snprintf(dst->deblock_mode,     sizeof(dst->deblock_mode),     "%s", src->deblock_mode);
    snprintf(dst->deblock_thresh,   sizeof(dst->deblock_thresh),   "%s", src->deblock_thresh);
    dst->dering_active = src->dering_active;
    snprintf(dst->dering_strength,  sizeof(dst->dering_strength),  "%s", src->dering_strength);

    snprintf(dst->sharpen_method,   sizeof(dst->sharpen_method),   "%s", src->sharpen_method);
    snprintf(dst->sharpen_strength, sizeof(dst->sharpen_strength), "%s", src->sharpen_strength);
    snprintf(dst->usm_radius,       sizeof(dst->usm_radius),       "%s", src->usm_radius);
    snprintf(dst->usm_amount,       sizeof(dst->usm_amount),       "%s", src->usm_amount);
    snprintf(dst->usm_threshold,    sizeof(dst->usm_threshold),    "%s", src->usm_threshold);

    snprintf(dst->deband_method,    sizeof(dst->deband_method),    "%s", src->deband_method);
    snprintf(dst->deband_strength,  sizeof(dst->deband_strength),  "%s", src->deband_strength);
    snprintf(dst->f3kdb_range,      sizeof(dst->f3kdb_range),      "%s", src->f3kdb_range);
    snprintf(dst->f3kdb_y,          sizeof(dst->f3kdb_y),          "%s", src->f3kdb_y);
    snprintf(dst->f3kdb_cbcr,       sizeof(dst->f3kdb_cbcr),       "%s", src->f3kdb_cbcr);

    snprintf(dst->grain_strength,   sizeof(dst->grain_strength),   "%s", src->grain_strength);

    
    snprintf(dst->denoiser_2,         sizeof(dst->denoiser_2),         "%s", src->denoiser_2);
    snprintf(dst->denoise_strength_2, sizeof(dst->denoise_strength_2), "%s", src->denoise_strength_2);
    snprintf(dst->deblock_mode_2,     sizeof(dst->deblock_mode_2),     "%s", src->deblock_mode_2);
    snprintf(dst->deblock_thresh_2,   sizeof(dst->deblock_thresh_2),   "%s", src->deblock_thresh_2);
    dst->dering_active_2 = src->dering_active_2;
    snprintf(dst->dering_strength_2,  sizeof(dst->dering_strength_2),  "%s", src->dering_strength_2);

    snprintf(dst->sharpen_method_2,   sizeof(dst->sharpen_method_2),   "%s", src->sharpen_method_2);
    snprintf(dst->sharpen_strength_2, sizeof(dst->sharpen_strength_2), "%s", src->sharpen_strength_2);
    snprintf(dst->usm_radius_2,       sizeof(dst->usm_radius_2),       "%s", src->usm_radius_2);
    snprintf(dst->usm_amount_2,       sizeof(dst->usm_amount_2),       "%s", src->usm_amount_2);
    snprintf(dst->usm_threshold_2,    sizeof(dst->usm_threshold_2),    "%s", src->usm_threshold_2);

    snprintf(dst->deband_method_2,    sizeof(dst->deband_method_2),    "%s", src->deband_method_2);
    snprintf(dst->deband_strength_2,  sizeof(dst->deband_strength_2),  "%s", src->deband_strength_2);
    snprintf(dst->f3kdb_range_2,      sizeof(dst->f3kdb_range_2),      "%s", src->f3kdb_range_2);
    snprintf(dst->f3kdb_y_2,          sizeof(dst->f3kdb_y_2),          "%s", src->f3kdb_y_2);
    snprintf(dst->f3kdb_cbcr_2,       sizeof(dst->f3kdb_cbcr_2),       "%s", src->f3kdb_cbcr_2);

    snprintf(dst->grain_strength_2,   sizeof(dst->grain_strength_2),   "%s", src->grain_strength_2);

    dst->use_denoise_2 = src->use_denoise_2;
    dst->use_deblock_2 = src->use_deblock_2;
    dst->use_dering_2  = src->use_dering_2;
    dst->use_sharpen_2 = src->use_sharpen_2;
    dst->use_deband_2  = src->use_deband_2;
    dst->use_grain_2   = src->use_grain_2;

    snprintf(dst->mi_mode, sizeof(dst->mi_mode), "%s", src->mi_mode);

    snprintf(dst->eq_contrast,   sizeof(dst->eq_contrast),   "%s", src->eq_contrast);
    snprintf(dst->eq_brightness, sizeof(dst->eq_brightness), "%s", src->eq_brightness);
    snprintf(dst->eq_saturation, sizeof(dst->eq_saturation), "%s", src->eq_saturation);
    snprintf(dst->lut3d_file,    sizeof(dst->lut3d_file),    "%s", src->lut3d_file);

    snprintf(dst->x265_params,   sizeof(dst->x265_params),   "%s", src->x265_params);

    snprintf(dst->outdir,        sizeof(dst->outdir),        "%s", src->outdir);
    snprintf(dst->audio_bitrate, sizeof(dst->audio_bitrate), "%s", src->audio_bitrate);
    snprintf(dst->threads,       sizeof(dst->threads),       "%s", src->threads);
    snprintf(dst->movflags,      sizeof(dst->movflags),      "%s", src->movflags);

    dst->use10    = src->use10;
    dst->preview  = src->preview;

    dst->no_deblock     = src->no_deblock;
    dst->no_denoise     = src->no_denoise;
    dst->no_decimate    = src->no_decimate;
    dst->no_interpolate = src->no_interpolate;
    dst->no_sharpen     = src->no_sharpen;
    dst->no_deband      = src->no_deband;
    dst->no_eq          = src->no_eq;
    dst->no_grain       = src->no_grain;
    dst->pci_safe_mode  = src->pci_safe_mode;

    snprintf(dst->hwaccel, sizeof(dst->hwaccel), "%s", src->hwaccel);
    snprintf(dst->encoder, sizeof(dst->encoder), "%s", src->encoder);
}


static void process_file(const char *in, const char *ffmpeg, bool batch);
static void process_directory(const char *dir, const char *ffmpeg);
static int ar_menu_choose(const char *prompt, const char **items, int n, int start_index);
static void set_defaults(void);
static void reset_to_factory(void);
static inline bool up60p_is_cancelled(void) { return cancel_requested != 0; }

static void sanitize_path(char *p) {
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

static void init_paths(void) {
    char xdg[PATH_MAX];
    const char *env = getenv("XDG_CONFIG_HOME");
    if (env && *env) {
        snprintf(xdg, sizeof(xdg), "%s", env);
    } else {
        const char *home = getenv("HOME");
        if (home && *home) {
            snprintf(xdg, sizeof(xdg), "%s/.config", home);
        } else {
            
            snprintf(xdg, sizeof(xdg), "/tmp");
        }
    }
    snprintf(GPTPRO_PRESET_DIR, sizeof(GPTPRO_PRESET_DIR), "%s/gptPro/presets", xdg);
    snprintf(GPTPRO_ACTIVE_FILE, sizeof(GPTPRO_ACTIVE_FILE), "%s/gptPro/active_preset", xdg);
}

static void mkdir_p(const char *path) {
    char tmp[PATH_MAX]; snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) { if (*p == '/') { *p = 0; mkdir(tmp, 0775); *p = '/'; } }
    mkdir(tmp, 0775);
}

static void set_defaults(void) {
    memset(&S, 0, sizeof(S));
    strcpy(S.codec, "h264"); strcpy(S.fps, "60"); strcpy(S.scale_factor, "2");
    strcpy(S.scaler, "lanczos"); strcpy(S.ai_backend, "sr"); strcpy(S.ai_model_type, "espcn"); strcpy(S.dnn_backend, "tensorflow");
    
    strcpy(S.denoiser, "bm3d"); strcpy(S.denoise_strength, "2.5");
    strcpy(S.deblock_mode, "strong");
    S.dering_active = 0; strcpy(S.dering_strength, "0.5");

    strcpy(S.sharpen_method, "cas"); strcpy(S.sharpen_strength, "0.25");
    strcpy(S.usm_radius, "5"); strcpy(S.usm_amount, "1.0"); strcpy(S.usm_threshold, "0.03");

    strcpy(S.deband_method, "deband"); strcpy(S.deband_strength, "0.015");
    strcpy(S.f3kdb_range, "15"); strcpy(S.f3kdb_y, "64"); strcpy(S.f3kdb_cbcr, "64");

    strcpy(S.grain_strength, "1.0");
    
    
    strcpy(S.denoiser_2, "bm3d"); strcpy(S.denoise_strength_2, "2.5");
    strcpy(S.deblock_mode_2, "strong");
    S.dering_active_2 = 0; strcpy(S.dering_strength_2, "0.5");

    strcpy(S.sharpen_method_2, "cas"); strcpy(S.sharpen_strength_2, "0.25");
    strcpy(S.usm_radius_2, "5"); strcpy(S.usm_amount_2, "1.0"); strcpy(S.usm_threshold_2, "0.03");

    strcpy(S.deband_method_2, "deband"); strcpy(S.deband_strength_2, "0.015");
    strcpy(S.f3kdb_range_2, "15"); strcpy(S.f3kdb_y_2, "64"); strcpy(S.f3kdb_cbcr_2, "64");

    strcpy(S.grain_strength_2, "1.0");
    S.use_denoise_2 = 0;
    S.use_deblock_2 = 0;
    S.use_dering_2 = 0;
    S.use_sharpen_2 = 0;
    S.use_deband_2 = 0;
    S.use_grain_2 = 0;
    strcpy(S.mi_mode, "mci");
    strcpy(S.eq_contrast, "1.03"); strcpy(S.eq_brightness, "0.005"); strcpy(S.eq_saturation, "1.06");
    strcpy(S.x265_params, "aq-mode=3,psy-rd=2.0,deblock=-2,-2");
    strcpy(S.audio_bitrate, "192k"); strcpy(S.movflags, "+faststart");
    strcpy(S.hwaccel, "none"); strcpy(S.encoder, "auto");
    S.preview = 0; S.pci_safe_mode = 0;
    DEF = S;
}

static void reset_to_factory(void) { S = DEF; }

static void save_preset_file(const char *name) {
    if (!name || !*name || strcmp(name, "factory") == 0) return;
    char file[PATH_MAX]; snprintf(file, sizeof(file), "%s/%s.preset", GPTPRO_PRESET_DIR, name);
    FILE *fp = fopen(file, "w"); if (!fp) return;
    fprintf(fp, "codec=\"%s\"\ncrf=\"%s\"\npreset=\"%s\"\nfps=\"%s\"\nscale_factor=\"%s\"\n", S.codec, S.crf, S.preset, S.fps, S.scale_factor);
    fprintf(fp, "scaler=\"%s\"\nai_backend=\"%s\"\nai_model=\"%s\"\nai_model_type=\"%s\"\ndnn_backend=\"%s\"\n", S.scaler, S.ai_backend, S.ai_model, S.ai_model_type, S.dnn_backend);
    
    fprintf(fp, "denoiser=\"%s\"\ndenoise_strength=\"%s\"\n", S.denoiser, S.denoise_strength);
    fprintf(fp, "deblock_mode=\"%s\"\ndeblock_thresh=\"%s\"\ndering_active=\"%d\"\ndering_strength=\"%s\"\n", S.deblock_mode, S.deblock_thresh, S.dering_active, S.dering_strength);
    
    fprintf(fp, "sharpen_method=\"%s\"\nsharpen_strength=\"%s\"\n", S.sharpen_method, S.sharpen_strength);
    fprintf(fp, "usm_radius=\"%s\"\nusm_amount=\"%s\"\nusm_threshold=\"%s\"\n", S.usm_radius, S.usm_amount, S.usm_threshold);

    fprintf(fp, "deband_method=\"%s\"\ndeband_strength=\"%s\"\n", S.deband_method, S.deband_strength);
    fprintf(fp, "f3kdb_range=\"%s\"\nf3kdb_y=\"%s\"\nf3kdb_cbcr=\"%s\"\n", S.f3kdb_range, S.f3kdb_y, S.f3kdb_cbcr);

    fprintf(fp, "grain_strength=\"%s\"\n", S.grain_strength);
    
    
    fprintf(fp, "denoiser_2=\"%s\"\ndenoise_strength_2=\"%s\"\n", S.denoiser_2, S.denoise_strength_2);
    fprintf(fp, "deblock_mode_2=\"%s\"\ndeblock_thresh_2=\"%s\"\ndering_active_2=\"%d\"\ndering_strength_2=\"%s\"\n", S.deblock_mode_2, S.deblock_thresh_2, S.dering_active_2, S.dering_strength_2);
    
    fprintf(fp, "sharpen_method_2=\"%s\"\nsharpen_strength_2=\"%s\"\n", S.sharpen_method_2, S.sharpen_strength_2);
    fprintf(fp, "usm_radius_2=\"%s\"\nusm_amount_2=\"%s\"\nusm_threshold_2=\"%s\"\n", S.usm_radius_2, S.usm_amount_2, S.usm_threshold_2);

    fprintf(fp, "deband_method_2=\"%s\"\ndeband_strength_2=\"%s\"\n", S.deband_method_2, S.deband_strength_2);
    fprintf(fp, "f3kdb_range_2=\"%s\"\nf3kdb_y_2=\"%s\"\nf3kdb_cbcr_2=\"%s\"\n", S.f3kdb_range_2, S.f3kdb_y_2, S.f3kdb_cbcr_2);

    fprintf(fp, "grain_strength_2=\"%s\"\n", S.grain_strength_2);
    fprintf(fp, "use_denoise_2=\"%d\"\nuse_deblock_2=\"%d\"\nuse_dering_2=\"%d\"\n", S.use_denoise_2, S.use_deblock_2, S.use_dering_2);
    fprintf(fp, "use_sharpen_2=\"%d\"\nuse_deband_2=\"%d\"\nuse_grain_2=\"%d\"\n", S.use_sharpen_2, S.use_deband_2, S.use_grain_2);
    fprintf(fp, "mi_mode=\"%s\"\neq_contrast=\"%s\"\neq_brightness=\"%s\"\neq_saturation=\"%s\"\n", S.mi_mode, S.eq_contrast, S.eq_brightness, S.eq_saturation);
    fprintf(fp, "lut3d_file=\"%s\"\nx265_params=\"%s\"\n", S.lut3d_file, S.x265_params);
    fprintf(fp, "outdir=\"%s\"\naudio_bitrate=\"%s\"\nmovflags=\"%s\"\nthreads=\"%s\"\n", S.outdir, S.audio_bitrate, S.movflags, S.threads);
    fprintf(fp, "use10=\"%d\"\nhwaccel=\"%s\"\nencoder=\"%s\"\npreview=\"%d\"\n", S.use10, S.hwaccel, S.encoder, S.preview);
    
    fprintf(fp, "no_deblock=\"%d\"\nno_denoise=\"%d\"\nno_decimate=\"%d\"\nno_interpolate=\"%d\"\n", S.no_deblock, S.no_denoise, S.no_decimate, S.no_interpolate);
    fprintf(fp, "no_sharpen=\"%d\"\nno_deband=\"%d\"\nno_eq=\"%d\"\nno_grain=\"%d\"\n", S.no_sharpen, S.no_deband, S.no_eq, S.no_grain);
    fprintf(fp, "pci_safe_mode=\"%d\"\n", S.pci_safe_mode);
    
    fclose(fp);
    printf("Saved preset: %s\n", name);
}

static void load_preset_file(const char *name, bool quiet) {
    if (strcmp(name, "factory") == 0) { S = DEF; return; }
    char file[PATH_MAX]; snprintf(file, sizeof(file), "%s/%s.preset", GPTPRO_PRESET_DIR, name);
    FILE *fp = fopen(file, "r"); if (!fp) { if(!quiet) printf("Preset not found: %s\n", name); return; }
    char line[2048], key[64], val[1024];
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "%63[^=]=\"%1023[^\"]\"", key, val) == 2) {
            if (!strcmp(key, "codec")) strcpy(S.codec, val); else if (!strcmp(key, "crf")) strcpy(S.crf, val);
            else if (!strcmp(key, "preset")) strcpy(S.preset, val); else if (!strcmp(key, "fps")) strcpy(S.fps, val);
            else if (!strcmp(key, "scale_factor")) strcpy(S.scale_factor, val); else if (!strcmp(key, "scaler")) strcpy(S.scaler, val);
            else if (!strcmp(key, "ai_backend")) strcpy(S.ai_backend, val); else if (!strcmp(key, "ai_model")) strcpy(S.ai_model, val);
            else if (!strcmp(key, "ai_model_type")) strcpy(S.ai_model_type, val); else if (!strcmp(key, "dnn_backend")) strcpy(S.dnn_backend, val);
            else if (!strcmp(key, "denoiser")) strcpy(S.denoiser, val); else if (!strcmp(key, "denoise_strength")) strcpy(S.denoise_strength, val);
            else if (!strcmp(key, "deblock_mode")) strcpy(S.deblock_mode, val); else if (!strcmp(key, "deblock_thresh")) strcpy(S.deblock_thresh, val);
            else if (!strcmp(key, "dering_active")) S.dering_active = atoi(val); else if (!strcmp(key, "dering_strength")) strcpy(S.dering_strength, val);
            else if (!strcmp(key, "sharpen_method")) strcpy(S.sharpen_method, val); else if (!strcmp(key, "sharpen_strength")) strcpy(S.sharpen_strength, val);
            else if (!strcmp(key, "usm_radius")) strcpy(S.usm_radius, val); else if (!strcmp(key, "usm_amount")) strcpy(S.usm_amount, val); else if (!strcmp(key, "usm_threshold")) strcpy(S.usm_threshold, val);
            else if (!strcmp(key, "deband_method")) strcpy(S.deband_method, val); else if (!strcmp(key, "deband_strength")) strcpy(S.deband_strength, val);
            else if (!strcmp(key, "f3kdb_range")) strcpy(S.f3kdb_range, val); else if (!strcmp(key, "f3kdb_y")) strcpy(S.f3kdb_y, val); else if (!strcmp(key, "f3kdb_cbcr")) strcpy(S.f3kdb_cbcr, val);
            else if (!strcmp(key, "grain_strength")) strcpy(S.grain_strength, val);
            else if (!strcmp(key, "denoiser_2")) strcpy(S.denoiser_2, val); else if (!strcmp(key, "denoise_strength_2")) strcpy(S.denoise_strength_2, val);
            else if (!strcmp(key, "deblock_mode_2")) strcpy(S.deblock_mode_2, val); else if (!strcmp(key, "deblock_thresh_2")) strcpy(S.deblock_thresh_2, val);
            else if (!strcmp(key, "dering_active_2")) S.dering_active_2 = atoi(val); else if (!strcmp(key, "dering_strength_2")) strcpy(S.dering_strength_2, val);
            else if (!strcmp(key, "sharpen_method_2")) strcpy(S.sharpen_method_2, val); else if (!strcmp(key, "sharpen_strength_2")) strcpy(S.sharpen_strength_2, val);
            else if (!strcmp(key, "usm_radius_2")) strcpy(S.usm_radius_2, val); else if (!strcmp(key, "usm_amount_2")) strcpy(S.usm_amount_2, val); else if (!strcmp(key, "usm_threshold_2")) strcpy(S.usm_threshold_2, val);
            else if (!strcmp(key, "deband_method_2")) strcpy(S.deband_method_2, val); else if (!strcmp(key, "deband_strength_2")) strcpy(S.deband_strength_2, val);
            else if (!strcmp(key, "f3kdb_range_2")) strcpy(S.f3kdb_range_2, val); else if (!strcmp(key, "f3kdb_y_2")) strcpy(S.f3kdb_y_2, val); else if (!strcmp(key, "f3kdb_cbcr_2")) strcpy(S.f3kdb_cbcr_2, val);
            else if (!strcmp(key, "grain_strength_2")) strcpy(S.grain_strength_2, val);
            else if (!strcmp(key, "use_denoise_2")) S.use_denoise_2 = atoi(val);
            else if (!strcmp(key, "use_deblock_2")) S.use_deblock_2 = atoi(val);
            else if (!strcmp(key, "use_dering_2")) S.use_dering_2 = atoi(val);
            else if (!strcmp(key, "use_sharpen_2")) S.use_sharpen_2 = atoi(val);
            else if (!strcmp(key, "use_deband_2")) S.use_deband_2 = atoi(val);
            else if (!strcmp(key, "use_grain_2")) S.use_grain_2 = atoi(val);
            else if (!strcmp(key, "mi_mode")) strcpy(S.mi_mode, val);
            else if (!strcmp(key, "eq_contrast")) strcpy(S.eq_contrast, val); else if (!strcmp(key, "eq_brightness")) strcpy(S.eq_brightness, val); else if (!strcmp(key, "eq_saturation")) strcpy(S.eq_saturation, val);
            else if (!strcmp(key, "lut3d_file")) strcpy(S.lut3d_file, val); else if (!strcmp(key, "x265_params")) strcpy(S.x265_params, val);
            else if (!strcmp(key, "outdir")) strcpy(S.outdir, val); else if (!strcmp(key, "audio_bitrate")) strcpy(S.audio_bitrate, val);
            else if (!strcmp(key, "movflags")) strcpy(S.movflags, val); else if (!strcmp(key, "threads")) strcpy(S.threads, val); else if (!strcmp(key, "hwaccel")) strcpy(S.hwaccel, val);
            else if (!strcmp(key, "encoder")) strcpy(S.encoder, val); else if (!strcmp(key, "use10")) S.use10 = atoi(val); else if (!strcmp(key, "preview")) S.preview = atoi(val);
            else if (!strcmp(key, "no_deblock")) S.no_deblock = atoi(val); else if (!strcmp(key, "no_denoise")) S.no_denoise = atoi(val);
            else if (!strcmp(key, "no_decimate")) S.no_decimate = atoi(val); else if (!strcmp(key, "no_interpolate")) S.no_interpolate = atoi(val);
            else if (!strcmp(key, "no_sharpen")) S.no_sharpen = atoi(val); else if (!strcmp(key, "no_deband")) S.no_deband = atoi(val);
            else if (!strcmp(key, "no_eq")) S.no_eq = atoi(val); else if (!strcmp(key, "no_grain")) S.no_grain = atoi(val);
            else if (!strcmp(key, "pci_safe_mode")) S.pci_safe_mode = atoi(val);
        }
    } fclose(fp);
}

static void ensure_conf_dirs(void) {
    mkdir_p(GPTPRO_PRESET_DIR);
    char def[PATH_MAX]; snprintf(def, sizeof(def), "%s/default.preset", GPTPRO_PRESET_DIR);
    struct stat st;
    if (stat(def, &st) != 0) { S = DEF; save_preset_file("default"); }
    if (stat(GPTPRO_ACTIVE_FILE, &st) != 0) {
        FILE *fp = fopen(GPTPRO_ACTIVE_FILE, "w"); if(fp) { fprintf(fp, "default\n"); fclose(fp); }
    }
}

static void active_preset_name(char *out, size_t outsz) {
    FILE *fp = fopen(GPTPRO_ACTIVE_FILE, "r");
    if (!fp || !fgets(out, (int)outsz, fp)) safe_copy(out, "default", outsz);
    else { size_t n = strlen(out); while(n > 0 && isspace(out[n-1])) out[--n] = 0; }
    if (fp) fclose(fp);
}

static void set_active_preset(const char *name) {
    FILE *fp = fopen(GPTPRO_ACTIVE_FILE, "w"); if (fp) { fprintf(fp, "%s\n", name); fclose(fp); }
}

static void list_presets(char ***names, int *count) {
    *names=NULL; *count=0; int cap=8;
    char **arr = malloc(sizeof(char*)*cap);
    arr[*count] = strdup("factory"); (*count)++;
    DIR *d = opendir(GPTPRO_PRESET_DIR);
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0]=='.') continue;
            size_t L = strlen(e->d_name);
            if (L>7 && !strcmp(e->d_name+L-7,".preset")) {
                char base[PATH_MAX]; snprintf(base, sizeof(base), "%s", e->d_name);
                base[L-7]='\0';
                if (strcmp(base,"factory")) {
                    if (*count==cap) { cap*=2; arr=realloc(arr,sizeof(char*)*cap); }
                    arr[*count]=strdup(base); (*count)++;
                }
            }
        } closedir(d);
    } *names=arr;
}


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

static int ar_menu_choose(const char *prompt, const char **items, int n, int start_index) {
    int rfd = open("/dev/tty", O_RDONLY);
    int wfd = STDERR_FILENO;
    if (rfd < 0 || !isatty(wfd)) {
        dprintf(wfd, "%s\n", prompt);
        for(int i=0; i<n; i++) dprintf(wfd, "%d. %s\n", i+1, items[i]);
        return 0;
    }
    TermCtx ctx = term_enter_raw(rfd);
    int selected = (start_index >= 0 && start_index < n) ? start_index : 0;
    int width = 64; bool done = false, cancelled = false; char k[8];
    dprintf(wfd, "\033[?25l");

    while (!done) {
        dprintf(wfd, "\033[2J\033[H");
        dprintf(wfd, " ┌"); for (int i=0; i<width-2; i++) dprintf(wfd,"─"); dprintf(wfd, "┐\n");
        dprintf(wfd, " │ " C_BOLD "%-*s" C_RESET " │\n", width-4, prompt);
        dprintf(wfd, " ├"); for (int i=0; i<width-2; i++) dprintf(wfd,"─"); dprintf(wfd, "┤\n");

        for (int i = 0; i < n; i++) {
            char key[4];
            if (i < 9) snprintf(key, 4, "%d", i+1); else if (i == 9) strcpy(key, "0"); else snprintf(key, 4, "%c", 'A' + (i-10));
            if (i == selected) dprintf(wfd, " │ " C_CYAN "> %s. %-*s" C_RESET " │\n", key, width-8, items[i]);
            else dprintf(wfd, " │   %s. %-*s │\n", key, width-8, items[i]);
        }
        dprintf(wfd, " └"); for (int i=0; i<width-2; i++) dprintf(wfd,"─"); dprintf(wfd, "┘\n");

        memset(k, 0, sizeof(k));
        if (read(rfd, k, 1) <= 0) break;
        if (k[0] == 0x1b) {
            if (read(rfd, k+1, 1) > 0 && k[1] == '[') {
                read(rfd, k+2, 1);
                if (k[2] == 'A') { selected = (selected - 1 + n) % n; play_ui_sound("Tink"); }
                if (k[2] == 'B') { selected = (selected + 1) % n; play_ui_sound("Tink"); }
            } else { cancelled = true; break; }
        } else if (k[0] == '\n' || k[0] == '\r') { play_ui_sound("Hero"); done = true; }
        else {
            int idx = -1;
            if (k[0] >= '1' && k[0] <= '9') idx = k[0] - '1'; else if (k[0] == '0') idx = 9;
            else if (k[0] >= 'a' && k[0] <= 'z') idx = k[0] - 'a' + 10; else if (k[0] >= 'A' && k[0] <= 'Z') idx = k[0] - 'A' + 10;
            if (idx >= 0 && idx < n) { selected = idx; play_ui_sound("Hero"); done = true; }
        }
    }
    dprintf(wfd, "\033[?25h"); term_leave_raw(&ctx); close(rfd);
    return cancelled ? -1 : selected;
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

static void submenu_toggle_group(const char *title, const char **keys, char **vals, int n) {
    int cursor = 0;
    for (;;) {
        char **items = malloc((n+1)*sizeof(char*));
        for(int i=0; i<n; i++) {
            items[i] = malloc(256); bool on = !strcmp(vals[i], "1");
            snprintf(items[i], 256, "%s %s", on ? C_GREEN "[ON] " C_RESET : "[OFF]", keys[i]);
        }
        items[n] = strdup("← Back");
        int sel = ar_menu_choose(title, (const char**)items, n+1, cursor);
        for(int i=0; i<=n; i++) free(items[i]); free(items);
        if (sel < 0 || sel == n) break;
        cursor = sel; if (!strcmp(vals[sel], "1")) strcpy(vals[sel], "0"); else strcpy(vals[sel], "1");
    }
}

static void settings_main_menu(void) {
    ensure_conf_dirs(); char current[128]; active_preset_name(current, sizeof(current));
    load_preset_file(current, true); int cursor = 0;
    for(;;) {
        const char *opts[] = { "Codec & Rate", "Frame / Scale", "AI Upscaling", "Filters (Denoise/Deblock)", "Color / EQ / LUT", "Toggles", "Hardware", "I/O", "Load Preset", "Save Preset", "Reset Factory", "Exit & Save" };
        char head[256]; snprintf(head, sizeof(head), "Settings — Active: %s", current);
        int sel = ar_menu_choose(head, opts, ARR_LEN(opts), cursor);
        if (sel < 0) return; cursor = sel;
        
        if(sel==0){
            int sub_c = 0;
            for(;;) {
                char *items[5];
                items[0] = malloc(256); snprintf(items[0],256,"Codec: " C_CYAN "%s" C_RESET, S.codec);
                items[1] = malloc(256); snprintf(items[1],256,"CRF: %s", S.crf);
                items[2] = malloc(256); snprintf(items[2],256,"Preset: " C_CYAN "%s" C_RESET, S.preset);
                items[3] = malloc(256); snprintf(items[3],256,"x265 Params: %s", S.x265_params);
                items[4] = strdup("← Back");
                int sidx = ar_menu_choose("Codec & Rate", (const char**)items, 5, sub_c);
                for(int i=0;i<5;i++) free(items[i]);
                if(sidx<0 || sidx==4) break; sub_c=sidx;
                if(sidx==0) { const char *opt[]={"h264","hevc"}; cycle_string(S.codec, opt, 2); }
                else if(sidx==1) prompt_edit("CRF (0-51)", S.crf, sizeof(S.crf));
                else if(sidx==2) { const char *opt[]={"veryfast","faster","medium","slow","slower","veryslow"}; cycle_string(S.preset, opt, 6); }
                else if(sidx==3) prompt_edit("x265 Params", S.x265_params, sizeof(S.x265_params));
            }
        }
        else if(sel==1){
            int sub_c = 0;
            for(;;) {
                char *items[5];
                items[0] = malloc(256); snprintf(items[0],256,"FPS: %s (source=Lock)", S.fps);
                items[1] = malloc(256); snprintf(items[1],256,"Scale Factor: %s", S.scale_factor);
                items[2] = malloc(256); snprintf(items[2],256,"Scaler: " C_CYAN "%s" C_RESET, S.scaler);
                items[3] = malloc(256); snprintf(items[3],256,"Interpolation: " C_CYAN "%s" C_RESET, S.mi_mode);
                items[4] = strdup("← Back");
                int sidx = ar_menu_choose("Frame & Scale", (const char**)items, 5, sub_c);
                for(int i=0;i<5;i++) free(items[i]);
                if(sidx<0 || sidx==4) break; sub_c=sidx;
                if(sidx==0) prompt_edit("FPS (1-240 or 'source')", S.fps, sizeof(S.fps));
                else if(sidx==1) prompt_edit("Scale Factor (0.1-10)", S.scale_factor, sizeof(S.scale_factor));
                else if(sidx==2) { const char *opt[]={"ai","lanczos","zscale","hw"}; cycle_string(S.scaler, opt, 4); }
                else if(sidx==3) { const char *opt[]={"mci","blend"}; cycle_string(S.mi_mode, opt, 2); }
            }
        }
        else if(sel==2){
            int sub_c = 0;
            for(;;) {
                char *items[5];
                items[0] = malloc(256); snprintf(items[0],256,"Backend: " C_CYAN "%s" C_RESET, S.ai_backend);
                items[1] = malloc(256); snprintf(items[1],256,"Model Path: %s", S.ai_model);
                items[2] = malloc(256); snprintf(items[2],256,"Model Type: " C_CYAN "%s" C_RESET, S.ai_model_type);
                items[3] = malloc(256); snprintf(items[3],256,"DNN Backend: " C_CYAN "%s" C_RESET, S.dnn_backend);
                items[4] = strdup("← Back");
                int sidx = ar_menu_choose("AI Upscaling", (const char**)items, 5, sub_c);
                for(int i=0;i<5;i++) free(items[i]);
                if(sidx<0 || sidx==4) break; sub_c=sidx;
                if(sidx==0) { const char *opt[]={"sr","dnn"}; cycle_string(S.ai_backend, opt, 2); }
                else if(sidx==1) prompt_edit("Model Path (Absolute)", S.ai_model, sizeof(S.ai_model));
                else if(sidx==2) { const char *opt[]={"srcnn","espcn","edsr","fsrcnn"}; cycle_string(S.ai_model_type, opt, 4); }
                else if(sidx==3) { const char *opt[]={"tensorflow","openvino","native"}; cycle_string(S.dnn_backend, opt, 3); }
            }
        }
        else if(sel==3){
            int sub_c = 0;
            for(;;) {
                char *items[40]; int k=0;
                
                items[k++] = malloc(256); snprintf(items[k-1],256,"Denoiser: " C_CYAN "%s" C_RESET, S.denoiser);
                items[k++] = malloc(256); snprintf(items[k-1],256,"Denoise Strength: %s", S.denoise_strength);
                items[k++] = malloc(256); snprintf(items[k-1],256,"Deblock Mode: " C_CYAN "%s" C_RESET, S.deblock_mode);
                items[k++] = malloc(256); snprintf(items[k-1],256,"Dering Active: " C_CYAN "%s" C_RESET, S.dering_active ? "YES" : "NO");
                items[k++] = malloc(256); snprintf(items[k-1],256,"Dering Strength: %s", S.dering_strength);
                items[k++] = malloc(256); snprintf(items[k-1],256,"Sharpen Method: " C_CYAN "%s" C_RESET, S.sharpen_method);
                
                if(!strcmp(S.sharpen_method, "unsharp")) {
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Radius: %s", S.usm_radius);
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Amount: %s", S.usm_amount);
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Threshold: %s", S.usm_threshold);
                } else {
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  CAS Strength: %s", S.sharpen_strength);
                }

                items[k++] = malloc(256); snprintf(items[k-1],256,"Deband Method: " C_CYAN "%s" C_RESET, S.deband_method);
                if(!strcmp(S.deband_method, "f3kdb")) {
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Range: %s", S.f3kdb_range);
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Y: %s", S.f3kdb_y);
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  CbCr: %s", S.f3kdb_cbcr);
                } else {
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Strength: %s", S.deband_strength);
                }
                items[k++] = malloc(256); snprintf(items[k-1],256,"Grain Strength: %s", S.grain_strength);
                
                
                int first_set_count = k;
                
                
                items[k++] = malloc(256); snprintf(items[k-1],256,"[%s] Use Denoiser (2)", S.use_denoise_2 ? "ON" : "OFF");
                items[k++] = malloc(256); snprintf(items[k-1],256,"Denoiser (2): " C_CYAN "%s" C_RESET, S.denoiser_2);
                items[k++] = malloc(256); snprintf(items[k-1],256,"Denoise Strength (2): %s", S.denoise_strength_2);
                items[k++] = malloc(256); snprintf(items[k-1],256,"[%s] Use Deblock (2)", S.use_deblock_2 ? "ON" : "OFF");
                items[k++] = malloc(256); snprintf(items[k-1],256,"Deblock Mode (2): " C_CYAN "%s" C_RESET, S.deblock_mode_2);
                items[k++] = malloc(256); snprintf(items[k-1],256,"[%s] Use Dering (2)", S.use_dering_2 ? "ON" : "OFF");
                items[k++] = malloc(256); snprintf(items[k-1],256,"Dering Active (2): " C_CYAN "%s" C_RESET, S.dering_active_2 ? "YES" : "NO");
                items[k++] = malloc(256); snprintf(items[k-1],256,"Dering Strength (2): %s", S.dering_strength_2);
                items[k++] = malloc(256); snprintf(items[k-1],256,"[%s] Use Sharpen (2)", S.use_sharpen_2 ? "ON" : "OFF");
                items[k++] = malloc(256); snprintf(items[k-1],256,"Sharpen Method (2): " C_CYAN "%s" C_RESET, S.sharpen_method_2);
                
                if(!strcmp(S.sharpen_method_2, "unsharp")) {
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Radius (2): %s", S.usm_radius_2);
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Amount (2): %s", S.usm_amount_2);
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Threshold (2): %s", S.usm_threshold_2);
                } else {
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  CAS Strength (2): %s", S.sharpen_strength_2);
                }

                items[k++] = malloc(256); snprintf(items[k-1],256,"[%s] Use Deband (2)", S.use_deband_2 ? "ON" : "OFF");
                items[k++] = malloc(256); snprintf(items[k-1],256,"Deband Method (2): " C_CYAN "%s" C_RESET, S.deband_method_2);
                if(!strcmp(S.deband_method_2, "f3kdb")) {
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Range (2): %s", S.f3kdb_range_2);
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Y (2): %s", S.f3kdb_y_2);
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  CbCr (2): %s", S.f3kdb_cbcr_2);
                } else {
                    items[k++] = malloc(256); snprintf(items[k-1],256,"  Strength (2): %s", S.deband_strength_2);
                }
                items[k++] = malloc(256); snprintf(items[k-1],256,"[%s] Use Grain (2)", S.use_grain_2 ? "ON" : "OFF");
                items[k++] = malloc(256); snprintf(items[k-1],256,"Grain Strength (2): %s", S.grain_strength_2);
                
                items[k++] = strdup("← Back");
                
                int sidx = ar_menu_choose("Filters (Adv)", (const char**)items, k, sub_c);
                for(int i=0;i<k;i++) free(items[i]);
                if(sidx<0 || sidx==k-1) break; sub_c=sidx;
                
                
                int actual_idx = sidx;
                bool is_second_set = (sidx >= first_set_count && sidx < k-1);
                if(is_second_set) {
                    actual_idx = sidx - first_set_count;
                }
                
                
                if(!is_second_set) {
                    if(actual_idx==0) { const char *opt[]={"bm3d","nlmeans","hqdn3d","atadenoise"}; cycle_string(S.denoiser, opt, 4); }
                    else if(actual_idx==1) prompt_edit("Denoise Strength (0-20 or 'auto')", S.denoise_strength, sizeof(S.denoise_strength));
                    else if(actual_idx==2) { const char *opt[]={"weak","strong"}; cycle_string(S.deblock_mode, opt, 2); }
                    else if(actual_idx==3) S.dering_active = !S.dering_active;
                    else if(actual_idx==4) prompt_edit("Dering Strength (0-10)", S.dering_strength, sizeof(S.dering_strength));
                    else if(actual_idx==5) { const char *opt[]={"cas","unsharp"}; cycle_string(S.sharpen_method, opt, 2); }
                    else {
                        const char *sharpen_method = S.sharpen_method;
                        bool unsharp = !strcmp(sharpen_method, "unsharp");
                        int offset = 6;
                        if(unsharp) {
                            if(actual_idx==offset) prompt_edit("USM Radius (3-23)", S.usm_radius, 16);
                            else if(actual_idx==offset+1) prompt_edit("USM Amount (-2.0-5.0)", S.usm_amount, 16);
                            else if(actual_idx==offset+2) prompt_edit("USM Threshold (0-255)", S.usm_threshold, 16);
                            offset += 3;
                        } else {
                            if(actual_idx==offset) prompt_edit("CAS Strength (0.0-1.0)", S.sharpen_strength, 32);
                            offset += 1;
                        }
                        
                        if(actual_idx==offset) {
                            const char *opt[]={"deband","gradfun","f3kdb"};
                            cycle_string(S.deband_method, opt, 3);
                        }
                        else {
                            const char *deband_method = S.deband_method;
                            bool f3 = !strcmp(deband_method, "f3kdb");
                            int doff = offset + 1;
                            if(f3) {
                                if(actual_idx==doff) prompt_edit("F3KDB Range (1-50)", S.f3kdb_range, 16);
                                else if(actual_idx==doff+1) prompt_edit("F3KDB Y (0-255)", S.f3kdb_y, 16);
                                else if(actual_idx==doff+2) prompt_edit("F3KDB CbCr (0-255)", S.f3kdb_cbcr, 16);
                                doff+=3;
                            } else {
                                if(actual_idx==doff) prompt_edit("Deband Strength (0.0-0.5)", S.deband_strength, 32);
                                doff+=1;
                            }
                            if(actual_idx==doff) prompt_edit("Grain Strength (0-100)", S.grain_strength, 16);
                        }
                    }
                }
                
                else {
                    
                    if(actual_idx==0) S.use_denoise_2 = !S.use_denoise_2;
                    
                    else if(actual_idx==1) { const char *opt[]={"bm3d","nlmeans","hqdn3d","atadenoise"}; cycle_string(S.denoiser_2, opt, 4); }
                    
                    else if(actual_idx==2) prompt_edit("Denoise Strength (2) (0-20 or 'auto')", S.denoise_strength_2, sizeof(S.denoise_strength_2));
                    
                    else if(actual_idx==3) S.use_deblock_2 = !S.use_deblock_2;
                    
                    else if(actual_idx==4) { const char *opt[]={"weak","strong"}; cycle_string(S.deblock_mode_2, opt, 2); }
                    
                    else if(actual_idx==5) S.use_dering_2 = !S.use_dering_2;
                    
                    else if(actual_idx==6) S.dering_active_2 = !S.dering_active_2;
                    
                    else if(actual_idx==7) prompt_edit("Dering Strength (2) (0-10)", S.dering_strength_2, sizeof(S.dering_strength_2));
                    
                    else if(actual_idx==8) S.use_sharpen_2 = !S.use_sharpen_2;
                    
                    else if(actual_idx==9) { const char *opt[]={"cas","unsharp"}; cycle_string(S.sharpen_method_2, opt, 2); }
                    
                    else {
                        const char *sharpen_method = S.sharpen_method_2;
                        bool unsharp = !strcmp(sharpen_method, "unsharp");
                        int offset = 10;
                        if(unsharp) {
                            if(actual_idx==offset) prompt_edit("USM Radius (2) (3-23)", S.usm_radius_2, 16);
                            else if(actual_idx==offset+1) prompt_edit("USM Amount (2) (-2.0-5.0)", S.usm_amount_2, 16);
                            else if(actual_idx==offset+2) prompt_edit("USM Threshold (2) (0-255)", S.usm_threshold_2, 16);
                            offset += 3;
                        } else {
                            if(actual_idx==offset) prompt_edit("CAS Strength (2) (0.0-1.0)", S.sharpen_strength_2, 32);
                            offset += 1;
                        }
                        
                        
                        if(actual_idx==offset) S.use_deband_2 = !S.use_deband_2;
                        
                        else if(actual_idx==offset+1) {
                            const char *opt[]={"deband","gradfun","f3kdb"};
                            cycle_string(S.deband_method_2, opt, 3);
                        }
                        
                        else {
                            const char *deband_method = S.deband_method_2;
                            bool f3 = !strcmp(deband_method, "f3kdb");
                            int doff = offset + 2;
                            if(f3) {
                                if(actual_idx==doff) prompt_edit("F3KDB Range (2) (1-50)", S.f3kdb_range_2, 16);
                                else if(actual_idx==doff+1) prompt_edit("F3KDB Y (2) (0-255)", S.f3kdb_y_2, 16);
                                else if(actual_idx==doff+2) prompt_edit("F3KDB CbCr (2) (0-255)", S.f3kdb_cbcr_2, 16);
                                doff+=3;
                            } else {
                                if(actual_idx==doff) prompt_edit("Deband Strength (2) (0.0-0.5)", S.deband_strength_2, 32);
                                doff+=1;
                            }
                            
                            if(actual_idx==doff) S.use_grain_2 = !S.use_grain_2;
                            
                            else if(actual_idx==doff+1) prompt_edit("Grain Strength (2) (0-100)", S.grain_strength_2, 16);
                        }
                    }
                }
            }
        }
        else if(sel==4){
            const char *k[]={"contrast (1.0=norm)","brightness","saturation (1.0=norm)","lut3d_file"};
            char *v[]={S.eq_contrast,S.eq_brightness,S.eq_saturation,S.lut3d_file};
            size_t s[]={16,16,16,PATH_MAX}; submenu_edit_group("Color", k, v, s, 4);
        }
        else if(sel==5){
            const char *k[]={"no_deblock","no_denoise","no_decimate","no_interpolate","no_sharpen","no_deband","no_eq","no_grain","pci_safe_mode"};
            char b[9][16]; char *v[9]; for(int i=0;i<9;i++) v[i]=b[i];
            snprintf(b[0],16,"%d",S.no_deblock); snprintf(b[1],16,"%d",S.no_denoise); snprintf(b[2],16,"%d",S.no_decimate); snprintf(b[3],16,"%d",S.no_interpolate);
            snprintf(b[4],16,"%d",S.no_sharpen); snprintf(b[5],16,"%d",S.no_deband); snprintf(b[6],16,"%d",S.no_eq); snprintf(b[7],16,"%d",S.no_grain);
            snprintf(b[8],16,"%d",S.pci_safe_mode);
            submenu_toggle_group("Toggles", k, v, 9);
            S.no_deblock=atoi(b[0]); S.no_denoise=atoi(b[1]); S.no_decimate=atoi(b[2]); S.no_interpolate=atoi(b[3]);
            S.no_sharpen=atoi(b[4]); S.no_deband=atoi(b[5]); S.no_eq=atoi(b[6]); S.no_grain=atoi(b[7]);
            S.pci_safe_mode=atoi(b[8]);
        }
        else if(sel==6){
            int sub_c=0;
            for(;;) {
                char *items[5];
                items[0] = malloc(256); snprintf(items[0],256,"HW Accel: " C_CYAN "%s" C_RESET, S.hwaccel);
                items[1] = malloc(256); snprintf(items[1],256,"Encoder: " C_CYAN "%s" C_RESET, S.encoder);
                items[2] = malloc(256); snprintf(items[2],256,"10-Bit Output: " C_CYAN "%s" C_RESET, S.use10 ? "Yes" : "No");
                items[3] = malloc(256); snprintf(items[3],256,"Threads: %s", S.threads);
                items[4] = strdup("← Back");
                int sidx = ar_menu_choose("Hardware", (const char**)items, 5, sub_c);
                for(int i=0;i<5;i++) free(items[i]);
                if(sidx<0 || sidx==4) break; sub_c=sidx;
                if(sidx==0) { const char *opt[]={"none","cuda","qsv","vaapi"}; cycle_string(S.hwaccel, opt, 4); }
                else if(sidx==1) { const char *opt[]={"auto","cpu","nvenc","qsv","vaapi"}; cycle_string(S.encoder, opt, 5); }
                else if(sidx==2) S.use10 = !S.use10;
                else if(sidx==3) prompt_edit("Threads (0=Auto)", S.threads, sizeof(S.threads));
            }
        }
        else if(sel==7){
            int sub_c=0;
            for(;;) {
                char *items[5];
                items[0] = malloc(256); snprintf(items[0],256,"Output Dir: %s", S.outdir);
                items[1] = malloc(256); snprintf(items[1],256,"Audio Bitrate: %s", S.audio_bitrate);
                items[2] = malloc(256); snprintf(items[2],256,"Movflags: " C_CYAN "%s" C_RESET, S.movflags);
                items[3] = malloc(256); snprintf(items[3],256,"Live Preview: " C_CYAN "%s" C_RESET, S.preview ? "ON" : "OFF");
                items[4] = strdup("← Back");
                int sidx = ar_menu_choose("I/O", (const char**)items, 5, sub_c);
                for(int i=0;i<5;i++) free(items[i]);
                if(sidx<0 || sidx==4) break; sub_c=sidx;
                if(sidx==0) prompt_edit("Output Dir", S.outdir, sizeof(S.outdir));
                else if(sidx==1) prompt_edit("Audio Bitrate (e.g. 192k)", S.audio_bitrate, sizeof(S.audio_bitrate));
                else if(sidx==2) { if(!strcmp(S.movflags, "+faststart")) strcpy(S.movflags, ""); else strcpy(S.movflags, "+faststart"); }
                else if(sidx==3) S.preview = !S.preview;
            }
        }
        else if(sel==8){
            char **names; int count; list_presets(&names, &count);
            int pidx = ar_menu_choose("Load", (const char**)names, count, 0);
            if (pidx >= 0) { load_preset_file(names[pidx], false); snprintf(current, sizeof(current), "%s", names[pidx]); set_active_preset(current); }
            for(int i=0;i<count;i++) free(names[i]); free(names);
        } else if(sel==9){
            char name[256]=""; prompt_edit("name", name, sizeof(name));
            if (*name && strcmp(name,"factory")) { save_preset_file(name); snprintf(current, sizeof(current), "%s", name); set_active_preset(current); }
        } else if(sel==10) reset_to_factory();
        else if(sel==11) { save_preset_file(current); return; }
    }
}


static int parse_command_line(char *command_line, char ***argv_out) {
    int argc = 0; int max_args = 64;
    char **argv = malloc(sizeof(char*) * max_args);
    char *p = command_line;
    bool in_q = false, in_dq = false;
    while (*p) {
        while (*p && isspace((unsigned char)*p) && !in_q && !in_dq) p++;
        if (!*p) break;
        char *start = p;
        while (*p) {
            if (*p == '\\' && p[1]) { memmove(p, p+1, strlen(p)); p++; }
            else if (*p == '\'') { in_q = !in_q; memmove(p, p+1, strlen(p)); }
            else if (*p == '"') { in_dq = !in_dq; memmove(p, p+1, strlen(p)); }
            else if (isspace((unsigned char)*p) && !in_q && !in_dq) break;
            else p++;
        }
        if (*p) *p++ = 0;
        argv[argc++] = strdup(start);
    }
    argv[argc] = NULL; *argv_out = argv; return argc;
}

static int process_cli_args(int argc, char **argv, const char *ffmpeg_path) {
    char input_path[PATH_MAX]="";
    int opt, long_idx;
    
    struct option long_opts[] = {
        {"codec",1,0,1}, {"crf",1,0,'c'}, {"preset",1,0,'p'}, {"fps",1,0,'f'}, {"scale",1,0,'s'},
        {"scaler",1,0,2}, {"denoiser",1,0,3}, {"lut",1,0,4}, {"x265",1,0,5}, {"help",0,0,'h'},
        {"manual",0,0,'m'}, {"outdir",1,0,'o'}, {"no-deblock",0,0,10}, {"no-denoise",0,0,11}, {"dry-run",0,0,12},
        {"dering",0,0,13}, {"usm-radius",1,0,14}, {"usm-amount",1,0,15}, {"usm-threshold",1,0,16},
        {"f3kdb-range",1,0,17}, {"pci-safe",0,0,18}, {"preview",0,0,19},
        
        {"hevc",0,0,20}, {"10bit",0,0,21}, {"mi-mode",1,0,22}, {"ai-backend",1,0,23},
        {"ai-model",1,0,24}, {"dnn-backend",1,0,25}, {"denoise-strength",1,0,26},
        {"sharpen-method",1,0,27}, {"deband-method",1,0,28},
        {0,0,0,0}
    };
    optind = 1;
    while ((opt = getopt_long(argc, argv, "i:o:c:p:f:s:hm", long_opts, &long_idx)) != -1) {
        switch(opt) {
            case 'i': safe_copy(input_path, optarg, PATH_MAX); break;
            case 'o': safe_copy(S.outdir, optarg, PATH_MAX); break;
            case 'c': safe_copy(S.crf, optarg, 16); break;
            case 'p': safe_copy(S.preset, optarg, 32); break;
            case 'f': safe_copy(S.fps, optarg, 16); break;
            case 's': safe_copy(S.scale_factor, optarg, 16); break;
            case 1: safe_copy(S.codec, optarg, 8); break;
            case 2: safe_copy(S.scaler, optarg, 16); break;
            case 3: safe_copy(S.denoiser, optarg, 16); break;
            case 4: safe_copy(S.lut3d_file, optarg, PATH_MAX); break;
            case 5: safe_copy(S.x265_params, optarg, 256); break;
            case 10: S.no_deblock = 1; break;
            case 11: S.no_denoise = 1; break;
            case 12: DRY_RUN = 1; break;
            case 13: S.dering_active = 1; break;
            case 14: safe_copy(S.usm_radius, optarg, 16); strcpy(S.sharpen_method, "unsharp"); break;
            case 15: safe_copy(S.usm_amount, optarg, 16); break;
            case 16: safe_copy(S.usm_threshold, optarg, 16); break;
            case 17: safe_copy(S.f3kdb_range, optarg, 16); strcpy(S.deband_method, "f3kdb"); break;
            case 18: S.pci_safe_mode = 1; break;
            case 19: S.preview = 1; break;
            
            case 20: strcpy(S.codec, "hevc"); break;
            case 21: S.use10 = 1; break;
            case 22: safe_copy(S.mi_mode, optarg, 16); break;
            case 23: safe_copy(S.ai_backend, optarg, 16); break;
            case 24: safe_copy(S.ai_model, optarg, PATH_MAX); break;
            case 25: safe_copy(S.dnn_backend, optarg, 32); break;
            case 26: safe_copy(S.denoise_strength, optarg, 16); break;
            case 27: safe_copy(S.sharpen_method, optarg, 16); break;
            case 28: safe_copy(S.deband_method, optarg, 16); break;
            
            case 'h': printf("%s", HELP_TEXT); return 0;
            case 'm': printf("%s", MANUAL_TEXT); return 0;
        }
    }
    if (optind < argc && !*input_path) safe_copy(input_path, argv[optind], PATH_MAX);
    if (*input_path) process_file(input_path, ffmpeg_path, false);
    return 0;
}


typedef struct { char *buf; size_t len, cap; } SB;
static void sb_append(SB *s, const char *str) {
    if (!s->buf) { s->cap=1024; s->buf=malloc(s->cap); s->len=0; }
    size_t l = strlen(str);
    if (s->len + l + 1 >= s->cap) { s->cap = (s->cap + l)*2; s->buf=realloc(s->buf, s->cap); }
    strcpy(s->buf + s->len, str); s->len += l;
}
static void sb_fmt(SB *s, const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    char tmp[2048]; vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap); sb_append(s, tmp);
}



static double parse_strength(const char *strength) {
    if (!strength || !strcmp(strength, "auto")) return 0.0;
    char *end;
    double val = strtod(strength, &end);
    if (*end != '\0' || val < 0) return 0.0;
    return val;
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

static bool is_image(const char *path) {
    const char *ext = strrchr(path, '.');
    if (!ext) return false;
    if (!strcasecmp(ext, ".png") || !strcasecmp(ext, ".jpg") || 
        !strcasecmp(ext, ".jpeg") || !strcasecmp(ext, ".tif") || 
        !strcasecmp(ext, ".tiff") || !strcasecmp(ext, ".bmp") || 
        !strcasecmp(ext, ".webp")) return true;
    return false;
}

#ifndef UP60P_LIBRARY_MODE
static int execute_ffmpeg_command(char **args) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        execvp(args[0], args);
        perror("execvp");
        _exit(1);
    }
    int status;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
#endif

static void process_file(const char *in, const char *ffmpeg, bool batch) {
    (void)batch; char outdir[PATH_MAX], base[PATH_MAX], out[PATH_MAX];
    bool img = is_image(in);

    if (up60p_is_cancelled()) return;

    {
        char t[PATH_MAX]; strcpy(t, in); char *b = basename(t); strcpy(base, b);
        char *dot = strrchr(base, '.'); if(dot) *dot=0;
        if (*S.outdir) strcpy(outdir, S.outdir); else { strcpy(t, in); strcpy(outdir, dirname(t)); }
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
        if (*S.deblock_thresh) sb_fmt(&vf, "deblock=filter=%s:block=8:%s,", S.deblock_mode, S.deblock_thresh);
        else sb_fmt(&vf, "deblock=filter=%s:block=8,", S.deblock_mode);
    }
    
    if (S.dering_active) {
        
        
        
        
        double dstr = parse_strength(S.dering_strength);
        if (dstr <= 0) dstr = 0.5;
        
        double luma = dstr * 8.0; 
        double chroma = luma * 0.75;
        double luma_tmp = luma * 1.5;
        double chroma_tmp = luma_tmp * 0.75;
        
        
        if (luma > 15.0) luma = 15.0;
        
        sb_fmt(&vf, "hqdn3d=%.2f:%.2f:%.2f:%.2f,", luma, chroma, luma_tmp, chroma_tmp);
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

    if (!S.no_eq) {
        sb_fmt(&vf, "eq=contrast=%s:brightness=%s:saturation=%s,", S.eq_contrast, S.eq_brightness, S.eq_saturation);
        if (*S.lut3d_file) sb_fmt(&vf, "lut3d=file='%s',", S.lut3d_file);
    }
    
    
    if (S.use_deblock_2 && !S.no_deblock) {
        if (*S.deblock_thresh_2) sb_fmt(&vf, "deblock=filter=%s:block=8:%s,", S.deblock_mode_2, S.deblock_thresh_2);
        else sb_fmt(&vf, "deblock=filter=%s:block=8,", S.deblock_mode_2);
    }
    
    if (S.use_dering_2 && S.dering_active_2) {
        double dstr = parse_strength(S.dering_strength_2);
        if (dstr <= 0) dstr = 0.5;
        
        double luma = dstr * 8.0; 
        double chroma = luma * 0.75;
        double luma_tmp = luma * 1.5;
        double chroma_tmp = luma_tmp * 0.75;
        if (luma > 15.0) luma = 15.0;
        
        sb_fmt(&vf, "hqdn3d=%.2f:%.2f:%.2f:%.2f,", luma, chroma, luma_tmp, chroma_tmp);
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

#ifdef UP60P_LIBRARY_MODE
    log_message("Processing: %s\n", in);
    
    if (DRY_RUN) {
        if (global_log_cb) {
            char cmd_buf[8192];
            int pos = 0;
            pos += snprintf(cmd_buf + pos, sizeof(cmd_buf) - pos, "CMD: ");
            for(int i=0; args[i]; i++) {
                pos += snprintf(cmd_buf + pos, sizeof(cmd_buf) - pos, "%s ", args[i]);
            }
            pos += snprintf(cmd_buf + pos, sizeof(cmd_buf) - pos, "\n");
            global_log_cb(cmd_buf);
        }
    } else {
        
        int stdout_pipe[2], stderr_pipe[2];
        if (pipe(stdout_pipe) == -1 || pipe(stderr_pipe) == -1) {
            if (global_log_cb) global_log_cb("Error: Failed to create pipes\n");
            free(vf.buf);
            return;
        }
        
        pid_t pid = fork();
        if (pid == 0) {
            
            int nullfd = open("/dev/null", O_RDONLY);
            if (nullfd >= 0) {
                dup2(nullfd, STDIN_FILENO);
                close(nullfd);
            } else {
                close(STDIN_FILENO);
            }
            
            close(stdout_pipe[0]);
            close(stderr_pipe[0]);
            dup2(stdout_pipe[1], STDOUT_FILENO);
            dup2(stderr_pipe[1], STDERR_FILENO);
            close(stdout_pipe[1]);
            close(stderr_pipe[1]);
            execvp(args[0], args);
            _exit(1);
        } else {
            
            close(stdout_pipe[1]);
            close(stderr_pipe[1]);
            
            char buffer[4096];
            fd_set readfds;
            int maxfd = (stdout_pipe[0] > stderr_pipe[0]) ? stdout_pipe[0] : stderr_pipe[0];
            ssize_t result;
            
            while (1) {
                FD_ZERO(&readfds);
                FD_SET(stdout_pipe[0], &readfds);
                FD_SET(stderr_pipe[0], &readfds);
                
                struct timeval timeout = {0, 100000}; 
                int select_result = select(maxfd + 1, &readfds, NULL, NULL, &timeout);
                
                if (select_result > 0) {
                    if (FD_ISSET(stdout_pipe[0], &readfds)) {
                        ssize_t n = read(stdout_pipe[0], buffer, sizeof(buffer) - 1);
                        if (n > 0) {
                            buffer[n] = 0;
                            if (global_log_cb) global_log_cb(buffer);
                        } else if (n == 0) {
                            close(stdout_pipe[0]);
                            FD_CLR(stdout_pipe[0], &readfds);
                        }
                    }
                    if (FD_ISSET(stderr_pipe[0], &readfds)) {
                        ssize_t n = read(stderr_pipe[0], buffer, sizeof(buffer) - 1);
                        if (n > 0) {
                            buffer[n] = 0;
                            if (global_log_cb) global_log_cb(buffer);
                        } else if (n == 0) {
                            close(stderr_pipe[0]);
                            FD_CLR(stderr_pipe[0], &readfds);
                        }
                    }
                } else if (select_result == 0) {
                    
                    int status;
                    if (waitpid(pid, &status, WNOHANG) != 0) {
                        
                        break;
                    }
                }
            }
            
            
            while ((result = read(stdout_pipe[0], buffer, sizeof(buffer) - 1)) > 0) {
                buffer[result] = 0;
                if (global_log_cb) global_log_cb(buffer);
            }
            while ((result = read(stderr_pipe[0], buffer, sizeof(buffer) - 1)) > 0) {
                buffer[result] = 0;
                if (global_log_cb) global_log_cb(buffer);
            }
            
            close(stdout_pipe[0]);
            close(stderr_pipe[0]);
            waitpid(pid, NULL, 0);
            
            if (global_log_cb) global_log_cb("Done.\n");
        }
    }
#else
    printf(C_BOLD "Processing: %s\n" C_RESET, in);
    if (DRY_RUN) {
        printf(C_YELLOW "CMD: ");
        for(int i=0; args[i]; i++) printf("%s ", args[i]);
        printf("\n" C_RESET);
    } else {
        if (up60p_is_cancelled()) { free(vf.buf); return; }
        
        int result = execute_ffmpeg_command(args);
        if (result == 0) {
            printf(C_GREEN "Done.\n" C_RESET);
        } else {
            printf(C_RED "Error: FFmpeg returned code %d\n" C_RESET, result);
        }
    }
#endif
    free(vf.buf);
}


static void process_directory(const char *dir, const char *ffmpeg) {
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

__attribute__((unused)) static int interactive_mode(const char *self_path, const char *ffmpeg_path) {
    (void)self_path;
    char line[PATH_MAX];
    printf("\n" C_BOLD "up60p_restore_beast v4.9 COMPLETE" C_RESET "\n"); 
    ensure_conf_dirs(); char ap[128]; active_preset_name(ap, sizeof(ap)); load_preset_file(ap, true);

    for (;;) {
        printf("\n────────────────────────────────────────────────────────────────\n");
        printf("Drag video/folder here, 'settings', or 'q':\n" C_CYAN "> " C_RESET);
        if (!fgets(line, sizeof(line), stdin)) break;
        sanitize_path(line);
        if (!strcmp(line, "q")) break;
        if (!strcmp(line, "settings")) { settings_main_menu(); continue; }
        
        char **p_argv; char *lc = strdup(line); int p_argc = parse_command_line(lc, &p_argv);
        if (p_argc > 1 || (p_argc == 1 && p_argv[0][0] == '-')) {
            char *t_argv[64]; t_argv[0] = (char*)SCRIPT_NAME;
            for(int i=0; i<p_argc; i++) t_argv[i+1] = p_argv[i];
            process_cli_args(p_argc+1, t_argv, ffmpeg_path);
        } else {
            struct stat st;
            if (stat(line, &st) == 0) {
                if (S_ISDIR(st.st_mode)) process_directory(line, ffmpeg_path);
                else process_file(line, ffmpeg_path, false);
            } else printf(C_RED "Invalid path or command.\n" C_RESET);
        }
        for(int i=0; i<p_argc; i++) free(p_argv[i]); free(p_argv); free(lc);
    }
    return 0;
}


void up60p_set_dry_run(int enable) {
    DRY_RUN = enable;
}


void up60p_request_cancel(void) {
    cancel_requested = 1;
}


up60p_error up60p_init(const char *app_support_dir, up60p_log_callback log_cb) {
    (void)app_support_dir; 
    
#ifdef UP60P_LIBRARY_MODE
    global_log_cb = log_cb; 
#endif

    
    init_paths();
    
    
    set_defaults();        
    
    
    ensure_conf_dirs();    

    
    
    char name[64];
    active_preset_name(name, sizeof(name));
    if (name[0] != '\0') {
        load_preset_file(name, true);  
    }

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

    const char *ffmpeg = get_bundled_ffmpeg_path();
    if (!ffmpeg || ffmpeg[0] == '\0') {
        
#ifdef UP60P_LIBRARY_MODE
        if (global_log_cb) {
            global_log_cb("ERROR: FFmpeg executable not found.\n");
            global_log_cb("Please install FFmpeg via Homebrew: brew install ffmpeg\n");
            global_log_cb("Or set UP60P_FFMPEG environment variable to point to FFmpeg executable.\n");
        }
#endif
        return UP60P_ERR_FFMPEG_NOT_FOUND;
    }

    struct stat st;
    if (stat(input_path, &st) != 0) return UP60P_ERR_IO;

    
    settings_from_up60p_options(&S, opts);

    if (S_ISDIR(st.st_mode)) {
        process_directory(input_path, ffmpeg);
    } else {
        process_file(input_path, ffmpeg, false);
    }

    if (up60p_is_cancelled()) {
        return UP60P_ERR_CANCELLED;
    }

    return UP60P_OK;
}

void up60p_shutdown(void) {
    
}

#ifndef UP60P_LIBRARY_MODE
int main(int argc, char **argv) {
    set_defaults();
    init_paths();

    
    ensure_conf_dirs();
    char ap[128];
    active_preset_name(ap, sizeof(ap));
    load_preset_file(ap, true);

    const char *ffmpeg = get_bundled_ffmpeg_path();
    if (!ffmpeg) {
        printf("Error: FFmpeg not found.\n");
        return 1;
    }

    if (argc > 1 && argv[1][0] != '-') {
        struct stat st;
        if (stat(argv[1], &st) == 0) {
            if (S_ISDIR(st.st_mode)) {
                process_directory(argv[1], ffmpeg);
            } else {
                process_file(argv[1], ffmpeg, false);
            }
            return 0;
        }
    }

    return interactive_mode(argv[0], ffmpeg);
}
#endif
