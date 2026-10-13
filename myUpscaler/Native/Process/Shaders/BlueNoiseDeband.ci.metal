#include "ShaderCommon.h"

// Deband without static blue-noise by blending toward neighborhood average
extern "C" float4 blue_noise_deband(coreimage::sampler src, float threshold, float amount) {
    float2 dc = src.coord();
    float4 center = src.sample(dc);

    float4 n1 = src.sample(dc + float2(-1.0, -1.0));
    float4 n2 = src.sample(dc + float2(1.0, 1.0));
    float3 avg = (n1.rgb + n2.rgb + center.rgb) / 3.0;

    float3 diff = abs(center.rgb - avg);
    float max_diff = max(max(diff.r, diff.g), diff.b);

    float factor = 1.0 - smoothstep(0.0, threshold, max_diff);
    if (factor <= 0.0) { return center; }

    float blend = clamp(amount * factor, 0.0, 1.0);
    float3 out_rgb = mix(center.rgb, avg, blend);
    return float4(out_rgb, center.a);
}
