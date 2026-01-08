#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

// MARK: - Helper Functions

static constant float PI = 3.14159265358979323846;

static constant int  kBilatRadius = 2;
static constant int  kBilatKernelSize = (kBilatRadius * 2 + 1) * (kBilatRadius * 2 + 1);

static constant float2 kBilatOffsets[kBilatKernelSize] = {
    float2(-2.0, -2.0), float2(-1.0, -2.0), float2(0.0, -2.0), float2(1.0, -2.0), float2(2.0, -2.0),
    float2(-2.0, -1.0), float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0), float2(2.0, -1.0),
    float2(-2.0,  0.0), float2(-1.0,  0.0), float2(0.0,  0.0), float2(1.0,  0.0), float2(2.0,  0.0),
    float2(-2.0,  1.0), float2(-1.0,  1.0), float2(0.0,  1.0), float2(1.0,  1.0), float2(2.0,  1.0),
    float2(-2.0,  2.0), float2(-1.0,  2.0), float2(0.0,  2.0), float2(1.0,  2.0), float2(2.0,  2.0),
};

static constant float kBilatDist2[kBilatKernelSize] = {
    8.0, 5.0, 4.0, 5.0, 8.0,
    5.0, 2.0, 1.0, 2.0, 5.0,
    4.0, 1.0, 0.0, 1.0, 4.0,
    5.0, 2.0, 1.0, 2.0, 5.0,
    8.0, 5.0, 4.0, 5.0, 8.0,
};


float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// Convert sRGB to linear light
float3 srgbToLinear(float3 c) {
    float3 low = c / 12.92;
    float3 high = fast::powr((c + 0.055) / 1.055, float3(2.4));
    return mix(low, high, step(0.04045, c));
}

/// Convert linear light to sRGB
float3 linearToSrgb(float3 c) {
    float3 low = c * 12.92;
    float3 high = 1.055 * fast::powr(c, float3(1.0 / 2.4)) - 0.055;
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


// MARK: - Bilateral Denoise (Lightweight NLMeans)
// Preserves edges while smoothing flat areas.
// Input: src, sigma_spatial (radius), sigma_range (color sensitivity)
extern "C" float4 bilateral_denoise(coreimage::sampler src,
                                    float sigma_spatial,
                                    float sigma_range) {
    float2 dc = src.coord();
    float4 c4 = src.sample(dc);
    float3 c  = c4.rgb;
    
    // If sigma_range is ~0, early-out – no reason to spend time
    if (sigma_range <= 0.0 || sigma_spatial <= 0.0) {
        return c4;
    }
    
    float invTwoSigmaSpatial2 = 1.0 / max(2.0 * sigma_spatial * sigma_spatial, 1e-4);
    float invTwoSigmaRange2   = 1.0 / max(2.0 * sigma_range   * sigma_range,   1e-4);
    
    float3 sum = float3(0.0);
    float  wsum = 0.0;
    
    // 5x5 kernel, precomputed offsets & dist²
    for (int i = 0; i < kBilatKernelSize; ++i) {
        float2 offset = kBilatOffsets[i];
        float4 s4 = src.sample(dc + offset);
        float3 s  = s4.rgb;
        
        float3 diff = c - s;
        float  colorDist2 = dot(diff, diff);
        float  dist2 = kBilatDist2[i];
        
        // Single exponent: spatial + range in one go
        float w = fast::exp(-dist2 * invTwoSigmaSpatial2
                            - colorDist2 * invTwoSigmaRange2);
        
        sum  += s * w;
        wsum += w;
    }
    
    float invW = (wsum > 0.0) ? (1.0 / wsum) : 1.0;
    float3 denoised = sum * invW;
    
    // Prevent over-smoothing: mix back some original based on sigma_range
    float mixOriginal = clamp(1.0 - sigma_range * 4.0, 0.0, 0.5);
    float3 out = mix(denoised, c, mixOriginal);
    
    return float4(out, c4.a);
}
// MARK: - Drift Guard (Color Stabilization)
// Blends AI output with baseline when differences exceed threshold.
// Input: ai (image), base (image), threshold, amount (blend strength)
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
    
    float3 low = min(min(ring, c.rgb),
                     min(src.sample(dc + float2(-1.0, -1.0)).rgb,
                         src.sample(dc + float2( 1.0,  1.0)).rgb));
    float3 high = max(max(ring, c.rgb),
                      max(src.sample(dc + float2(-1.0, -1.0)).rgb,
                          src.sample(dc + float2( 1.0,  1.0)).rgb));
    
    float3 halo = clamp(c.rgb - ring, 0.0, 1.0);
    float3 suppressed = mix(c.rgb, clamp(c.rgb - halo, low, high), strength);
    return float4(suppressed, c.a);
}

extern "C" float4 moire_suppress(coreimage::sampler src, float strength) {
    float2 dc = src.coord();
    float3 center = src.sample(dc).rgb;
    float3 diag = (src.sample(dc + float2( 1.0,  1.0)).rgb +
                   src.sample(dc + float2(-1.0, -1.0)).rgb +
                   src.sample(dc + float2(-1.0,  1.0)).rgb +
                   src.sample(dc + float2( 1.0, -1.0)).rgb) * 0.25;
    float3 cross = (src.sample(dc + float2( 1.0,  0.0)).rgb +
                    src.sample(dc + float2(-1.0,  0.0)).rgb +
                    src.sample(dc + float2( 0.0,  1.0)).rgb +
                    src.sample(dc + float2( 0.0, -1.0)).rgb) * 0.25;
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

// MARK: - Tiled Processing Helpers (Hann/fast::cosine Feather)

extern "C" float4 hann_feather_tile(coreimage::sampler src, float tileWidth, float tileHeight, float margin) {
    float2 dc = src.coord();
    float4 c = src.sample(dc);
    float wx = 1.0;
    float wy = 1.0;
    float m = max(margin, 1.0);
    if (dc.x < margin) {
        float t = clamp(dc.x / m, 0.0, 1.0);
        wx *= 0.5 * (1.0 - fast::cos(t * PI));
    } else if (dc.x > tileWidth - margin) {
        float t = clamp((tileWidth - dc.x) / m, 0.0, 1.0);
        wx *= 0.5 * (1.0 - fast::cos(t * PI));
    }
    if (dc.y < margin) {
        float t = clamp(dc.y / m, 0.0, 1.0);
        wy *= 0.5 * (1.0 - fast::cos(t * PI));
    } else if (dc.y > tileHeight - margin) {
        float t = clamp((tileHeight - dc.y) / m, 0.0, 1.0);
        wy *= 0.5 * (1.0 - fast::cos(t * PI));
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
