#include "ShaderCommon.h"

// Halo suppression
extern "C" float4 dehalo(coreimage::sampler src, float strength) {
    float2 dc = src.coord();
    float4 c = src.sample(dc);

    float3 ring = (src.sample(dc + float2(-1.0, 0.0)).rgb +
                   src.sample(dc + float2(1.0, 0.0)).rgb +
                   src.sample(dc + float2(0.0, -1.0)).rgb +
                   src.sample(dc + float2(0.0, 1.0)).rgb) * 0.25;

    float3 low = min(min(ring, c.rgb),
                     min(src.sample(dc + float2(-1.0, -1.0)).rgb,
                         src.sample(dc + float2( 1.0,  1.0)).rgb));
    float3 high = max(max(ring, c.rgb),
                      max(src.sample(dc + float2(-1.0, -1.0)).rgb,
                          src.sample(dc + float2( 1.0,  1.0)).rgb));

    float3 halo = clamp(c.rgb - ring, 0.0, 1.0);
    float3 suppressed = mix(c.rgb, clamp(c.rgb - halo, low, high), strength);
    return float4(suppressed, c.a);
}
