#include "ShaderCommon.h"

// Color stabilization against the baseline image
extern "C" float4 drift_guard(coreimage::sampler ai,
                              coreimage::sampler base,
                              float threshold,
                              float amount) {
    float2 dc = ai.coord();
    float4 s4 = ai.sample(dc);
    float4 b4 = base.sample(dc);

    float3 s = s4.rgb;
    float3 b = b4.rgb;

    // Raw per-pixel difference
    float3 diff = abs(s - b);
    float max_diff = max(max(diff.r, diff.g), diff.b);

    // Local neighborhood for detail measure (simple 4-neighbor cross)
    float3 sL = ai.sample(dc + float2(-1.0,  0.0)).rgb;
    float3 sR = ai.sample(dc + float2( 1.0,  0.0)).rgb;
    float3 sU = ai.sample(dc + float2( 0.0, -1.0)).rgb;
    float3 sD = ai.sample(dc + float2( 0.0,  1.0)).rgb;

    float3 bL = base.sample(dc + float2(-1.0,  0.0)).rgb;
    float3 bR = base.sample(dc + float2( 1.0,  0.0)).rgb;
    float3 bU = base.sample(dc + float2( 0.0, -1.0)).rgb;
    float3 bD = base.sample(dc + float2( 0.0,  1.0)).rgb;

    const float3 lW = float3(0.299, 0.587, 0.114);

    float sDetail =
    fabs(dot(sL - s, lW)) +
    fabs(dot(sR - s, lW)) +
    fabs(dot(sU - s, lW)) +
    fabs(dot(sD - s, lW));

    float bDetail =
    fabs(dot(bL - b, lW)) +
    fabs(dot(bR - b, lW)) +
    fabs(dot(bU - b, lW)) +
    fabs(dot(bD - b, lW));

    // If AI has significantly *less* detail than baseline, we want stronger guard
    float detailRatio = (bDetail + 1e-3) / (sDetail + 1e-3); // >1 means baseline has more HF
    float detailGuard = clamp(detailRatio - 1.0, 0.0, 1.0); // 0..1

    // Base guard factor from overall color difference
    float guard = smoothstep(threshold, threshold * 2.0, max_diff);

    // Combine: only strong guard where AI both differs a lot and has less HF detail
    float t = guard * detailGuard * amount;
    float3 out_rgb = mix(s, b, t);

    return float4(out_rgb, s4.a);
}
