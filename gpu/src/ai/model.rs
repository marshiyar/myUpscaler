//! The network description, its two file formats and the CPU forward pass.
//!
//! SRVGGNetCompact is a chain of 3x3 convolutions. Every convolution but the last is followed by a PReLU. The last
//! one produces `3 * scale * scale` channels, which are rearranged into the enlarged image (pixel shuffle) and added
//! to the nearest-neighbour enlargement of the input.

/// An RGB image with every plane on the 0..255 scale, like `up60p::frame::Plane`.
#[derive(Clone, Debug, PartialEq)]
pub struct Rgb {
    pub w: usize,
    pub h: usize,
    pub planes: [Vec<f32>; 3],
}

impl Rgb {
    pub fn new(w: usize, h: usize, value: f32) -> Rgb {
        Rgb { w, h, planes: [vec![value; w * h], vec![value; w * h], vec![value; w * h]] }
    }
}

/// One 3x3 convolution. `weights` is laid out `[cout][cin][3][3]`.
#[derive(Clone, Debug, PartialEq)]
pub struct Layer {
    pub cin: usize,
    pub cout: usize,
    pub weights: Vec<f32>,
    pub bias: Vec<f32>,
    /// PReLU slopes, one per output channel; `None` for the final convolution.
    pub slopes: Option<Vec<f32>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Model {
    layers: Vec<Layer>,
    scale: usize,
}

const MAX_CHANNELS: usize = 4096;
const MAGIC: &[u8; 8] = b"UP60MDL\0";
const VERSION: u32 = 1;
const NCNN_MAGIC: &str = "7767517";
const NCNN_TAG_F16: u32 = 0x0130_6B47;
const NCNN_TAG_F32: u32 = 0;

impl Model {
    /// Checks that the layers form a valid chain and builds the model.
    pub fn new(layers: Vec<Layer>, scale: usize) -> Result<Model, String> {
        if !(2..=4).contains(&scale) {
            return Err(format!("unsupported scale {scale}"));
        }
        if layers.len() < 2 {
            return Err("a model needs at least two convolutions".into());
        }
        let mut cin = 3;
        for (i, l) in layers.iter().enumerate() {
            let last = i + 1 == layers.len();
            if l.cin != cin || l.cout == 0 || l.cout > MAX_CHANNELS {
                return Err(format!("layer {i}: bad channel count {} -> {}", l.cin, l.cout));
            }
            if l.weights.len() != l.cout * l.cin * 9 || l.bias.len() != l.cout {
                return Err(format!("layer {i}: wrong number of weights"));
            }
            match (&l.slopes, last) {
                (Some(s), false) if s.len() == l.cout => {}
                (None, true) => {}
                _ => return Err(format!("layer {i}: wrong activation")),
            }
            cin = l.cout;
        }
        if cin != 3 * scale * scale {
            return Err(format!("the last layer has {cin} channels, expected {}", 3 * scale * scale));
        }
        Ok(Model { layers, scale })
    }

    pub fn layers(&self) -> &[Layer] {
        &self.layers
    }

    pub fn scale(&self) -> usize {
        self.scale
    }

    /// Receptive-field radius in input pixels: every 3x3 convolution reaches one pixel further.
    pub fn radius(&self) -> usize {
        self.layers.len()
    }

    /// Reads an ncnn `.param` / `.bin` pair of a SRVGGNetCompact (fp16 or fp32 weights).
    pub fn from_ncnn(param: &str, bin: &[u8]) -> Result<Model, String> {
        let mut lines = param.lines().map(str::trim).filter(|l| !l.is_empty());
        if lines.next() != Some(NCNN_MAGIC) {
            return Err("not an ncnn param file".into());
        }
        lines.next().ok_or("ncnn param file is cut short")?;
        let mut pos = 0usize;
        let mut layers: Vec<Layer> = Vec::new();
        let mut scale = None;
        // A convolution waits here until the next layer shows whether a PReLU follows it.
        let mut pending: Option<Layer> = None;
        for line in lines {
            let f: Vec<&str> = line.split_whitespace().collect();
            let attr =
                |key: &str| f.iter().skip(1).find_map(|t| t.strip_prefix(key)).and_then(|v| v.parse::<usize>().ok());
            match f[0] {
                "Convolution" => {
                    if pending.is_some() || scale.is_some() {
                        return Err("a convolution without its PReLU".into());
                    }
                    if attr("1=") != Some(3) || attr("5=") != Some(1) {
                        return Err("only 3x3 convolutions with bias are supported".into());
                    }
                    let cout = attr("0=").ok_or("convolution without an output size")?;
                    let count = attr("6=").ok_or("convolution without a weight count")?;
                    let cin = layers.last().map_or(3, |l: &Layer| l.cout);
                    if cout == 0 || cout > MAX_CHANNELS || count != cout * cin * 9 {
                        return Err(format!("convolution {}: bad sizes", layers.len()));
                    }
                    let weights = read_weights(bin, &mut pos, count)?;
                    let bias = read_f32(bin, &mut pos, cout)?;
                    pending = Some(Layer { cin, cout, weights, bias, slopes: None });
                }
                "PReLU" => {
                    let mut layer = pending.take().ok_or("a PReLU without a convolution")?;
                    if attr("0=") != Some(layer.cout) {
                        return Err("PReLU size differs from the convolution".into());
                    }
                    layer.slopes = Some(read_f32(bin, &mut pos, layer.cout)?);
                    layers.push(layer);
                }
                "PixelShuffle" => {
                    if scale.is_some() {
                        return Err("more than one PixelShuffle".into());
                    }
                    scale = Some(attr("0=").ok_or("PixelShuffle without a factor")?);
                    layers.extend(pending.take());
                }
                _ => {}
            }
        }
        layers.extend(pending.take());
        if pos != bin.len() {
            return Err(format!("{} unexpected bytes after the last weight", bin.len() - pos));
        }
        Model::new(layers, scale.ok_or("no PixelShuffle layer")?)
    }

    /// Reads the compact container written by [`Model::to_bytes`].
    pub fn from_bytes(bytes: &[u8]) -> Result<Model, String> {
        if bytes.len() < MAGIC.len() + 12 + 8 || &bytes[..8] != MAGIC {
            return Err("not a model file".into());
        }
        let (body, sum) = bytes.split_at(bytes.len() - 8);
        if fnv1a(body) != u64::from_le_bytes(sum.try_into().map_err(|_| "bad checksum")?) {
            return Err("the model file is damaged (checksum mismatch)".into());
        }
        let mut pos = 8usize;
        let version = take_u32(body, &mut pos)?;
        if version != VERSION {
            return Err(format!("unsupported model file version {version}"));
        }
        let scale = take_u32(body, &mut pos)? as usize;
        let count = take_u32(body, &mut pos)? as usize;
        if count > 1024 {
            return Err("too many layers".into());
        }
        let mut table = Vec::with_capacity(count);
        for _ in 0..count {
            let cin = take_u32(body, &mut pos)? as usize;
            let cout = take_u32(body, &mut pos)? as usize;
            let flags = take_u32(body, &mut pos)?;
            if cin == 0 || cout == 0 || cin > MAX_CHANNELS || cout > MAX_CHANNELS || flags > 1 {
                return Err("bad layer table".into());
            }
            table.push((cin, cout, flags == 1));
        }
        let mut layers = Vec::with_capacity(count);
        for (cin, cout, prelu) in table {
            let n = cout * cin * 9;
            let raw = body.get(pos..pos + n * 2).ok_or("model file is cut short")?;
            let weights = raw.chunks_exact(2).map(|c| f16_to_f32(u16::from_le_bytes([c[0], c[1]]))).collect();
            pos += n * 2;
            let bias = read_f32(body, &mut pos, cout)?;
            let slopes = if prelu { Some(read_f32(body, &mut pos, cout)?) } else { None };
            layers.push(Layer { cin, cout, weights, bias, slopes });
        }
        if pos != body.len() {
            return Err(format!("{} unexpected bytes after the last layer", body.len() - pos));
        }
        Model::new(layers, scale)
    }

    /// Writes the compact container: header, layer table, fp16 weights, fp32 bias and slopes, FNV-1a checksum.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(MAGIC);
        for v in [VERSION, self.scale as u32, self.layers.len() as u32] {
            out.extend_from_slice(&v.to_le_bytes());
        }
        for l in &self.layers {
            for v in [l.cin as u32, l.cout as u32, l.slopes.is_some() as u32] {
                out.extend_from_slice(&v.to_le_bytes());
            }
        }
        for l in &self.layers {
            for w in &l.weights {
                out.extend_from_slice(&f32_to_f16(*w).to_le_bytes());
            }
            for v in l.bias.iter().chain(l.slopes.iter().flatten()) {
                out.extend_from_slice(&v.to_le_bytes());
            }
        }
        let sum = fnv1a(&out);
        out.extend_from_slice(&sum.to_le_bytes());
        out
    }
}

fn fnv1a(data: &[u8]) -> u64 {
    data.iter().fold(0xcbf2_9ce4_8422_2325, |h, b| (h ^ *b as u64).wrapping_mul(0x0000_0100_0000_01b3))
}

fn take_u32(data: &[u8], pos: &mut usize) -> Result<u32, String> {
    let b = data.get(*pos..*pos + 4).ok_or("the file is cut short")?;
    *pos += 4;
    Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
}

fn read_f32(data: &[u8], pos: &mut usize, n: usize) -> Result<Vec<f32>, String> {
    let end = n.checked_mul(4).and_then(|b| pos.checked_add(b)).ok_or("size overflow")?;
    let raw = data.get(*pos..end).ok_or("the file is cut short")?;
    *pos = end;
    Ok(raw.chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect())
}

/// One ncnn weight block: a 4-byte tag, then fp16 (padded to 4 bytes) or fp32 values.
fn read_weights(bin: &[u8], pos: &mut usize, n: usize) -> Result<Vec<f32>, String> {
    match take_u32(bin, pos)? {
        NCNN_TAG_F32 => read_f32(bin, pos, n),
        NCNN_TAG_F16 => {
            let bytes = n.checked_mul(2).ok_or("size overflow")?;
            let end = pos.checked_add(bytes).ok_or("size overflow")?;
            let raw = bin.get(*pos..end).ok_or("the file is cut short")?;
            *pos = end + (4 - bytes % 4) % 4;
            if *pos > bin.len() {
                return Err("the file is cut short".into());
            }
            Ok(raw.chunks_exact(2).map(|c| f16_to_f32(u16::from_le_bytes([c[0], c[1]]))).collect())
        }
        t => Err(format!("unsupported weight format tag {t:#x}")),
    }
}

pub(crate) fn f16_to_f32(h: u16) -> f32 {
    let sign = if h >> 15 == 1 { -1.0 } else { 1.0 };
    let exp = ((h >> 10) & 31) as i32;
    let man = (h & 1023) as f32;
    sign * match exp {
        0 => man * 2f32.powi(-24),
        31 if man == 0.0 => f32::INFINITY,
        31 => f32::NAN,
        _ => (1.0 + man / 1024.0) * 2f32.powi(exp - 15),
    }
}

/// Rounds to the nearest half-precision value (ties to even); out-of-range values become infinity.
pub(crate) fn f32_to_f16(v: f32) -> u16 {
    let bits = v.to_bits();
    let sign = ((bits >> 16) & 0x8000) as u16;
    let exp = ((bits >> 23) & 0xff) as i32;
    let man = bits & 0x7f_ffff;
    if exp == 0xff {
        return sign | 0x7c00 | if man != 0 { 0x200 } else { 0 };
    }
    let e = exp - 127 + 15;
    if e >= 31 {
        return sign | 0x7c00;
    }
    if e <= 0 {
        if e < -10 {
            return sign;
        }
        let m = man | 0x80_0000;
        let shift = (14 - e) as u32;
        let half = m >> shift;
        let rem = m & ((1 << shift) - 1);
        let mid = 1 << (shift - 1);
        let up = rem > mid || (rem == mid && half & 1 == 1);
        return sign | (half + up as u32) as u16;
    }
    let half = ((e as u32) << 10) | (man >> 13);
    let rem = man & 0x1fff;
    let up = rem > 0x1000 || (rem == 0x1000 && half & 1 == 1);
    sign | (half + up as u32) as u16
}

/// The network on the CPU, used as the reference for the GPU. Input and output are on the 0..255 scale; the
/// arithmetic runs on 0..1. Convolutions pad with zeros like the real network.
pub fn cpu_forward(model: &Model, tile: &Rgb) -> Rgb {
    let (w, h) = (tile.w, tile.h);
    let plane = w * h;
    let mut cur: Vec<f32> = tile.planes.iter().flat_map(|p| p.iter().map(|v| v / 255.0)).collect();
    let input = cur.clone();
    for l in &model.layers {
        let mut next = vec![0f32; l.cout * plane];
        for co in 0..l.cout {
            let out = &mut next[co * plane..(co + 1) * plane];
            out.fill(l.bias[co]);
            for ci in 0..l.cin {
                let src = &cur[ci * plane..(ci + 1) * plane];
                for dy in 0..3usize {
                    for dx in 0..3usize {
                        let wt = l.weights[(co * l.cin + ci) * 9 + dy * 3 + dx];
                        for y in 0..h {
                            // Source row y + dy - 1, source column x + dx - 1; outside the tile counts as zero.
                            if y + dy < 1 || y + dy > h {
                                continue;
                            }
                            let row = &src[(y + dy - 1) * w..(y + dy) * w];
                            let dst = &mut out[y * w..(y + 1) * w];
                            for (x, d) in dst.iter_mut().enumerate() {
                                if x + dx >= 1 && x + dx <= w {
                                    *d += wt * row[x + dx - 1];
                                }
                            }
                        }
                    }
                }
            }
            if let Some(slopes) = &l.slopes {
                for v in out.iter_mut() {
                    if *v < 0.0 {
                        *v *= slopes[co];
                    }
                }
            }
        }
        cur = next;
    }
    let s = model.scale;
    let (ow, oh) = (w * s, h * s);
    let mut out = Rgb::new(ow, oh, 0.0);
    for c in 0..3 {
        for y in 0..oh {
            for x in 0..ow {
                let fc = c * s * s + (y % s) * s + x % s;
                let at = (y / s) * w + x / s;
                out.planes[c][y * ow + x] = (cur[fc * plane + at] + input[c * plane + at]) * 255.0;
            }
        }
    }
    out
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    struct Rng(u64);
    impl Rng {
        fn next(&mut self) -> f32 {
            self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            ((self.0 >> 40) as f32 / 16777216.0) * 2.0 - 1.0
        }
        /// A value that half precision stores exactly.
        fn half(&mut self, scale: f32) -> f32 {
            f16_to_f32(f32_to_f16(self.next() * scale))
        }
    }

    /// `convs` convolutions, `channels` wide except the last, which has `3 * scale * scale` outputs.
    pub(crate) fn random_model(channels: usize, convs: usize, scale: usize, seed: u64) -> Model {
        let mut rng = Rng(seed);
        let mut layers = Vec::new();
        let mut cin = 3;
        for i in 0..convs {
            let last = i + 1 == convs;
            let cout = if last { 3 * scale * scale } else { channels };
            let k = (2.0 / (cin * 9) as f32).sqrt();
            layers.push(Layer {
                cin,
                cout,
                weights: (0..cout * cin * 9).map(|_| rng.half(k)).collect(),
                bias: (0..cout).map(|_| rng.next() * 0.05).collect(),
                slopes: if last { None } else { Some((0..cout).map(|_| 0.1 + 0.1 * rng.next()).collect()) },
            });
            cin = cout;
        }
        Model::new(layers, scale).unwrap()
    }

    pub(crate) fn random_image(w: usize, h: usize, seed: u64) -> Rgb {
        let mut rng = Rng(seed);
        let mut img = Rgb::new(w, h, 0.0);
        for p in img.planes.iter_mut() {
            for v in p.iter_mut() {
                *v = (rng.next() * 0.5 + 0.5) * 255.0;
            }
        }
        img
    }

    fn ncnn_bytes(m: &Model, fp16: bool) -> (String, Vec<u8>) {
        let mut param = String::from("7767517\n0 0\nInput input 0 1 data\n");
        let mut bin = Vec::new();
        for l in m.layers() {
            param += &format!("Convolution conv 1 1 a b 0={} 1=3 5=1 6={}\n", l.cout, l.weights.len());
            if fp16 {
                bin.extend_from_slice(&NCNN_TAG_F16.to_le_bytes());
                l.weights.iter().for_each(|w| bin.extend_from_slice(&f32_to_f16(*w).to_le_bytes()));
                if l.weights.len() % 2 == 1 {
                    bin.extend_from_slice(&[0, 0]);
                }
            } else {
                bin.extend_from_slice(&NCNN_TAG_F32.to_le_bytes());
                l.weights.iter().for_each(|w| bin.extend_from_slice(&w.to_le_bytes()));
            }
            l.bias.iter().for_each(|b| bin.extend_from_slice(&b.to_le_bytes()));
            if let Some(s) = &l.slopes {
                param += &format!("PReLU act 1 1 b c 0={}\n", l.cout);
                s.iter().for_each(|v| bin.extend_from_slice(&v.to_le_bytes()));
            }
        }
        param += &format!("PixelShuffle shuffle 1 1 x y 0={}\n", m.scale());
        param += "Interp up 1 1 data z 0=1 1=2 2=2\nBinaryOp add 2 1 y z out 0=0\n";
        (param, bin)
    }

    #[test]
    fn half_conversion_round_trips() {
        for h in 0..=0xffffu16 {
            let v = f16_to_f32(h);
            if v.is_nan() {
                assert!(f16_to_f32(f32_to_f16(v)).is_nan());
            } else {
                assert_eq!(f32_to_f16(v), h, "{h:#06x}");
            }
        }
        assert_eq!(f32_to_f16(1.0 + 1.0 / 2048.0), 0x3c00, "ties go to even");
        assert_eq!(f32_to_f16(1e9), 0x7c00);
    }

    #[test]
    fn ncnn_and_container_agree() {
        let model = random_model(5, 2, 2, 42);
        assert_eq!((model.radius(), model.scale()), (2, 2));
        let tile = random_image(13, 9, 7);
        let want = cpu_forward(&model, &tile);
        assert_eq!((want.w, want.h), (26, 18));
        for fp16 in [true, false] {
            let (param, bin) = ncnn_bytes(&model, fp16);
            let loaded = Model::from_ncnn(&param, &bin).unwrap();
            assert_eq!(loaded, model);
            assert_eq!(cpu_forward(&loaded, &tile), want);
        }
        let bytes = model.to_bytes();
        let loaded = Model::from_bytes(&bytes).unwrap();
        assert_eq!(loaded, model);
        assert_eq!(cpu_forward(&loaded, &tile), want);
        assert_eq!(loaded.to_bytes(), bytes);
    }

    #[test]
    fn bad_inputs_are_errors() {
        let model = random_model(4, 2, 2, 1);
        let (param, bin) = ncnn_bytes(&model, true);
        for n in [0, 3, 10, bin.len() / 2, bin.len() - 1] {
            assert!(Model::from_ncnn(&param, &bin[..n]).is_err(), "truncated bin {n}");
        }
        let mut long = bin.clone();
        long.push(0);
        assert!(Model::from_ncnn(&param, &long).unwrap_err().contains("unexpected bytes"));
        let mut tagged = bin.clone();
        tagged[..4].copy_from_slice(&0x1234_5678u32.to_le_bytes());
        assert!(Model::from_ncnn(&param, &tagged).unwrap_err().contains("tag"));
        assert!(Model::from_ncnn("hello", &bin).is_err());
        assert!(Model::from_ncnn(&param[..param.len() / 2], &bin).is_err());
        assert!(Model::from_ncnn(&param.replace("0=4 ", "0=3 "), &bin).is_err());
        assert!(Model::from_ncnn("", &[]).is_err());

        let bytes = model.to_bytes();
        for n in [0, 5, 8, 20, bytes.len() / 2, bytes.len() - 1] {
            assert!(Model::from_bytes(&bytes[..n]).is_err(), "truncated container {n}");
        }
        let mut grown = bytes.clone();
        grown.push(0);
        assert!(Model::from_bytes(&grown).is_err());
        for at in [0, 9, 17, 30, bytes.len() / 2, bytes.len() - 1] {
            let mut bad = bytes.clone();
            bad[at] ^= 0x55;
            assert!(Model::from_bytes(&bad).is_err(), "flipped byte {at}");
        }
    }

    #[test]
    fn hand_computed_model() {
        // The body convolution copies each colour channel (centre tap 1; positive inputs pass the PReLU unchanged).
        // The output convolution sends the copy of channel c to the first phase of every 2x2 block of channel c and
        // leaves the other phases at zero, so those phases only carry the nearest-neighbour input.
        let mut first = vec![0.0; 3 * 3 * 9];
        for c in 0..3 {
            first[(c * 3 + c) * 9 + 4] = 1.0;
        }
        let mut last = vec![0.0; 12 * 3 * 9];
        for c in 0..3 {
            last[((c * 4) * 3 + c) * 9 + 4] = 1.0;
        }
        let model = Model::new(
            vec![
                Layer { cin: 3, cout: 3, weights: first, bias: vec![0.0; 3], slopes: Some(vec![0.25; 3]) },
                Layer { cin: 3, cout: 12, weights: last, bias: vec![0.0; 12], slopes: None },
            ],
            2,
        )
        .unwrap();
        let mut tile = Rgb::new(2, 2, 0.0);
        tile.planes[0] = vec![51.0, 102.0, 153.0, 204.0];
        tile.planes[1] = vec![255.0; 4];
        let out = cpu_forward(&model, &tile);
        assert_eq!((out.w, out.h), (4, 4));
        for y in 0..4 {
            for x in 0..4 {
                let v = tile.planes[0][(y / 2) * 2 + x / 2];
                let want = if x % 2 == 0 && y % 2 == 0 { 2.0 * v } else { v };
                assert!((out.planes[0][y * 4 + x] - want).abs() < 1e-3, "({x},{y})");
            }
        }
        assert!((out.planes[1][0] - 510.0).abs() < 1e-3 && (out.planes[1][1] - 255.0).abs() < 1e-3);
        assert!(out.planes[2].iter().all(|v| v.abs() < 1e-3));
    }

    #[test]
    fn invalid_models_are_rejected() {
        let model = random_model(4, 2, 2, 3);
        let mut layers = model.layers().to_vec();
        assert!(Model::new(layers.clone(), 5).is_err());
        layers[1].cout = 11;
        assert!(Model::new(layers, 2).is_err());
        assert!(Model::new(vec![], 2).is_err());
    }
}
