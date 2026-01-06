#include "up60p_settings.h"
#include "up60p_utils.h"
#include "up60p.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>


#include <limits.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

void up60p_options_from_settings(up60p_options *dst, const Settings *src) {
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


void settings_from_up60p_options(Settings *dst, const up60p_options *src) {
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

void init_paths(void) {
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
}

void set_defaults(void) {
    memset(&S, 0, sizeof(S));
    strcpy(S.codec, "h264"); strcpy(S.crf, "20"); strcpy(S.preset, "faster"); strcpy(S.fps, "60"); strcpy(S.scale_factor, "2");
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
void reset_to_factory(void) { S = DEF; }

