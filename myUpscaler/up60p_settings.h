#ifndef UP60P_SETTINGS_H
#define UP60P_SETTINGS_H

#include "up60p_common.h"

struct Settings {
    
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
};

void init_paths(void);
void set_defaults(void);
void reset_to_factory(void);
void ensure_conf_dirs(void);

// Preset Management
void save_preset_file(const char *name);
void load_preset_file(const char *name, bool quiet);
void active_preset_name(char *out, size_t outsz);
void set_active_preset(const char *name);
void list_presets(char ***names, int *count);

void up60p_options_from_settings(up60p_options *dst, const Settings *src);

void settings_from_up60p_options(Settings *dst, const up60p_options *src);

extern Settings S;
extern Settings DEF;

#endif
