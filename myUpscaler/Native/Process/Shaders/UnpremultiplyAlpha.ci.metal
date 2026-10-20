#include "ShaderCommon.h"

// Unpremultiply RGB with a safe alpha divisor
extern "C" float4 unpremultiply_alpha(coreimage::sampler src) {
    float4 c = src.sample(src.coord());
    float safeA = max(c.a, 0.0001);
    return float4(c.rgb / safeA, c.a);
}
