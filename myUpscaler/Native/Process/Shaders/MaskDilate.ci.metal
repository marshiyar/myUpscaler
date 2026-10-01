#include "ShaderCommon.h"

// Dilate a single-channel mask
extern "C" float4 mask_dilate(coreimage::sampler src, float radius) {
    float2 dc = src.coord();
    int r = clamp(int(radius + 0.5), 0, 3);
    float maxV = 0.0;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            maxV = max(maxV, src.sample(dc + float2(x, y)).r);
        }
    }
    return float4(maxV, maxV, maxV, 1.0);
}
