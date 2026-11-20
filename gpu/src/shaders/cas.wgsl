// Contrast-adaptive sharpening of one luma plane, one thread per pixel, with the same arithmetic and the same
// clamped 3x3 neighbourhood as the CPU stage. Samples are normalised from 0..255 to 0..1 and scaled back.

struct Params {
    w: u32,
    h: u32,
    // -1 / (8 + (5 - 8) * strength)
    peak: f32,
    pad: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> input: array<f32>;
@group(0) @binding(2) var<storage, read_write> output: array<f32>;

fn load(x: u32, y: u32) -> f32 {
    return clamp(input[y * params.w + x] / 255.0, 0.0, 1.0);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= params.w || id.y >= params.h) {
        return;
    }
    let l = max(id.x, 1u) - 1u;
    let r = min(id.x + 1u, params.w - 1u);
    let u = max(id.y, 1u) - 1u;
    let d = min(id.y + 1u, params.h - 1u);
    let a = load(l, u);
    let b = load(id.x, u);
    let c = load(r, u);
    let dd = load(l, id.y);
    let e = load(id.x, id.y);
    let f = load(r, id.y);
    let g = load(l, d);
    let hh = load(id.x, d);
    let i = load(r, d);
    let mn_cross = min(min(min(b, dd), min(e, f)), hh);
    let mn = mn_cross + min(min(mn_cross, a), min(min(c, g), i));
    let mx_cross = max(max(max(b, dd), max(e, f)), hh);
    let mx = mx_cross + max(max(mx_cross, a), max(max(c, g), i));
    var amp = 0.0;
    if (mx > 0.0) {
        amp = sqrt(clamp(min(mn, 2.0 - mx) / mx, 0.0, 1.0));
    }
    let wgt = amp * params.peak;
    let v = ((b + dd + f + hh) * wgt + e) / (1.0 + 4.0 * wgt);
    output[id.y * params.w + id.x] = v * 255.0;
}
