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

static char GPTPRO_PRESET_DIR[PATH_MAX];
static char GPTPRO_ACTIVE_FILE[PATH_MAX];

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
    snprintf(GPTPRO_PRESET_DIR, sizeof(GPTPRO_PRESET_DIR), "%s/gptPro/presets", xdg);
    snprintf(GPTPRO_ACTIVE_FILE, sizeof(GPTPRO_ACTIVE_FILE), "%s/gptPro/active_preset", xdg);
}


void set_defaults(void) {
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


void reset_to_factory(void) { S = DEF; }



void save_preset_file(const char *name) {
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


void load_preset_file(const char *name, bool quiet) {
    if (strcmp(name, "factory") == 0) { S = DEF; return; }
    char file[PATH_MAX];
    snprintf(file, sizeof(file), "%s/%s.preset", GPTPRO_PRESET_DIR, name);
    FILE *fp = fopen(file, "w"); if (!fp) return;
    
    char line[2048], key[64], val[1024];
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "%63[^=]=\"%1023[^\"]\"", key, val) == 2) {
            if (!strcmp(key, "codec")) safe_copy(S.codec, val, sizeof(S.codec));
            else if (!strcmp(key, "crf")) safe_copy(S.crf, val, sizeof(S.crf));
            else if (!strcmp(key, "preset")) safe_copy(S.preset, val, sizeof(S.preset));
            else if (!strcmp(key, "fps")) safe_copy(S.fps, val, sizeof(S.fps));
            else if (!strcmp(key, "scale_factor")) safe_copy(S.scale_factor, val, sizeof(S.scale_factor));
            else if (!strcmp(key, "scaler")) safe_copy(S.scaler, val, sizeof(S.scaler));
            else if (!strcmp(key, "ai_backend")) safe_copy(S.ai_backend, val, sizeof(S.ai_backend));
            else if (!strcmp(key, "ai_model")) safe_copy(S.ai_model, val, sizeof(S.ai_model));
            else if (!strcmp(key, "ai_model_type")) safe_copy(S.ai_model_type, val, sizeof(S.ai_model_type));
            else if (!strcmp(key, "dnn_backend")) safe_copy(S.dnn_backend, val, sizeof(S.dnn_backend));
            
            else if (!strcmp(key, "denoiser")) safe_copy(S.denoiser, val, sizeof(S.denoiser));
            else if (!strcmp(key, "denoise_strength")) safe_copy(S.denoise_strength, val, sizeof(S.denoise_strength));
            else if (!strcmp(key, "deblock_mode")) safe_copy(S.deblock_mode, val, sizeof(S.deblock_mode));
            else if (!strcmp(key, "deblock_thresh")) safe_copy(S.deblock_thresh, val, sizeof(S.deblock_thresh));
            else if (!strcmp(key, "dering_active")) S.dering_active = atoi(val);
            else if (!strcmp(key, "dering_strength")) safe_copy(S.dering_strength, val, sizeof(S.dering_strength));
            
            else if (!strcmp(key, "sharpen_method")) safe_copy(S.sharpen_method, val, sizeof(S.sharpen_method));
            else if (!strcmp(key, "sharpen_strength")) safe_copy(S.sharpen_strength, val, sizeof(S.sharpen_strength));
            else if (!strcmp(key, "usm_radius")) safe_copy(S.usm_radius, val, sizeof(S.usm_radius));
            else if (!strcmp(key, "usm_amount")) safe_copy(S.usm_amount, val, sizeof(S.usm_amount));
            else if (!strcmp(key, "usm_threshold")) safe_copy(S.usm_threshold, val, sizeof(S.usm_threshold));
            
            else if (!strcmp(key, "deband_method")) safe_copy(S.deband_method, val, sizeof(S.deband_method));
            else if (!strcmp(key, "deband_strength")) safe_copy(S.deband_strength, val, sizeof(S.deband_strength));
            else if (!strcmp(key, "f3kdb_range")) safe_copy(S.f3kdb_range, val, sizeof(S.f3kdb_range));
            else if (!strcmp(key, "f3kdb_y")) safe_copy(S.f3kdb_y, val, sizeof(S.f3kdb_y));
            else if (!strcmp(key, "f3kdb_cbcr")) safe_copy(S.f3kdb_cbcr, val, sizeof(S.f3kdb_cbcr));
            
            else if (!strcmp(key, "grain_strength")) safe_copy(S.grain_strength, val, sizeof(S.grain_strength));
            
            else if (!strcmp(key, "denoiser_2")) safe_copy(S.denoiser_2, val, sizeof(S.denoiser_2));
            else if (!strcmp(key, "denoise_strength_2")) safe_copy(S.denoise_strength_2, val, sizeof(S.denoise_strength_2));
            else if (!strcmp(key, "deblock_mode_2")) safe_copy(S.deblock_mode_2, val, sizeof(S.deblock_mode_2));
            else if (!strcmp(key, "deblock_thresh_2")) safe_copy(S.deblock_thresh_2, val, sizeof(S.deblock_thresh_2));
            else if (!strcmp(key, "dering_active_2")) S.dering_active_2 = atoi(val);
            else if (!strcmp(key, "dering_strength_2")) safe_copy(S.dering_strength_2, val, sizeof(S.dering_strength_2));
            
            else if (!strcmp(key, "sharpen_method_2")) safe_copy(S.sharpen_method_2, val, sizeof(S.sharpen_method_2));
            else if (!strcmp(key, "sharpen_strength_2")) safe_copy(S.sharpen_strength_2, val, sizeof(S.sharpen_strength_2));
            else if (!strcmp(key, "usm_radius_2")) safe_copy(S.usm_radius_2, val, sizeof(S.usm_radius_2));
            else if (!strcmp(key, "usm_amount_2")) safe_copy(S.usm_amount_2, val, sizeof(S.usm_amount_2));
            else if (!strcmp(key, "usm_threshold_2")) safe_copy(S.usm_threshold_2, val, sizeof(S.usm_threshold_2));
            
            else if (!strcmp(key, "deband_method_2")) safe_copy(S.deband_method_2, val, sizeof(S.deband_method_2));
            else if (!strcmp(key, "deband_strength_2")) safe_copy(S.deband_strength_2, val, sizeof(S.deband_strength_2));
            else if (!strcmp(key, "f3kdb_range_2")) safe_copy(S.f3kdb_range_2, val, sizeof(S.f3kdb_range_2));
            else if (!strcmp(key, "f3kdb_y_2")) safe_copy(S.f3kdb_y_2, val, sizeof(S.f3kdb_y_2));
            else if (!strcmp(key, "f3kdb_cbcr_2")) safe_copy(S.f3kdb_cbcr_2, val, sizeof(S.f3kdb_cbcr_2));
            
            else if (!strcmp(key, "grain_strength_2")) safe_copy(S.grain_strength_2, val, sizeof(S.grain_strength_2));
            
            else if (!strcmp(key, "use_denoise_2")) S.use_denoise_2 = atoi(val);
            else if (!strcmp(key, "use_deblock_2")) S.use_deblock_2 = atoi(val);
            else if (!strcmp(key, "use_dering_2")) S.use_dering_2 = atoi(val);
            else if (!strcmp(key, "use_sharpen_2")) S.use_sharpen_2 = atoi(val);
            else if (!strcmp(key, "use_deband_2")) S.use_deband_2 = atoi(val);
            else if (!strcmp(key, "use_grain_2")) S.use_grain_2 = atoi(val);
            
            else if (!strcmp(key, "mi_mode")) safe_copy(S.mi_mode, val, sizeof(S.mi_mode));
            
            else if (!strcmp(key, "eq_contrast")) safe_copy(S.eq_contrast, val, sizeof(S.eq_contrast));
            else if (!strcmp(key, "eq_brightness")) safe_copy(S.eq_brightness, val, sizeof(S.eq_brightness));
            else if (!strcmp(key, "eq_saturation")) safe_copy(S.eq_saturation, val, sizeof(S.eq_saturation));
            
            else if (!strcmp(key, "lut3d_file")) safe_copy(S.lut3d_file, val, sizeof(S.lut3d_file));
            else if (!strcmp(key, "x265_params")) safe_copy(S.x265_params, val, sizeof(S.x265_params));
            
            else if (!strcmp(key, "outdir")) safe_copy(S.outdir, val, sizeof(S.outdir));
            else if (!strcmp(key, "audio_bitrate")) safe_copy(S.audio_bitrate, val, sizeof(S.audio_bitrate));
            else if (!strcmp(key, "movflags")) safe_copy(S.movflags, val, sizeof(S.movflags));
            else if (!strcmp(key, "threads")) safe_copy(S.threads, val, sizeof(S.threads));
            
            else if (!strcmp(key, "hwaccel")) safe_copy(S.hwaccel, val, sizeof(S.hwaccel));
            else if (!strcmp(key, "encoder")) safe_copy(S.encoder, val, sizeof(S.encoder));
            
            else if (!strcmp(key, "use10")) S.use10 = atoi(val);
            else if (!strcmp(key, "preview")) S.preview = atoi(val);
            
            else if (!strcmp(key, "no_deblock")) S.no_deblock = atoi(val);
            else if (!strcmp(key, "no_denoise")) S.no_denoise = atoi(val);
            else if (!strcmp(key, "no_decimate")) S.no_decimate = atoi(val);
            else if (!strcmp(key, "no_interpolate")) S.no_interpolate = atoi(val);
            
            else if (!strcmp(key, "no_sharpen")) S.no_sharpen = atoi(val);
            else if (!strcmp(key, "no_deband")) S.no_deband = atoi(val);
            else if (!strcmp(key, "no_eq")) S.no_eq = atoi(val);
            else if (!strcmp(key, "no_grain")) S.no_grain = atoi(val);
            
            else if (!strcmp(key, "pci_safe_mode")) S.pci_safe_mode = atoi(val);
        }
    }
    fclose(fp);
}


// MARK: -load_preset_file-


void ensure_conf_dirs(void) {
    mkdir_p(GPTPRO_PRESET_DIR);
    char def[PATH_MAX]; snprintf(def, sizeof(def), "%s/default.preset", GPTPRO_PRESET_DIR);
    struct stat st;
    if (stat(def, &st) != 0) { S = DEF; save_preset_file("default"); }
    if (stat(GPTPRO_ACTIVE_FILE, &st) != 0) {
        FILE *fp = fopen(GPTPRO_ACTIVE_FILE, "w"); if(fp) { fprintf(fp, "default\n"); fclose(fp); }
    }
}




void active_preset_name(char *out, size_t outsz) {
    FILE *fp = fopen(GPTPRO_ACTIVE_FILE, "r");
    if (!fp || !fgets(out, (int)outsz, fp)) safe_copy(out, "default", outsz);
    else {
    size_t n = strlen(out); while(n > 0 && isspace(out[n-1])) out[--n] = 0; }
    if (fp) fclose(fp);
}




void set_active_preset(const char *name) {
    FILE *fp = fopen(GPTPRO_ACTIVE_FILE, "w"); if (fp) { fprintf(fp, "%s\n", name); fclose(fp); }
}



void list_presets(char ***names, int *count) {
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
