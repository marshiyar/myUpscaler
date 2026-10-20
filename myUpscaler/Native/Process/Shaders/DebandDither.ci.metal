#include "ShaderCommon.h"

// Debanding with noise-free gradients
extern "C" float4 deband_dither(coreimage::sampler src, float threshold, float amount) {
    float2 dc = src.coord();
    float4 center = src.sample(dc);

    float4 s1 = src.sample(dc + float2(-2.0, -2.0));
    float4 s2 = src.sample(dc + float2( 2.0, -2.0));
    float4 s3 = src.sample(dc + float2(-2.0,  2.0));
    float4 s4 = src.sample(dc + float2( 2.0,  2.0));

    float3 avg = (s1.rgb + s2.rgb + s3.rgb + s4.rgb) * 0.25;

    const float3 lumaW = float3(0.299, 0.587, 0.114);
    float lc = dot(center.rgb, lumaW);
    float la = dot(avg,        lumaW);

    float diffL = fabs(lc - la);

    // Additional local contrast check: we only deband in very flat regions
    float localVar =
    fabs(dot(s1.rgb - s2.rgb, lumaW)) +
    fabs(dot(s3.rgb - s4.rgb, lumaW));

    float flatFactor = 1.0 - smoothstep(threshold * 2.0, threshold * 6.0, localVar);

    float bandFactor = 1.0 - smoothstep(0.0, threshold, diffL);
    float factor = bandFactor * flatFactor;

    if (factor <= 0.0) return center;

    float blend = clamp(amount * factor, 0.0, 1.0);
    float3 out_rgb = mix(center.rgb, avg, blend);
    return float4(out_rgb, center.a);
}
