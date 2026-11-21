// Hard-threshold BM3D (basic estimate) with the same grid, search window, group size, threshold and Kaiser
// aggregation as the CPU stage. One invocation handles one reference block: it matches blocks, transforms the
// group, thresholds it and adds the result into `acc` (numerator in the first half, denominator in the second).
// Floating point additions go through compare-and-swap, so their order differs from the CPU's.

struct Params {
    w: u32,
    h: u32,
    nx: u32,
    ny: u32,
    row_start: u32,
    row_count: u32,
    sigma: f32,
    pad: u32,
}

const N: u32 = 8u;
const AREA: u32 = 64u;
const STEP: u32 = 4u;
const SEARCH: i32 = 10;
const SEARCH_STRIDE: i32 = 2;
const MAX_GROUP: u32 = 8u;
const LAMBDA: f32 = 2.7;

@group(0) @binding(0) var<uniform> params: Params;
// dct[k * 8 + n], then the Kaiser window at 64 + y * 8 + x.
@group(0) @binding(1) var<storage, read> tables: array<f32>;
@group(0) @binding(2) var<storage, read> src: array<f32>;
@group(0) @binding(3) var<storage, read_write> acc: array<atomic<u32>>;
@group(0) @binding(4) var<storage, read_write> out: array<f32>;

fn add(index: u32, v: f32) {
    var old = atomicLoad(&acc[index]);
    loop {
        let next = bitcast<u32>(bitcast<f32>(old) + v);
        let r = atomicCompareExchangeWeak(&acc[index], old, next);
        if (r.exchanged) {
            break;
        }
        old = r.old_value;
    }
}

fn grid(i: u32, len: u32) -> u32 {
    return min(i * STEP, len - N);
}

// 2D DCT of the 64 values at group[base..], in place; `inverse` uses the transposed basis.
fn dct2(group: ptr<function, array<f32, 512>>, base: u32, inverse: bool) {
    var tmp: array<f32, 64>;
    for (var y = 0u; y < N; y = y + 1u) {
        for (var k = 0u; k < N; k = k + 1u) {
            var s = 0.0;
            for (var n = 0u; n < N; n = n + 1u) {
                var m = tables[k * N + n];
                if (inverse) {
                    m = tables[n * N + k];
                }
                s = s + (*group)[base + y * N + n] * m;
            }
            tmp[y * N + k] = s;
        }
    }
    for (var k = 0u; k < N; k = k + 1u) {
        for (var x = 0u; x < N; x = x + 1u) {
            var s = 0.0;
            for (var n = 0u; n < N; n = n + 1u) {
                var m = tables[k * N + n];
                if (inverse) {
                    m = tables[n * N + k];
                }
                s = s + m * tmp[n * N + x];
            }
            (*group)[base + k * N + x] = s;
        }
    }
}

fn walsh_hadamard(group: ptr<function, array<f32, 512>>, n: u32) {
    if (n < 2u) {
        return;
    }
    var len = 1u;
    loop {
        if (len >= n) {
            break;
        }
        for (var start = 0u; start < n; start = start + len * 2u) {
            for (var k = start; k < start + len; k = k + 1u) {
                for (var i = 0u; i < AREA; i = i + 1u) {
                    let a = (*group)[k * AREA + i];
                    let b = (*group)[(k + len) * AREA + i];
                    (*group)[k * AREA + i] = a + b;
                    (*group)[(k + len) * AREA + i] = a - b;
                }
            }
        }
        len = len * 2u;
    }
    let scale = 1.0 / sqrt(f32(n));
    for (var i = 0u; i < n * AREA; i = i + 1u) {
        (*group)[i] = (*group)[i] * scale;
    }
}

@compute @workgroup_size(8, 8)
fn denoise(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= params.nx || id.y >= params.row_count) {
        return;
    }
    let w = params.w;
    let h = params.h;
    let rx = grid(id.x, w);
    let ry = grid(params.row_start + id.y, h);
    let sigma = params.sigma;
    let threshold = LAMBDA * sigma;
    let ssd_limit = (2.0 * sigma * sigma + 400.0) * f32(AREA);

    var reference: array<f32, 64>;
    for (var j = 0u; j < N; j = j + 1u) {
        for (var i = 0u; i < N; i = i + 1u) {
            reference[j * N + i] = src[(ry + j) * w + rx + i];
        }
    }

    // The closest MAX_GROUP - 1 candidates, best first, ties kept in scan order.
    var best_ssd: array<f32, 7>;
    var best_pos: array<u32, 7>;
    var count = 0u;
    let y_lo = max(i32(ry) - SEARCH, 0);
    let y_hi = min(i32(ry) + SEARCH, i32(h - N));
    let x_lo = max(i32(rx) - SEARCH, 0);
    let x_hi = min(i32(rx) + SEARCH, i32(w - N));
    for (var cy = y_lo; cy <= y_hi; cy = cy + SEARCH_STRIDE) {
        for (var cx = x_lo; cx <= x_hi; cx = cx + SEARCH_STRIDE) {
            if (u32(cx) == rx && u32(cy) == ry) {
                continue;
            }
            var ssd = 0.0;
            for (var j = 0u; j < N; j = j + 1u) {
                let row = (u32(cy) + j) * w + u32(cx);
                for (var i = 0u; i < N; i = i + 1u) {
                    let d = reference[j * N + i] - src[row + i];
                    ssd = ssd + d * d;
                }
                if (j % 2u == 1u && ssd > ssd_limit) {
                    break;
                }
            }
            if (ssd > ssd_limit) {
                continue;
            }
            // Insert into the sorted list, dropping the worst when it is full.
            if (count == 7u && ssd >= best_ssd[6]) {
                continue;
            }
            var at = min(count, 6u);
            loop {
                if (at == 0u || best_ssd[at - 1u] <= ssd) {
                    break;
                }
                best_ssd[at] = best_ssd[at - 1u];
                best_pos[at] = best_pos[at - 1u];
                at = at - 1u;
            }
            best_ssd[at] = ssd;
            best_pos[at] = u32(cy) * w + u32(cx);
            count = min(count + 1u, 7u);
        }
    }
    // Candidates beyond what the best list holds do not change the group size, which tops out at MAX_GROUP.
    var size = 1u;
    loop {
        if (size * 2u > min(count + 1u, MAX_GROUP)) {
            break;
        }
        size = size * 2u;
    }

    var group: array<f32, 512>;
    var pos: array<u32, 8>;
    pos[0] = ry * w + rx;
    for (var g = 1u; g < size; g = g + 1u) {
        pos[g] = best_pos[g - 1u];
    }
    for (var g = 0u; g < size; g = g + 1u) {
        for (var i = 0u; i < AREA; i = i + 1u) {
            group[g * AREA + i] = src[pos[g] + (i / N) * w + i % N];
        }
        dct2(&group, g * AREA, false);
    }
    walsh_hadamard(&group, size);
    var kept = 0u;
    for (var i = 0u; i < size * AREA; i = i + 1u) {
        if (abs(group[i]) < threshold) {
            group[i] = 0.0;
        } else {
            kept = kept + 1u;
        }
    }
    walsh_hadamard(&group, size);
    let weight = 1.0 / f32(max(kept, 1u));
    let plane = w * h;
    for (var g = 0u; g < size; g = g + 1u) {
        dct2(&group, g * AREA, true);
        for (var i = 0u; i < AREA; i = i + 1u) {
            let k = tables[64u + i] * weight;
            let at = pos[g] + (i / N) * w + i % N;
            add(at, k * group[g * AREA + i]);
            add(plane + at, k);
        }
    }
}

// acc -> out: numerator / denominator where the denominator is positive, the input sample elsewhere.
@compute @workgroup_size(256)
fn finish(@builtin(global_invocation_id) id: vec3<u32>) {
    let plane = params.w * params.h;
    if (id.x >= plane) {
        return;
    }
    let den = bitcast<f32>(atomicLoad(&acc[plane + id.x]));
    if (den > 0.0) {
        out[id.x] = bitcast<f32>(atomicLoad(&acc[id.x])) / den;
    } else {
        out[id.x] = src[id.x];
    }
}
