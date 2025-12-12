/*
 Shaders.ci.metal
 myUpscaler

 Core Image Metal Kernels for High-Fidelity Video Restoration.
 These kernels clone the behavior of industry-standard FFmpeg filters:
 - cas_sharpen: Clones AMD Contrast Adaptive Sharpening (cas)
 - deband_dither: Clones f3kdb/deband behavior
 - bilateral_denoise: Clones hqdn3d/nlmeans behavior (lightweight)
 - drift_guard: GPU DriftGuard blending AI and baseline

 Designed for Apple Silicon (M-series) GPUs.
 */

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

// MARK: - Helper Functions

static constant float PI = 3.14159265358979323846;

/// High-quality pseudo-random noise generator
/// Hashes the pixel coordinate to produce deterministic monochromatic noise
float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// Convert sRGB to linear light
float3 srgbToLinear(float3 c) {
    float3 low = c / 12.92;
    float3 high = pow((c + 0.055) / 1.055, float3(2.4));
    return mix(low, high, step(0.04045, c));
}

/// Convert linear light to sRGB
float3 linearToSrgb(float3 c) {
    float3 low = c * 12.92;
    float3 high = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
    return mix(low, high, step(0.0031308, c));
}

/// Clamp helper to keep colors in-gamut after transforms
float4 clamp01(float4 c) {
    return float4(clamp(c.rgb, 0.0, 1.0), clamp(c.a, 0.0, 1.0));
}

// MARK: - Color Management Kernels (sRGB <-> linear, tone, gamma)

/// Linearize sRGB and optionally apply exposure gain
extern "C" float4 linearize_srgb(coreimage::sampler src, float exposure) {
    float4 s = src.sample(src.coord());
    float3 lin = srgbToLinear(s.rgb) * exposure;
    return clamp01(float4(lin, s.a));
}

/// Encode linear back to sRGB
extern "C" float4 encode_srgb(coreimage::sampler src, float exposure) {
    float4 s = src.sample(src.coord());
    float3 encoded = linearToSrgb(s.rgb * exposure);
    return clamp01(float4(encoded, s.a));
}

/// Simple Reinhard tone map in linear domain
extern "C" float4 tone_map_reinhard(coreimage::sampler src, float exposure) {
    float4 s = src.sample(src.coord());
    float3 lin = srgbToLinear(s.rgb) * exposure;
    float3 mapped = lin / (1.0 + lin);
    return clamp01(float4(mapped, s.a));
}

/// Gamma-correct blend between two images (linear domain)
extern "C" float4 gamma_correct_blend(coreimage::sampler a,
                                     coreimage::sampler b,
                                     float mixFactor) {
    float2 dc = a.coord();
    float4 sa = a.sample(dc);
    float4 sb = b.sample(dc);
    float3 la = srgbToLinear(sa.rgb);
    float3 lb = srgbToLinear(sb.rgb);
    float3 blended = mix(la, lb, clamp(mixFactor, 0.0, 1.0));
    return clamp01(float4(linearToSrgb(blended), mix(sa.a, sb.a, mixFactor)));
}

// MARK: - CAS Sharpening (Contrast Adaptive Sharpening)
// Replicates the logic of the AMD CAS algorithm.
// Input: src (image), sharpness (0.0 - 1.0)
extern "C" float4 cas_sharpen(coreimage::sampler src, float sharpness) {
    float2 dc = src.coord();
    
    // 3x3 neighborhood
    float4 e = src.sample(dc);
    float4 a = src.sample(dc + float2(-1.0, -1.0));
    float4 b = src.sample(dc + float2( 0.0, -1.0));
    float4 c = src.sample(dc + float2( 1.0, -1.0));
    float4 d = src.sample(dc + float2(-1.0,  0.0));
    float4 f = src.sample(dc + float2( 1.0,  0.0));
    float4 g = src.sample(dc + float2(-1.0,  1.0));
    float4 h = src.sample(dc + float2( 0.0,  1.0));
    float4 i = src.sample(dc + float2( 1.0,  1.0));
    
    // Soft min/max (RGB only)
    float3 min_rgb = min(min(min(d.rgb, e.rgb), min(f.rgb, b.rgb)), h.rgb);
    float3 max_rgb = max(max(max(d.rgb, e.rgb), max(f.rgb, b.rgb)), h.rgb);
    float3 min_rgb2 = min(min(min(a.rgb, c.rgb), min(g.rgb, i.rgb)), min_rgb);
    float3 max_rgb2 = max(max(max(a.rgb, c.rgb), max(g.rgb, i.rgb)), max_rgb);
    min_rgb += min_rgb2;
    max_rgb += max_rgb2;
    
    // Low-pass / high-pass
    float4 cross_sum = b + d + f + h;
    float4 low_pass = cross_sum * 0.25;
    float4 high_pass = e - low_pass;
    
    // Adaptive weighting to limit halos
    float3 local_contrast = max_rgb - min_rgb;
    float3 adapt = clamp(1.0 - (local_contrast * 2.0), 0.0, 1.0);
    float s = clamp(sharpness, 0.0, 1.0);
    float3 out_rgb = e.rgb + high_pass.rgb * s * adapt * 4.0;
    
    return float4(clamp(out_rgb, 0.0, 1.0), e.a);
}

// MARK: - Debanding (Noise-free gradients)
// Replicates f3kdb / deband behavior but removes static dithering noise.
// Input: src, threshold (0.001 - 0.1), amount (blend strength toward local avg)
extern "C" float4 deband_dither(coreimage::sampler src, float threshold, float amount) {
    float2 dc = src.coord();
    float4 center = src.sample(dc);
    
    float4 s1 = src.sample(dc + float2(-2.0, -2.0));
    float4 s2 = src.sample(dc + float2( 2.0, -2.0));
    float4 s3 = src.sample(dc + float2(-2.0,  2.0));
    float4 s4 = src.sample(dc + float2( 2.0,  2.0));
    
    float3 avg = (s1.rgb + s2.rgb + s3.rgb + s4.rgb) * 0.25;
    float3 diff = abs(center.rgb - avg);
    float max_diff = max(max(diff.r, diff.g), diff.b);
    
    float factor = 1.0 - smoothstep(0.0, threshold, max_diff);
    if (factor <= 0.0) { return center; }
    
    // Instead of adding random dithering (visible as static noise), smoothly blend
    // toward the local average in flat regions.
    float blend = clamp(amount * factor, 0.0, 1.0);
    float3 out_rgb = mix(center.rgb, avg, blend);
    return float4(out_rgb, center.a);
}

// MARK: - Bilateral Denoise (Lightweight NLMeans)
// Preserves edges while smoothing flat areas.
// Input: src, sigma_spatial (radius), sigma_range (color sensitivity)
extern "C" float4 bilateral_denoise(coreimage::sampler src, float sigma_spatial, float sigma_range) {
    float2 dc = src.coord();
    float4 center = src.sample(dc);
    
    float3 sum = float3(0.0);
    float weight_sum = 0.0;
    
    float two_sigma_spatial2 = 2.0 * sigma_spatial * sigma_spatial;
    float two_sigma_range2 = 2.0 * sigma_range * sigma_range;
    int radius = 2; // 5x5 kernel
    
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            float2 offset = float2(float(x), float(y));
            float4 sample = src.sample(dc + offset);
            
            float dist2 = dot(offset, offset);
            float w_spatial = exp(-dist2 / two_sigma_spatial2);
            
            float3 color_diff = center.rgb - sample.rgb;
            float color_dist2 = dot(color_diff, color_diff);
            float w_range = exp(-color_dist2 / two_sigma_range2);
            
            float w = w_spatial * w_range;
            sum += sample.rgb * w;
            weight_sum += w;
        }
    }
    
    float3 result = sum / max(weight_sum, 0.0001);
    return float4(result, center.a);
}

// MARK: - Drift Guard (Color Stabilization)
// Blends AI output with baseline when differences exceed threshold.
// Input: ai (image), base (image), threshold, amount (blend strength)
extern "C" float4 drift_guard(coreimage::sampler ai, coreimage::sampler base, float threshold, float amount) {
    float4 s = ai.sample(ai.coord());
    float4 b = base.sample(base.coord());
    
    float3 diff = abs(s.rgb - b.rgb);
    float max_diff = max(max(diff.r, diff.g), diff.b);
    
    float factor = smoothstep(threshold, threshold * 2.0, max_diff);
    float3 out_rgb = mix(s.rgb, b.rgb, factor * amount);
    return float4(out_rgb, s.a);
}

// MARK: - Edge-Aware Sharpening (Unsharp / Laplacian-guided)

/// Simple box blur helper for small radius (1-2)
float3 boxBlur(coreimage::sampler src, float2 dc, int radius) {
    float3 sum = float3(0.0);
    float weight = 0.0;
    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            float3 sample = src.sample(dc + float2(x, y)).rgb;
            sum += sample;
            weight += 1.0;
        }
    }
    return sum / max(weight, 1.0);
}

/// Unsharp mask with edge thresholding to limit halos
extern "C" float4 unsharp_mask(coreimage::sampler src, float radius, float amount, float threshold) {
    float2 dc = src.coord();
    int r = clamp(int(radius + 0.5), 1, 2); // small radius for perf
    float4 c = src.sample(dc);
    float3 blur = boxBlur(src, dc, r);
    float3 high = c.rgb - blur;
    float3 edgeMask = smoothstep(threshold, threshold * 1.6, abs(high));
    float3 sharpened = c.rgb + high * amount * edgeMask;
    return clamp01(float4(sharpened, c.a));
}

/// Edge-preserving sharpen using Laplacian estimate
extern "C" float4 laplacian_sharpen(coreimage::sampler src, float strength) {
    float2 dc = src.coord();
    float3 center = src.sample(dc).rgb;
    float3 left = src.sample(dc + float2(-1.0, 0.0)).rgb;
    float3 right = src.sample(dc + float2(1.0, 0.0)).rgb;
    float3 up = src.sample(dc + float2(0.0, -1.0)).rgb;
    float3 down = src.sample(dc + float2(0.0, 1.0)).rgb;
    float3 lap = (left + right + up + down) * 0.25 - center;
    float3 enhanced = center - lap * strength;
    return clamp01(float4(enhanced, src.sample(dc).a));
}

// MARK: - Denoise / Deband Extras

/// Median-like denoise using trimmed mean (3x3)
extern "C" float4 median_denoise(coreimage::sampler src) {
    float2 dc = src.coord();
    float3 samples[9];
    int idx = 0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            samples[idx++] = src.sample(dc + float2(x, y)).rgb;
        }
    }
    // Simple sort by luminance
    for (int i = 0; i < 9; ++i) {
        for (int j = i + 1; j < 9; ++j) {
            float li = dot(samples[i], float3(0.299, 0.587, 0.114));
            float lj = dot(samples[j], float3(0.299, 0.587, 0.114));
            if (lj < li) {
                float3 tmp = samples[i];
                samples[i] = samples[j];
                samples[j] = tmp;
            }
        }
    }
    float3 median = samples[4];
    float4 c = src.sample(dc);
    return float4(median, c.a);
}

/// Deband without static blue-noise; gently blend toward neighborhood average.
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

// MARK: - Artifact Suppression (Dehalo / Moiré)

extern "C" float4 dehalo(coreimage::sampler src, float strength) {
    float2 dc = src.coord();
    float4 c = src.sample(dc);
    
    float3 ring = (src.sample(dc + float2(-1.0, 0.0)).rgb +
                   src.sample(dc + float2(1.0, 0.0)).rgb +
                   src.sample(dc + float2(0.0, -1.0)).rgb +
                   src.sample(dc + float2(0.0, 1.0)).rgb) * 0.25;
    
    float3 low = min(min(ring, c.rgb), min(src.sample(dc + float2(-1.0, -1.0)).rgb,
                                           src.sample(dc + float2(1.0, 1.0)).rgb));
    float3 high = max(max(ring, c.rgb), max(src.sample(dc + float2(-1.0, -1.0)).rgb,
                                           src.sample(dc + float2(1.0, 1.0)).rgb));
    float3 halo = clamp(c.rgb - ring, 0.0, 1.0);
    float3 suppressed = mix(c.rgb, clamp(c.rgb - halo, low, high), strength);
    return float4(suppressed, c.a);
}

extern "C" float4 moire_suppress(coreimage::sampler src, float strength) {
    float2 dc = src.coord();
    float3 center = src.sample(dc).rgb;
    float3 diag = (src.sample(dc + float2(1.0, 1.0)).rgb +
                   src.sample(dc + float2(-1.0, -1.0)).rgb +
                   src.sample(dc + float2(-1.0, 1.0)).rgb +
                   src.sample(dc + float2(1.0, -1.0)).rgb) * 0.25;
    float3 cross = (src.sample(dc + float2(1.0, 0.0)).rgb +
                    src.sample(dc + float2(-1.0, 0.0)).rgb +
                    src.sample(dc + float2(0.0, 1.0)).rgb +
                    src.sample(dc + float2(0.0, -1.0)).rgb) * 0.25;
    float3 smooth = mix(cross, diag, 0.5);
    float3 cleaned = mix(center, smooth, strength);
    return float4(cleaned, src.sample(dc).a);
}

// MARK: - Alpha Utilities

extern "C" float4 premultiply_alpha(coreimage::sampler src) {
    float4 c = src.sample(src.coord());
    return float4(c.rgb * c.a, c.a);
}

extern "C" float4 unpremultiply_alpha(coreimage::sampler src) {
    float4 c = src.sample(src.coord());
    float safeA = max(c.a, 0.0001);
    return float4(c.rgb / safeA, c.a);
}

// MARK: - Mask Helpers (Feather / Dilate / Erode)

extern "C" float4 mask_feather(coreimage::sampler src, float radius) {
    float2 dc = src.coord();
    int r = clamp(int(radius + 0.5), 0, 3);
    float sum = 0.0;
    float weight = 0.0;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            float dist2 = float(x * x + y * y);
            float w = exp(-dist2 / max(1.0, radius * radius));
            sum += src.sample(dc + float2(x, y)).r * w;
            weight += w;
        }
    }
    float v = weight > 0 ? sum / weight : src.sample(dc).r;
    return float4(v, v, v, 1.0);
}

extern "C" float4 mask_dilate(coreimage::sampler src, float radius) {
    float2 dc = src.coord();
    int r = clamp(int(radius + 0.5), 0, 3);
    float maxV = 0.0;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            maxV = max(maxV, src.sample(dc + float2(x, y)).r);
        }
    }
    return float4(maxV, maxV, maxV, 1.0);
}

extern "C" float4 mask_erode(coreimage::sampler src, float radius) {
    float2 dc = src.coord();
    int r = clamp(int(radius + 0.5), 0, 3);
    float minV = 1.0;
    for (int y = -r; y <= r; ++y) {
        for (int x = -r; x <= r; ++x) {
            minV = min(minV, src.sample(dc + float2(x, y)).r);
        }
    }
    return float4(minV, minV, minV, 1.0);
}

// MARK: - Tiled Processing Helpers (Hann/Cosine Feather)

extern "C" float4 hann_feather_tile(coreimage::sampler src, float tileWidth, float tileHeight, float margin) {
    float2 dc = src.coord();
    float4 c = src.sample(dc);
    float wx = 1.0;
    float wy = 1.0;
    float m = max(margin, 1.0);
    if (dc.x < margin) {
        float t = clamp(dc.x / m, 0.0, 1.0);
        wx *= 0.5 * (1.0 - cos(t * PI));
    } else if (dc.x > tileWidth - margin) {
        float t = clamp((tileWidth - dc.x) / m, 0.0, 1.0);
        wx *= 0.5 * (1.0 - cos(t * PI));
    }
    if (dc.y < margin) {
        float t = clamp(dc.y / m, 0.0, 1.0);
        wy *= 0.5 * (1.0 - cos(t * PI));
    } else if (dc.y > tileHeight - margin) {
        float t = clamp((tileHeight - dc.y) / m, 0.0, 1.0);
        wy *= 0.5 * (1.0 - cos(t * PI));
    }
    float w = wx * wy;
    return float4(c.rgb * w, c.a);
}

// MARK: - Temporal Smoothing (Video)

extern "C" float4 temporal_smooth(coreimage::sampler current,
                                  coreimage::sampler previous,
                                  float strength) {
    float2 dc = current.coord();
    float4 c = current.sample(dc);
    float4 p = previous.sample(dc);
    float3 lc = srgbToLinear(c.rgb);
    float3 lp = srgbToLinear(p.rgb);
    float s = clamp(strength, 0.0, 1.0);
    float3 blended = mix(lc, lp, s);
    return clamp01(float4(linearToSrgb(blended), mix(c.a, p.a, s)));
}
