// Separable Lanczos resampling with the tap tables computed on the CPU (the same ones the CPU path uses), so the
// two paths differ only by the order of the floating point sums.

struct Dims {
    src_w: u32,
    src_h: u32,
    dst_w: u32,
    dst_h: u32,
}

@group(0) @binding(0) var<uniform> dims: Dims;
// Per output position: first source index, tap count, offset into `weights`.
@group(0) @binding(1) var<storage, read> taps: array<vec4<u32>>;
@group(0) @binding(2) var<storage, read> weights: array<f32>;
@group(0) @binding(3) var<storage, read> input: array<f32>;
@group(0) @binding(4) var<storage, read_write> output: array<f32>;

// Horizontal pass: input is src_w x src_h, output dst_w x src_h.
@compute @workgroup_size(16, 16)
fn horizontal(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= dims.dst_w || id.y >= dims.src_h) {
        return;
    }
    let t = taps[id.x];
    var acc = 0.0;
    for (var k = 0u; k < t.y; k = k + 1u) {
        acc = acc + weights[t.z + k] * input[id.y * dims.src_w + t.x + k];
    }
    output[id.y * dims.dst_w + id.x] = acc;
}

// Vertical pass: input is dst_w x src_h, output dst_w x dst_h.
@compute @workgroup_size(16, 16)
fn vertical(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= dims.dst_w || id.y >= dims.dst_h) {
        return;
    }
    let t = taps[id.y];
    var acc = 0.0;
    for (var k = 0u; k < t.y; k = k + 1u) {
        acc = acc + weights[t.z + k] * input[(t.x + k) * dims.dst_w + id.x];
    }
    output[id.y * dims.dst_w + id.x] = acc;
}
