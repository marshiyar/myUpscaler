#ifndef UP60P_FPS_H
#define UP60P_FPS_H
#include "up60p_settings.h"
#include "up60p_utils.h"
#include <math.h>
#include <limits.h>

static bool up60p_target_rate(const char *text, double *rate) {
    for (const char *p = text; *p; p++)
        if (!strchr("0123456789./+-eE", *p)) return false;
    char *end;
    double numerator = strtod(text, &end), denominator = 1;
    if (end == text) return false;
    if (*end == '/') {
        const char *start = end + 1;
        denominator = strtod(start, &end);
        if (end == start) return false;
    }
    *rate = numerator / denominator;
    return !*end && isfinite(numerator) && isfinite(denominator) && isfinite(*rate) &&
        numerator > 0 && denominator > 0 && *rate > 0 && *rate <= INT_MAX;
}

static bool up60p_build_fps_filter(SB *vf, const Settings *settings) {
    if (!strcmp(settings->fps, "source") || !strcmp(settings->fps, "lock")) return true;
    double target;
    if (!up60p_target_rate(settings->fps, &target)) {
        if (global_log_cb) global_log_cb("Invalid target FPS: a positive finite rate or rational is required.\n");
        return false;
    }
    bool interpolate = !settings->no_interpolate && strcmp(settings->mi_mode, "dup");
    bool timing_known = settings->source_cfr_verified && settings->source_frame_count > 0 &&
        isfinite(settings->source_video_duration) && settings->source_video_duration > 0 &&
        settings->source_rate_num > 0 && settings->source_rate_den > 0;
    double count = timing_known ? settings->source_video_duration * target : 0;
    if (timing_known && (!isfinite(count) || count > (double)INT64_MAX / 2)) return false;
    int64_t frames = timing_known ? (int64_t)floor(count + 0.5 + 1e-9) : 0;
    if (timing_known && frames < 1) frames = 1;
    if (timing_known) {
        double source_rate = (double)settings->source_rate_num / settings->source_rate_den;
        if (target <= source_rate * (1 + 1e-9) || settings->source_frame_count == 1) interpolate = false;
        // Padding stops when downstream trim reaches the finite requested count.
        // This also restores a static tail that mpdecimate removed. No motion is
        // invented beyond the final source frame: the last image is held.
        sb_append(vf, "tpad=stop_mode=clone:stop=-1,");
    } else if (interpolate && global_log_cb) {
        global_log_cb("Source timing is unknown or variable; motion interpolation may shorten the final frames.\n");
    }
    if (interpolate) {
        sb_fmt(vf, "minterpolate=fps=%s:mi_mode=%s:mc_mode=aobmc:me_mode=bidir:vsbmc=1,", settings->fps, settings->mi_mode);
    } else {
        sb_fmt(vf, "fps=fps=%s,", settings->fps);
    }
    if (timing_known) sb_fmt(vf, "trim=end_frame=%lld,", (long long)frames);
    return true;
}
#endif
