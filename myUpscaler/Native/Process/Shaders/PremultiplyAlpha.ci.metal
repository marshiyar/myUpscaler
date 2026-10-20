#include "ShaderCommon.h"

// Premultiply RGB by alpha
extern "C" float4 premultiply_alpha(coreimage::sampler src) {
    float4 c = src.sample(src.coord());
    return float4(c.rgb * c.a, c.a);
}
