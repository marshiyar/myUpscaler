#include "ShaderCommon.h"

// Gamma-correct blend between two images in linear domain
extern "C" float4 gamma_correct_blend(coreimage::sampler a,
                                     coreimage::sampler b,
                                     float mixFactor) {
    float2 dc = a.coord();
    float4 sa = a.sample(dc);
    float4 sb = b.sample(dc);
    float3 la = srgbToLinear(sa.rgb);
    float3 lb = srgbToLinear(sb.rgb);
    float3 blended = mix(la, lb, clamp(mixFactor, 0.0, 1.0));
    return clamp01(float4(linearToSrgb(blended), mix(sa.a, sb.a, mixFactor)));
}
