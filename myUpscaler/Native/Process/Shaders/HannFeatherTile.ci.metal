#include "ShaderCommon.h"

// Hann cosine feathering for a tile
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
