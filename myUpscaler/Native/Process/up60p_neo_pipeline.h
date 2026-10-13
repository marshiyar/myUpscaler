#ifndef UP60P_NEO_PIPELINE_H
#define UP60P_NEO_PIPELINE_H
/* Private CPU integration. Lossless rawvideo boundaries keep the genuine Neo
 * stage at its existing filter-stack position. Temporary media is bounded and
 * owned by one private directory; final output is atomically committed. */
#define UP60P_NEO_MARKER "up60p_neo="
#define UP60P_NEO_LIMIT 134217728LL

typedef struct { int range, y, cb, cr; } up60p_neo_stage;
static bool neo_integer(const char *text, int maximum, int *output) {
    char *end; errno = 0;
    double value = strtod(text, &end);
    while (*end == ' ' || *end == '\t') ++end;
    if (end == text || *end || errno || !isfinite(value) || value < 0 || value > maximum || trunc(value) != value) return false;
    *output = (int)value;
    return true;
}
static bool neo_marker(SB *vf, const char *range, const char *y, const char *cbcr) {
    int r, l, c;
    if (!neo_integer(range, 255, &r) || !neo_integer(y, 511, &l) || !neo_integer(cbcr, 511, &c)) {
        if (global_log_cb) global_log_cb("ERROR: Genuine Neo F3kdb requires integer range 0..255 and thresholds 0..511.\n");
        return false;
    }
    // Grain is zero and output depth equals input depth: zero references or
    // zero thresholds are an exact bypass, including original graph negotiation.
    if (r && (l || c)) sb_fmt(vf, UP60P_NEO_MARKER "%d:%d:%d:%d,", r, l, c, c);
    return true;
}
static int neo_helper(const char *supervisor, const char *helper, const char *directory, char *const parameters[]) {
    if (up60p_is_cancelled()) return UP60P_PROCESS_CANCELLED;
    char *args[24]; int n = 0;
    args[n++] = (char *)helper;
    args[n++] = "--owned-neo-job"; args[n++] = (char *)directory;
    for (int i = 0; parameters[i] && n < 23; ++i) args[n++] = parameters[i];
    args[n] = NULL;
    return up60p_execute_owned_process(supervisor, args, global_log_cb);
}
static int neo_ffmpeg(const char *ffmpeg, const char *directory, char *const original[]) {
    char executable[PATH_MAX], supervisor[PATH_MAX]; uint32_t size = sizeof(executable);
    const char *bundled = up60p_bundled_ffmpeg_path();
    if (!bundled || strcmp(bundled, ffmpeg) || _NSGetExecutablePath(executable, &size) ||
        !up60p_resolve_bundled_executable(executable, "up60p-ffmpeg-supervisor", supervisor, sizeof(supervisor))) return -1;
    char *args[164]; int a = 0;
    args[a++] = (char *)ffmpeg; args[a++] = "--owned-neo-job"; args[a++] = (char *)directory;
    for (int i = 1; original[i] && a < 163; ++i) args[a++] = original[i];
    args[a] = NULL;
    return up60p_execute_owned_process(supervisor, args, global_log_cb);
}
static bool neo_bounded_file(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0 && st.st_size < UP60P_NEO_LIMIT;
}
static void neo_restore_color(SB *graph, const char *color[5]) {
    // NUT rawvideo keeps timestamps but drops codec color fields. Restore the
    // source properties before every subsequent colorspace/scale conversion.
    sb_fmt(graph, "setparams=range=%s:color_primaries=%s:color_trc=%s:colorspace=%s:chroma_location=%s",
           color[3], color[0], color[1], color[2], color[4]);
}
static int neo_filter_boundary(const char *ffmpeg, const char *input, const char *output,
                               const char *filter, bool image, const char *color[5], const char *directory) {
    SB graph = {0};
    neo_restore_color(&graph, color); sb_append(&graph, ",");
    if (filter && *filter) { sb_append(&graph, filter); sb_append(&graph, ","); }
    sb_append(&graph, "format=yuv444p16le");
    char *args[64]; int a = 0;
    args[a++] = (char *)ffmpeg; args[a++] = "-hide_banner"; args[a++] = "-loglevel";
    args[a++] = "error"; args[a++] = "-nostats"; args[a++] = "-nostdin"; args[a++] = "-y";
    args[a++] = "-copyts"; args[a++] = "-i"; args[a++] = (char *)input;
    args[a++] = "-vf"; args[a++] = graph.buf;
    args[a++] = "-map"; args[a++] = "0:v:0"; args[a++] = "-map"; args[a++] = "0:a?";
    args[a++] = "-fps_mode"; args[a++] = "passthrough";
    args[a++] = "-threads"; args[a++] = "1"; args[a++] = "-filter_threads"; args[a++] = "1";
    args[a++] = "-c:v"; args[a++] = "rawvideo"; args[a++] = "-c:a"; args[a++] = "copy";
    if (image) { args[a++] = "-frames:v"; args[a++] = "1"; }
    const char *names[5] = {"color_primaries", "color_trc", "colorspace", "color_range", "chroma_sample_location"};
    char tags[5][64];
    for (int i = 0; i < 5; ++i) {
        snprintf(tags[i], sizeof(tags[i]), "neo.%s=%s", names[i], color[i]);
        args[a++] = "-metadata:s:v:0"; args[a++] = tags[i];
    }
    args[a++] = "-fs"; args[a++] = "134217728";
    args[a++] = "-f"; args[a++] = "nut"; args[a++] = (char *)output; args[a] = NULL;
    int result = graph.buf ? neo_ffmpeg(ffmpeg, directory, args) : -1;
    free(graph.buf);
    if (result == 0 && !neo_bounded_file(output)) {
        if (global_log_cb) global_log_cb("ERROR: Private Neo intermediate exceeded its 128 MiB bound or is empty.\n");
        return -1;
    }
    return result;
}
static int up60p_execute_neo_pipeline(const char *ffmpeg, char *const original[], const char *filter,
                                       const char *input, const char *output, bool image, bool preview) {
    if (!filter) return -1;
    if (!strstr(filter, UP60P_NEO_MARKER)) return execute_ffmpeg_command(original);
    if (preview) {
        if (global_log_cb) global_log_cb("ERROR: Private genuine Neo F3kdb pipeline does not yet support live preview.\n");
        return -1;
    }
    char executable[PATH_MAX], supervisor[PATH_MAX], helper[PATH_MAX];
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size) ||
        !up60p_resolve_bundled_executable(executable, "up60p-neo-supervisor", supervisor, sizeof(supervisor)) ||
        !up60p_resolve_bundled_executable(executable, "up60p-neo-media", helper, sizeof(helper))) {
        if (global_log_cb) global_log_cb("ERROR: Private genuine Neo F3kdb helper is missing; no substitute filter is used.\n");
        return -1;
    }
    char *graph = strdup(filter); if (!graph) return -1;
    char *segments[3] = {graph, NULL, NULL}; up60p_neo_stage stages[2]; int count = 0;
    char *cursor = graph, *marker;
    while ((marker = strstr(cursor, UP60P_NEO_MARKER))) {
        int used = 0;
        if (count == 2 || sscanf(marker, UP60P_NEO_MARKER "%d:%d:%d:%d%n", &stages[count].range,
                                 &stages[count].y, &stages[count].cb, &stages[count].cr, &used) != 4 ||
            (marker[used] && marker[used] != ',')) { free(graph); return -1; }
        cursor = marker + used; if (*cursor == ',') ++cursor;
        if (marker > segments[count] && marker[-1] == ',') marker[-1] = 0;
        *marker = 0; segments[++count] = cursor;
    }
    // Same-directory final temporary gives atomic rename; the private directory
    // is 0700 and every intermediate path belongs exclusively to this job.
    char directory[PATH_MAX];
    if (snprintf(directory, sizeof(directory), "%s.neo-XXXXXX", output) >= (int)sizeof(directory) || !mkdtemp(directory)) {
        free(graph); return -1;
    }
    char canonical_directory[PATH_MAX];
    if (!realpath(directory, canonical_directory)) { rmdir(directory); free(graph); return -1; }
    safe_copy(directory, canonical_directory, sizeof(directory));
    char prefix[PATH_MAX], processed[PATH_MAX], colorFile[PATH_MAX], final[PATH_MAX];
    snprintf(prefix, sizeof(prefix), "%s/input.nut", directory);
    snprintf(processed, sizeof(processed), "%s/processed.nut", directory);
    snprintf(colorFile, sizeof(colorFile), "%s/colors.txt", directory);
    snprintf(final, sizeof(final), "%s/final.%s", directory, image ? "png" : "mp4");
    char *probeArgs[] = {"--probe", (char *)input, colorFile, NULL};
    int result = neo_helper(supervisor, helper, directory, probeArgs);
    char colorValues[5][16]; const char *color[5]; int colors[5] = {0}, version;
    FILE *metadata = result == 0 ? fopen(colorFile, "r") : NULL;
    if (result == 0 && (!metadata || fscanf(metadata, "%d %d %d %d %d %d", &version, &colors[0],
                                            &colors[1], &colors[2], &colors[3], &colors[4]) != 6 || version != 1)) result = -1;
    if (metadata) fclose(metadata);
    for (int i = 0; i < 5; ++i) { snprintf(colorValues[i], sizeof(colorValues[i]), "%d", colors[i]); color[i] = colorValues[i]; }
    const char *current = input;
    for (int stage = 0; stage < count && result == 0; ++stage) {
        if (up60p_is_cancelled()) { result = UP60P_PROCESS_CANCELLED; break; }
        unlink(prefix);
        if (global_log_cb) global_log_cb("stage=processing Preparing genuine F3kdb input\n");
        result = neo_filter_boundary(ffmpeg, current, prefix, segments[stage], image && stage == 0, color, directory);
        if (current == processed) unlink(processed);
        if (result) break;
        char values[4][16]; int parameters[4] = {stages[stage].range,stages[stage].y,stages[stage].cb,stages[stage].cr};
        for (int i = 0; i < 4; ++i) snprintf(values[i], sizeof(values[i]), "%d", parameters[i]);
        char *args[] = {prefix,processed,values[0],values[1],values[2],values[3],NULL};
        if (global_log_cb) global_log_cb("stage=processing Genuine Neo F3kdb CPU deband\n");
        result = neo_helper(supervisor, helper, directory, args);
        if (!result && !neo_bounded_file(processed)) result = -1;
        unlink(prefix); current = processed;
    }
    if (result == 0) {
        SB final_graph = {0}; neo_restore_color(&final_graph, color);
        if (*segments[count]) { sb_append(&final_graph, ","); sb_append(&final_graph, segments[count]); }
        char *args[160]; int a = 0;
        // Retain all encoder/audio settings; replace only input/filter/output.
        for (int i = 0; original[i] && a < 136; ++i) {
            if (!strcmp(original[i], "-hwaccel")) { ++i; continue; }
            if (!strcmp(original[i], "-stats")) { args[a++] = "-nostats"; continue; }
            if (!strcmp(original[i], "-i")) { args[a++] = "-copyts"; args[a++] = original[i++]; args[a++] = (char *)current; }
            else if (!strcmp(original[i], "-vf")) { args[a++] = original[i++]; args[a++] = final_graph.buf; }
            else if (!strcmp(original[i], output)) {
                const char *names[5] = {"-color_primaries","-color_trc","-colorspace","-color_range","-chroma_sample_location"};
                for (int c = 0; c < 5; ++c) { args[a++] = (char *)names[c]; args[a++] = (char *)color[c]; }
                args[a++] = "-threads"; args[a++] = "1"; args[a++] = "-filter_threads"; args[a++] = "1";
                args[a++] = "-fs"; args[a++] = "134217728"; args[a++] = final;
            } else args[a++] = original[i];
        }
        args[a] = NULL;
        if (global_log_cb) global_log_cb("stage=finalizing Encoding and verifying output\n");
        result = up60p_is_cancelled() ? UP60P_PROCESS_CANCELLED : (final_graph.buf ? neo_ffmpeg(ffmpeg, directory, args) : -1);
        if (!result && !neo_bounded_file(final)) result = -1;
        if (!result) {
            // Verify decode before publishing and preserve an existing output
            // through every failed/cancelled stage.
            char *verify[] = {(char *)ffmpeg,"-v","error","-nostdin","-threads","1","-i",final,
                              "-map","0:v:0","-f","null","-",NULL};
            result = neo_ffmpeg(ffmpeg, directory, verify);
        }
        if (!result) result = up60p_commit_output(final, output);
        free(final_graph.buf);
    }
    unlink(prefix); unlink(processed); unlink(colorFile); unlink(final); rmdir(directory); free(graph);
    return result == UP60P_PROCESS_COMMITTED ? result :
           (up60p_is_cancelled() ? UP60P_PROCESS_CANCELLED : result);
}
#endif
