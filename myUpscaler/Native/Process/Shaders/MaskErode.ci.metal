#include "ShaderCommon.h"

// Erode a single-channel mask
extern "C" float4 mask_erode(coreimage::sampler src, float radius) {
    float2 dc = src.coord();
    int r = clamp(int(radius + 0.5), 0, 3);
    float minV = 1.0;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            minV = min(minV, src.sample(dc + float2(x, y)).r);
        }
    }
    return float4(minV, minV, minV, 1.0);
}
