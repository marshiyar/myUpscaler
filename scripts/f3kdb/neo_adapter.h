#ifndef UP60P_NEO_ADAPTER_H
#define UP60P_NEO_ADAPTER_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct up60p_neo_handle up60p_neo_handle;
/* Integer, little-endian, low-aligned planar Y/Cb/Cr. No host frame ABI. */
typedef struct {
    int width, height, frames, input_depth, output_depth;
    int subsampling_width, subsampling_height;
    int range, y, cb, cr, seed, sample_mode, dither;
    int blur_first, keep_tv_range;
} up60p_neo_options;
typedef struct { const uint8_t *data; size_t capacity; int stride; } up60p_neo_source;
typedef struct { uint8_t *data; size_t capacity; int stride; } up60p_neo_destination;
typedef int (*up60p_neo_cancel)(void *context);
enum { UP60P_NEO_OK = 0, UP60P_NEO_INVALID = 1, UP60P_NEO_FAILURE = 2, UP60P_NEO_CANCELLED = 3 };
/* All diagnostics are copied to the caller's buffer. No exception crosses C.
 * Grain is zero; thresholds/detail thresholds use public Neo units (x4 inside).
 * One handle serializes calls. Destruction requires callers to have joined.
 * Cancellation sampler must be nonblocking and must not reenter this handle.
 * Process checks all planes before writing; destination is unpublished scratch
 * on cancellation/failure. Source/destination allocations must not overlap. */
int up60p_neo_create(const up60p_neo_options *, up60p_neo_handle **, char *, size_t);
int up60p_neo_process(up60p_neo_handle *, int frame, const up60p_neo_source[3],
                      const up60p_neo_destination[3], up60p_neo_cancel, void *, char *, size_t);
void up60p_neo_destroy(up60p_neo_handle *);
#ifdef __cplusplus
}
#endif
#endif
