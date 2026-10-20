#include "ShaderCommon.h"

// Temporal smoothing in linear light
extern "C" float4 temporal_smooth(coreimage::sampler current,
                                  coreimage::sampler previous,
                                  float strength) {
    float2 dc = current.coord();
    float4 c = current.sample(dc);
    float4 p = previous.sample(dc);
    float3 lc = srgbToLinear(c.rgb);
    float3 lp = srgbToLinear(p.rgb);
    float s = clamp(strength, 0.0, 1.0);
    float3 blended = mix(lc, lp, s);
    return clamp01(float4(linearToSrgb(blended), mix(c.a, p.a, s)));
}
