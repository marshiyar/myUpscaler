#include "neo_adapter.h"
#include "core.h"
#include <cstdio>
#include <limits>
#include <memory>
#include <stdexcept>

struct up60p_neo_handle {
    up60p_neo_options options;
    std::unique_ptr<f3kdb_core_t> core;
    std::mutex mutex;
};
static int failure(int status, const char *message, char *error, size_t size) noexcept {
    if (error && size) std::snprintf(error, size, "%s", message ? message : "Neo F3kdb failed");
    return status;
}
static void require(bool valid, const char *message) {
    if (!valid) throw std::invalid_argument(message);
}
static bool depth(int value) { return value == 8 || value == 10 || value == 16; }
static void validate(const up60p_neo_options &o) {
    require(o.width >= 16 && o.height >= 16 && o.width <= 8192 && o.height <= 8192,
            "Neo geometry must be 16..8192");
    require(size_t(o.width) * o.height <= 16777216, "Neo frame exceeds 16 megapixels");
    require(o.frames > 0 && o.frames <= 10000000, "Neo requires actual positive frame count, at most 10000000");
    require(depth(o.input_depth) && depth(o.output_depth), "Neo supports 8, 10 or 16-bit integer samples");
    require(o.subsampling_width >= 0 && o.subsampling_width <= 1 &&
            o.subsampling_height >= 0 && o.subsampling_height <= 1,
            "Neo supports planar 444, 422, 440 or 420");
    require(!(o.width % (1 << o.subsampling_width)) && !(o.height % (1 << o.subsampling_height)),
            "Subsampled Neo dimensions must be divisible by subsampling factors");
    require(o.range >= 0 && o.range <= 255, "Neo range must be 0..255");
    require(o.y >= 0 && o.y <= 511 && o.cb >= 0 && o.cb <= 511 && o.cr >= 0 && o.cr <= 511,
            "Neo thresholds must be 0..511");
    require(o.sample_mode >= 1 && o.sample_mode <= 7 && o.dither >= 1 && o.dither <= 4,
            "Invalid Neo sample or dither mode");
    require(o.dither != 4 || o.output_depth == 16, "Neo interleaved 16-bit dither requires 16-bit output");
    require((o.blur_first == 0 || o.blur_first == 1) && (o.keep_tv_range == 0 || o.keep_tv_range == 1),
            "Invalid Neo boolean option");
}
extern "C" int up60p_neo_create(const up60p_neo_options *options, up60p_neo_handle **result,
                                 char *error, size_t size) {
    if (error && size) error[0] = 0;
    if (!result) return failure(UP60P_NEO_INVALID, "Missing Neo handle destination", error, size);
    *result = nullptr;
    try {
        require(options, "Missing Neo options");
        validate(*options);
        auto handle = std::make_unique<up60p_neo_handle>();
        handle->options = *options;
        DSVideoInfo vi;
        vi.Width = options->width; vi.Height = options->height; vi.Frames = options->frames;
        vi.Format.BitsPerSample = options->input_depth;
        vi.Format.BytesPerSample = options->input_depth == 8 ? 1 : 2;
        vi.Format.SSW = options->subsampling_width; vi.Format.SSH = options->subsampling_height;
        f3kdb_params_t params;
        params.range = options->range;
        params.Y = params.Y_1 = params.Y_2 = options->y * 4;
        params.Cb = params.Cb_1 = params.Cb_2 = options->cb * 4;
        params.Cr = params.Cr_1 = params.Cr_2 = options->cr * 4;
        params.grainY = params.grainC = 0;
        params.seed = options->seed; params.sample_mode = options->sample_mode;
        params.blur_first = options->blur_first != 0; params.keep_tv_range = options->keep_tv_range != 0;
        params.output_depth = options->output_depth;
        params.dither_algo = options->output_depth == 16 ? DA_16BIT_INTERLEAVED : DITHER_ALGORITHM(options->dither);
        handle->core = std::make_unique<f3kdb_core_t>(vi, params, IMPL_C);
        *result = handle.release();
        return UP60P_NEO_OK;
    } catch (const std::invalid_argument &e) { return failure(UP60P_NEO_INVALID, e.what(), error, size); }
      catch (const std::exception &e) { return failure(UP60P_NEO_FAILURE, e.what(), error, size); }
      catch (const char *e) { return failure(UP60P_NEO_FAILURE, e, error, size); }
      catch (...) { return failure(UP60P_NEO_FAILURE, "Unknown Neo creation failure", error, size); }
}
static size_t extent(int stride, int rows, int rowBytes) {
    require(stride >= rowBytes && stride > 0, "Neo stride is shorter than row or negative");
    return size_t(stride) * size_t(rows - 1) + size_t(rowBytes);
}
static bool overlap(uintptr_t a, size_t as, uintptr_t b, size_t bs) {
    require(as <= std::numeric_limits<uintptr_t>::max() - a &&
            bs <= std::numeric_limits<uintptr_t>::max() - b, "Neo buffer address overflow");
    return a < b + bs && b < a + as;
}
extern "C" int up60p_neo_process(up60p_neo_handle *handle, int frame, const up60p_neo_source source[3],
                                  const up60p_neo_destination destination[3], up60p_neo_cancel cancel,
                                  void *context, char *error, size_t size) {
    if (error && size) error[0] = 0;
    try {
        require(handle && source && destination, "Missing Neo frame buffers or handle");
        std::lock_guard<std::mutex> lock(handle->mutex);
        const auto &o = handle->options;
        require(frame >= 0 && frame < o.frames, "Neo frame ordinal outside actual frame count");
        size_t inputSize[3], outputSize[3];
        for (int p = 0; p < 3; ++p) {
            const int w = o.width >> (p ? o.subsampling_width : 0);
            const int h = o.height >> (p ? o.subsampling_height : 0);
            require(source[p].data && destination[p].data, "Missing Neo plane");
            inputSize[p] = extent(source[p].stride, h, w * (o.input_depth == 8 ? 1 : 2));
            outputSize[p] = extent(destination[p].stride, h, w * (o.output_depth == 8 ? 1 : 2));
            require(source[p].capacity >= inputSize[p] && destination[p].capacity >= outputSize[p],
                    "Neo buffer is shorter than plane extent");
            require(o.input_depth == 8 || !(uintptr_t(source[p].data) % 2 || source[p].stride % 2),
                    "Neo high-depth source requires two-byte alignment");
            require(o.output_depth == 8 || !(uintptr_t(destination[p].data) % 2 || destination[p].stride % 2),
                    "Neo high-depth destination requires two-byte alignment");
        }
        for (int p = 0; p < 3; ++p) for (int q = 0; q < 3; ++q) {
            require(!overlap(uintptr_t(source[p].data), inputSize[p], uintptr_t(destination[q].data), outputSize[q]),
                    "Neo source and destination overlap");
            if (p != q) require(!overlap(uintptr_t(destination[p].data), outputSize[p],
                                       uintptr_t(destination[q].data), outputSize[q]), "Neo destination planes overlap");
        }
        for (int p = 0; p < 3; ++p) {
            if (cancel && cancel(context)) return failure(UP60P_NEO_CANCELLED, "Neo processing cancelled", error, size);
            handle->core->process_plane(frame, p, destination[p].data, destination[p].stride,
                                       source[p].data, source[p].stride);
        }
        if (cancel && cancel(context)) return failure(UP60P_NEO_CANCELLED, "Neo processing cancelled", error, size);
        return UP60P_NEO_OK;
    } catch (const std::invalid_argument &e) { return failure(UP60P_NEO_INVALID, e.what(), error, size); }
      catch (const std::exception &e) { return failure(UP60P_NEO_FAILURE, e.what(), error, size); }
      catch (const char *e) { return failure(UP60P_NEO_FAILURE, e, error, size); }
      catch (...) { return failure(UP60P_NEO_FAILURE, "Unknown Neo processing failure", error, size); }
}
extern "C" void up60p_neo_destroy(up60p_neo_handle *handle) { delete handle; }
