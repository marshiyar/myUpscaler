#include "ShaderCommon.h"

// Median denoise by sorting a 3x3 neighborhood by luminance
extern "C" float4 median_denoise(coreimage::sampler src) {
    float2 dc = src.coord();
    float3 samples[9];
    int idx = 0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            samples[idx++] = src.sample(dc + float2(x, y)).rgb;
        }
    }
    // Simple sort by luminance
    for (int i = 0; i < 9; ++i) {
        for (int j = i + 1; j < 9; ++j) {
            float li = dot(samples[i], float3(0.299, 0.587, 0.114));
            float lj = dot(samples[j], float3(0.299, 0.587, 0.114));
            if (lj < li) {
                float3 tmp = samples[i];
                samples[i] = samples[j];
                samples[j] = tmp;
            }
        }
    }
    float3 median = samples[4];
    float4 c = src.sample(dc);
    return float4(median, c.a);
}
