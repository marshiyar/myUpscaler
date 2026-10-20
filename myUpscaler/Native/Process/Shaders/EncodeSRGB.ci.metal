#include "ShaderCommon.h"

// Encode linear back to sRGB
extern "C" float4 encode_srgb(coreimage::sampler src, float exposure) {
    float4 s = src.sample(src.coord());
    float3 encoded = linearToSrgb(s.rgb * exposure);
    return clamp01(float4(encoded, s.a));
}
