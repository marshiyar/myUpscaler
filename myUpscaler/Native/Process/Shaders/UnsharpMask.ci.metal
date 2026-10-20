#include "ShaderCommon.h"

// Unsharp mask with edge thresholding to limit halos
/// Simple box blur helper for small radius (1-2)
float3 boxBlur(coreimage::sampler src, float2 dc, int radius) {
    float3 sum = float3(0.0);
    float weight = 0.0;
    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            float3 sample = src.sample(dc + float2(x, y)).rgb;
            sum += sample;
            weight += 1.0;
        }
    }
    return sum / max(weight, 1.0);
}

extern "C" float4 unsharp_mask(coreimage::sampler src, float radius, float amount, float threshold) {
    float2 dc = src.coord();
    int r = clamp(int(radius + 0.5), 1, 2); // small radius for perf
    float4 c = src.sample(dc);
    float3 blur = boxBlur(src, dc, r);
    float3 high = c.rgb - blur;
    float3 edgeMask = smoothstep(threshold, threshold * 1.6, abs(high));
    float3 sharpened = c.rgb + high * amount * edgeMask;
    return clamp01(float4(sharpened, c.a));
}
