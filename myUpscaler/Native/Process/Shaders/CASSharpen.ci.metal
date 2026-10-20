#include "ShaderCommon.h"

// Contrast adaptive sharpening
extern "C" float4 cas_sharpen(coreimage::sampler src, float sharpness) {
    float2 dc = src.coord();

    float4 e = src.sample(dc);
    float4 a = src.sample(dc + float2(-1.0, -1.0));
    float4 b = src.sample(dc + float2( 0.0, -1.0));
    float4 c = src.sample(dc + float2( 1.0, -1.0));
    float4 d = src.sample(dc + float2(-1.0,  0.0));
    float4 f = src.sample(dc + float2( 1.0,  0.0));
    float4 g = src.sample(dc + float2(-1.0,  1.0));
    float4 h = src.sample(dc + float2( 0.0,  1.0));
    float4 i = src.sample(dc + float2( 1.0,  1.0));

    // Min/max over neighborhood (RGB)
    float3 min_rgb = min(min(min(d.rgb, e.rgb), min(f.rgb, b.rgb)), h.rgb);
    float3 max_rgb = max(max(max(d.rgb, e.rgb), max(f.rgb, b.rgb)), h.rgb);
    float3 min_rgb2 = min(min(min(a.rgb, c.rgb), min(g.rgb, i.rgb)), min_rgb);
    float3 max_rgb2 = max(max(max(a.rgb, c.rgb), max(g.rgb, i.rgb)), max_rgb);
    min_rgb += min_rgb2;
    max_rgb += max_rgb2;

    float4 cross_sum = b + d + f + h;
    float4 low_pass = cross_sum * 0.25;
    float4 high_pass = e - low_pass;

    // Use scalar contrast (luma) to drive adaptation
    const float3 lumaW = float3(0.299, 0.587, 0.114);
    float minL = dot(min_rgb * (1.0 / 2.0), lumaW);
    float maxL = dot(max_rgb * (1.0 / 2.0), lumaW);
    float localContrast = maxL - minL;

    // Softer rolloff: strong suppression only at very high contrast
    float adapt = 1.0 - smoothstep(0.15, 0.6, localContrast);

    float s = clamp(sharpness, 0.0, 1.0);
    float3 out_rgb = e.rgb + high_pass.rgb * (s * 4.0 * adapt);

    return float4(clamp(out_rgb, 0.0, 1.0), e.a);
}
