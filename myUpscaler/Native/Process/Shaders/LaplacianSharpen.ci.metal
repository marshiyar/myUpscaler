#include "ShaderCommon.h"

// Edge-preserving sharpen using a Laplacian estimate
extern "C" float4 laplacian_sharpen(coreimage::sampler src, float strength) {
    float2 dc = src.coord();
    float3 center = src.sample(dc).rgb;
    float3 left = src.sample(dc + float2(-1.0, 0.0)).rgb;
    float3 right = src.sample(dc + float2(1.0, 0.0)).rgb;
    float3 up = src.sample(dc + float2(0.0, -1.0)).rgb;
    float3 down = src.sample(dc + float2(0.0, 1.0)).rgb;
    float3 lap = (left + right + up + down) * 0.25 - center;
    float3 enhanced = center - lap * strength;
    return clamp01(float4(enhanced, src.sample(dc).a));
}
