// Layer parameters. Weights, biases and PReLU slopes of all layers share one buffer; the offsets count floats.
struct Params {
    cin: u32,
    cout: u32,
    w: u32,
    h: u32,
    w_off: u32,
    b_off: u32,
    a_off: u32,
    prelu: u32,
    scale: u32,
    pad0: u32,
    pad1: u32,
    pad2: u32,
}

@group(0) @binding(0) var<uniform> p: Params;
@group(0) @binding(1) var<storage, read> weights: array<f32>;
@group(0) @binding(2) var<storage, read> inp: array<f32>;
@group(0) @binding(3) var<storage, read_write> outp: array<f32>;
@group(0) @binding(4) var<storage, read> orig: array<f32>;

// 3x3 convolution with zero padding, optionally followed by PReLU. Planar layout: channel, row, column.
// One invocation computes one pixel for a block of 8 output channels.
@compute @workgroup_size(8, 8, 1)
fn conv(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= p.w || id.y >= p.h) { return; }
    let co0 = id.z * 8u;
    var acc: array<f32, 8>;
    for (var j = 0u; j < 8u; j++) {
        if (co0 + j < p.cout) { acc[j] = weights[p.b_off + co0 + j]; }
    }
    let plane = p.w * p.h;
    for (var ci = 0u; ci < p.cin; ci++) {
        for (var dy = 0u; dy < 3u; dy++) {
            let yy = i32(id.y) + i32(dy) - 1;
            if (yy < 0 || yy >= i32(p.h)) { continue; }
            for (var dx = 0u; dx < 3u; dx++) {
                let xx = i32(id.x) + i32(dx) - 1;
                if (xx < 0 || xx >= i32(p.w)) { continue; }
                let v = inp[ci * plane + u32(yy) * p.w + u32(xx)];
                let k = dy * 3u + dx;
                for (var j = 0u; j < 8u; j++) {
                    if (co0 + j < p.cout) {
                        acc[j] += v * weights[p.w_off + ((co0 + j) * p.cin + ci) * 9u + k];
                    }
                }
            }
        }
    }
    for (var j = 0u; j < 8u; j++) {
        if (co0 + j < p.cout) {
            var a = acc[j];
            if (p.prelu != 0u && a < 0.0) { a = a * weights[p.a_off + co0 + j]; }
            outp[(co0 + j) * plane + id.y * p.w + id.x] = a;
        }
    }
}

// Pixel shuffle of the 3 * scale^2 channel map plus the nearest-neighbour enlargement of the input image.
// `p.w` and `p.h` are the input size; the output is `scale` times larger.
@compute @workgroup_size(8, 8, 1)
fn shuffle(@builtin(global_invocation_id) id: vec3<u32>) {
    let s = p.scale;
    let ow = p.w * s;
    let oh = p.h * s;
    if (id.x >= ow || id.y >= oh) { return; }
    let c = id.z;
    let sx = id.x / s;
    let sy = id.y / s;
    let fc = c * s * s + (id.y % s) * s + (id.x % s);
    let plane = p.w * p.h;
    outp[c * ow * oh + id.y * ow + id.x] = inp[fc * plane + sy * p.w + sx] + orig[c * plane + sy * p.w + sx];
}
