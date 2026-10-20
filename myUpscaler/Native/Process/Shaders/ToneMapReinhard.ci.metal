#include "ShaderCommon.h"

// Simple Reinhard tone map in linear domain
extern "C" float4 tone_map_reinhard(coreimage::sampler src, float exposure) {
    float4 s = src.sample(src.coord());
    float3 lin = srgbToLinear(s.rgb) * exposure;
    float3 mapped = lin / (1.0 + lin);
    return clamp01(float4(mapped, s.a));
}
