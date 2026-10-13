#include "ShaderCommon.h"

// Feather a single-channel mask
extern "C" float4 mask_feather(coreimage::sampler src, float radius) {
    float2 dc = src.coord();
    int r = clamp(int(radius + 0.5), 0, 3);
    float sum = 0.0;
    float weight = 0.0;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            float dist2 = float(x * x + y * y);
            float w = exp(-dist2 / max(1.0, radius * radius));
            sum += src.sample(dc + float2(x, y)).r * w;
            weight += w;
        }
    }
    float v = weight > 0 ? sum / weight : src.sample(dc).r;
    return float4(v, v, v, 1.0);
}
