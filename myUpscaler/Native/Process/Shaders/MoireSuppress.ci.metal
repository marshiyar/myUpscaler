#include "ShaderCommon.h"

// Moire suppression
extern "C" float4 moire_suppress(coreimage::sampler src, float strength) {
    float2 dc = src.coord();
    float3 center = src.sample(dc).rgb;
    float3 diag = (src.sample(dc + float2( 1.0,  1.0)).rgb +
                   src.sample(dc + float2(-1.0, -1.0)).rgb +
                   src.sample(dc + float2(-1.0,  1.0)).rgb +
                   src.sample(dc + float2( 1.0, -1.0)).rgb) * 0.25;
    float3 cross = (src.sample(dc + float2( 1.0,  0.0)).rgb +
                    src.sample(dc + float2(-1.0,  0.0)).rgb +
                    src.sample(dc + float2( 0.0,  1.0)).rgb +
                    src.sample(dc + float2( 0.0, -1.0)).rgb) * 0.25;
    float3 smooth = mix(cross, diag, 0.5);
    float3 cleaned = mix(center, smooth, strength);
    return float4(cleaned, src.sample(dc).a);
}
