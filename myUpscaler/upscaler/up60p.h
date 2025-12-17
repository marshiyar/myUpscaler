// up60p.h
#pragma once

#include <stddef.h>
#include <stdbool.h>
#include <limits.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    UP60P_OK = 0,
    UP60P_ERR_INVALID_OPTIONS,
    UP60P_ERR_FFMPEG_NOT_FOUND,
    UP60P_ERR_IO,
    UP60P_ERR_INTERNAL,
    UP60P_ERR_CANCELLED
} up60p_error;

/*
 * Public options struct – mirrors your Settings struct closely so
 * Swift can pass everything in one shot.
 */
typedef struct {
    /* Core */
    char codec[8];
    char crf[16];
    char preset[32];
    char fps[16];
    char scale_factor[16];
    
    /* Scaler / AI */
    char scaler[16];
    char ai_backend[16];
    char ai_model[PATH_MAX];
    char ai_model_type[16];
    char dnn_backend[32];
    
    /* Filters – First Set */
    char denoiser[16];
    char denoise_strength[16];
    char deblock_mode[16];
    char deblock_thresh[64];
    int  dering_active;
    char dering_strength[16];
    
    char sharpen_method[16];
    char sharpen_strength[32];
    char usm_radius[16];
    char usm_amount[16];
    char usm_threshold[16];
    
    char deband_method[16];
    char deband_strength[32];
    char f3kdb_range[16];
    char f3kdb_y[16];
    char f3kdb_cbcr[16];
    
    char grain_strength[16];
    
    /* Filters – Second Set */
    char denoiser_2[16];
    char denoise_strength_2[16];
    char deblock_mode_2[16];
    char deblock_thresh_2[64];
    int  dering_active_2;
    char dering_strength_2[16];
    
    char sharpen_method_2[16];
    char sharpen_strength_2[32];
    char usm_radius_2[16];
    char usm_amount_2[16];
    char usm_threshold_2[16];
    
    char deband_method_2[16];
    char deband_strength_2[32];
    char f3kdb_range_2[16];
    char f3kdb_y_2[16];
    char f3kdb_cbcr_2[16];
    
    char grain_strength_2[16];
    
    int use_denoise_2;
    int use_deblock_2;
    int use_dering_2;
    int use_sharpen_2;
    int use_deband_2;
    int use_grain_2;
    
    /* Interpolation / EQ / LUT */
    char mi_mode[16];
    char eq_contrast[16];
    char eq_brightness[16];
    char eq_saturation[16];
    char lut3d_file[PATH_MAX];
    
    /* Encoder extra */
    char x265_params[256];
    
    /* I/O */
    char outdir[PATH_MAX];
    char audio_bitrate[32];
    char threads[16];
    char movflags[32];
    int  use10;
    int  preview;
    
    /* Toggles */
    int no_deblock;
    int no_denoise;
    int no_decimate;
    int no_interpolate;
    int no_sharpen;
    int no_deband;
    int no_eq;
    int no_grain;
    int pci_safe_mode;
    
    /* HW */
    char hwaccel[16];
    char encoder[16];
} up60p_options;

/* Log callback type */
typedef void (*up60p_log_callback)(const char *message);

#ifdef UP60P_LIBRARY_MODE
extern void (*global_log_cb)(const char *message);
#endif

/* Initialize engine (paths, defaults, presets). app_support_dir is optional. */
up60p_error up60p_init(const char *app_support_dir, up60p_log_callback log_cb);

/* Fill out_opts with engine defaults / active preset (strings). */
void        up60p_default_options(up60p_options *out_opts);

/* Process a single file or directory path according to opts. */
up60p_error up60p_process_path(const char *input_path,
                               const up60p_options *opts);

/* Enable or disable dry run mode (1=enabled, 0=disabled) */
void        up60p_set_dry_run(int enable);

/* Request cancellation of any in-flight processing. */
void        up60p_request_cancel(void);

/* Cleanup hook (currently mostly a no-op, but future-proof). */
void        up60p_shutdown(void);

#ifdef __cplusplus
}
#endif
