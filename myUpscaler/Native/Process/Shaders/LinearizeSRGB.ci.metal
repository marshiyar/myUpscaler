#include "ShaderCommon.h"

// Linearize sRGB and optionally apply exposure gain
extern "C" float4 linearize_srgb(coreimage::sampler src, float exposure) {
    float4 s = src.sample(src.coord());
    float3 lin = srgbToLinear(s.rgb) * exposure;
    return clamp01(float4(lin, s.a));
}
