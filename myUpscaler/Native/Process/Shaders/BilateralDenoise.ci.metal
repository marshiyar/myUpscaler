#include "ShaderCommon.h"

// Bilateral denoise with precomputed 5x5 offsets
static constant int  kBilatRadius = 2;
static constant int  kBilatKernelSize = (kBilatRadius * 2 + 1) * (kBilatRadius * 2 + 1);

static constant float2 kBilatOffsets[kBilatKernelSize] = {
    float2(-2.0, -2.0), float2(-1.0, -2.0), float2(0.0, -2.0), float2(1.0, -2.0), float2(2.0, -2.0),
    float2(-2.0, -1.0), float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0), float2(2.0, -1.0),
    float2(-2.0,  0.0), float2(-1.0,  0.0), float2(0.0,  0.0), float2(1.0,  0.0), float2(2.0,  0.0),
    float2(-2.0,  1.0), float2(-1.0,  1.0), float2(0.0,  1.0), float2(1.0,  1.0), float2(2.0,  1.0),
    float2(-2.0,  2.0), float2(-1.0,  2.0), float2(0.0,  2.0), float2(1.0,  2.0), float2(2.0,  2.0),
};

static constant float kBilatDist2[kBilatKernelSize] = {
    8.0, 5.0, 4.0, 5.0, 8.0,
    5.0, 2.0, 1.0, 2.0, 5.0,
    4.0, 1.0, 0.0, 1.0, 4.0,
    5.0, 2.0, 1.0, 2.0, 5.0,
    8.0, 5.0, 4.0, 5.0, 8.0,
};

extern "C" float4 bilateral_denoise(coreimage::sampler src,
                                    float sigma_spatial,
                                    float sigma_range) {
    float2 dc = src.coord();
    float4 c4 = src.sample(dc);
    float3 c  = c4.rgb;

    // If sigma_range is ~0, early-out – no reason to spend time
    if (sigma_range <= 0.0 || sigma_spatial <= 0.0) {
        return c4;
    }

    float invTwoSigmaSpatial2 = 1.0 / max(2.0 * sigma_spatial * sigma_spatial, 1e-4);
    float invTwoSigmaRange2   = 1.0 / max(2.0 * sigma_range   * sigma_range,   1e-4);

    float3 sum = float3(0.0);
    float  wsum = 0.0;

    // 5x5 kernel, precomputed offsets & dist²
    for (int i = 0; i < kBilatKernelSize; ++i) {
        float2 offset = kBilatOffsets[i];
        float4 s4 = src.sample(dc + offset);
        float3 s  = s4.rgb;

        float3 diff = c - s;
        float  colorDist2 = dot(diff, diff);
        float  dist2 = kBilatDist2[i];

        // Single exponent: spatial + range in one go
        float w = fast::exp(-dist2 * invTwoSigmaSpatial2
                            - colorDist2 * invTwoSigmaRange2);

        sum  += s * w;
        wsum += w;
    }

    float invW = (wsum > 0.0) ? (1.0 / wsum) : 1.0;
    float3 denoised = sum * invW;

    // Prevent over-smoothing: mix back some original based on sigma_range
    float mixOriginal = clamp(1.0 - sigma_range * 4.0, 0.0, 0.5);
    float3 out = mix(denoised, c, mixOriginal);

    return float4(out, c4.a);
}
