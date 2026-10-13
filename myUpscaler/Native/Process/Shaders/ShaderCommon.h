#ifndef MYUPSCALER_SHADER_COMMON_H
#define MYUPSCALER_SHADER_COMMON_H

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

// Internal linkage keeps helpers local to each independently compiled CI kernel.
static constant float PI = 3.14159265358979323846;

static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float3 srgbToLinear(float3 c) {
    float3 low = c / 12.92;
    float3 high = fast::powr((c + 0.055) / 1.055, float3(2.4));
    return mix(low, high, step(0.04045, c));
}

static inline float3 linearToSrgb(float3 c) {
    float3 low = c * 12.92;
    float3 high = 1.055 * fast::powr(c, float3(1.0 / 2.4)) - 0.055;
    return mix(low, high, step(0.0031308, c));
}

static inline float4 clamp01(float4 c) {
    return float4(clamp(c.rgb, 0.0, 1.0), clamp(c.a, 0.0, 1.0));
}

#endif // MYUPSCALER_SHADER_COMMON_H
