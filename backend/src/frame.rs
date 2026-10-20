//! Frames as three full-resolution float planes (Y'CbCr 4:4:4, BT.709, full range, 0..255 scale with chroma
//! centred on 128) plus optional alpha. Filter parameters keep their usual 8-bit meaning on this scale while the
//! arithmetic keeps full precision until the single rounding when the frame goes back to RGBA8.

use crate::par;

#[derive(Clone, Debug, PartialEq)]
pub struct Plane {
    pub w: usize,
    pub h: usize,
    pub data: Vec<f32>,
}

impl Plane {
    pub fn new(w: usize, h: usize, fill: f32) -> Plane {
        Plane { w, h, data: vec![fill; w * h] }
    }

    #[inline]
    pub fn at(&self, x: usize, y: usize) -> f32 {
        self.data[y * self.w + x]
    }

    /// The sample at (x, y) with coordinates clamped to the plane (edge pixels repeat).
    #[inline]
    pub fn clamped(&self, x: isize, y: isize) -> f32 {
        let x = x.clamp(0, self.w as isize - 1) as usize;
        let y = y.clamp(0, self.h as isize - 1) as usize;
        self.data[y * self.w + x]
    }

    /// Bilinear sample at a fractional position, clamped to the plane.
    #[inline]
    pub fn bilinear(&self, x: f32, y: f32) -> f32 {
        let x = x.clamp(0.0, (self.w - 1) as f32);
        let y = y.clamp(0.0, (self.h - 1) as f32);
        let (x0, y0) = (x as usize, y as usize);
        let (x1, y1) = ((x0 + 1).min(self.w - 1), (y0 + 1).min(self.h - 1));
        let (fx, fy) = (x - x0 as f32, y - y0 as f32);
        let top = self.at(x0, y0) + (self.at(x1, y0) - self.at(x0, y0)) * fx;
        let bottom = self.at(x0, y1) + (self.at(x1, y1) - self.at(x0, y1)) * fx;
        top + (bottom - top) * fy
    }

    pub fn row(&self, y: usize) -> &[f32] {
        &self.data[y * self.w..(y + 1) * self.w]
    }
}

#[derive(Clone, Debug)]
pub struct Frame {
    /// Y', Cb, Cr.
    pub planes: [Plane; 3],
    /// 0..255; kept only for stills that have transparency.
    pub alpha: Option<Plane>,
    /// Presentation time in seconds.
    pub pts: f64,
}

// BT.709 luma weights (ITU-R BT.709-6, item 3.2).
const KR: f32 = 0.2126;
const KB: f32 = 0.0722;
const KG: f32 = 1.0 - KR - KB;
const CB_SCALE: f32 = 2.0 * (1.0 - KB);
const CR_SCALE: f32 = 2.0 * (1.0 - KR);

impl Frame {
    pub fn width(&self) -> usize {
        self.planes[0].w
    }

    pub fn height(&self) -> usize {
        self.planes[0].h
    }

    /// Converts straight RGBA8 to a frame; alpha is kept when `keep_alpha` and any pixel is not opaque.
    pub fn from_rgba(rgba: &[u8], w: usize, h: usize, pts: f64, keep_alpha: bool) -> Frame {
        let mut y = Plane::new(w, h, 0.0);
        let mut cb = Plane::new(w, h, 0.0);
        let mut cr = Plane::new(w, h, 0.0);
        for (i, px) in rgba.chunks_exact(4).take(w * h).enumerate() {
            let (r, g, b) = (px[0] as f32, px[1] as f32, px[2] as f32);
            let luma = KR * r + KG * g + KB * b;
            y.data[i] = luma;
            cb.data[i] = (b - luma) / CB_SCALE + 128.0;
            cr.data[i] = (r - luma) / CR_SCALE + 128.0;
        }
        let alpha = (keep_alpha && rgba.chunks_exact(4).any(|p| p[3] != 255)).then(|| Plane {
            w,
            h,
            data: rgba.chunks_exact(4).take(w * h).map(|p| p[3] as f32).collect(),
        });
        Frame { planes: [y, cb, cr], alpha, pts }
    }

    /// Converts back to RGBA8 with a triangular dither of one code value, so gradients smoothed by the filters do
    /// not band again when rounded to 8 bits. `seed` varies the dither between frames.
    pub fn to_rgba(&self, seed: u32) -> Vec<u8> {
        let (w, h) = (self.width(), self.height());
        let mut out = vec![0u8; w * h * 4];
        let [y, cb, cr] = &self.planes;
        let alpha = self.alpha.as_ref();
        let rows: Vec<Vec<u8>> = par::map(h, |row| {
            let mut line = vec![0u8; w * 4];
            for x in 0..w {
                let i = row * w + x;
                let luma = y.data[i];
                let (u, v) = (cb.data[i] - 128.0, cr.data[i] - 128.0);
                let r = luma + CR_SCALE * v;
                let b = luma + CB_SCALE * u;
                let g = (luma - KR * r - KB * b) / KG;
                let d = tpdf(x as u32, row as u32, seed);
                line[x * 4] = quantize(r + d);
                line[x * 4 + 1] = quantize(g + d);
                line[x * 4 + 2] = quantize(b + d);
                line[x * 4 + 3] = alpha.map_or(255, |a| quantize(a.data[i]));
            }
            line
        });
        for (row, line) in rows.into_iter().enumerate() {
            out[row * w * 4..(row + 1) * w * 4].copy_from_slice(&line);
        }
        out
    }
}

#[inline]
fn quantize(v: f32) -> u8 {
    (v + 0.5).clamp(0.0, 255.0) as u8
}

/// A well-mixed 32-bit hash of three values (used for dither, grain and deband sampling).
#[inline]
pub fn hash3(a: u32, b: u32, c: u32) -> u32 {
    let mut h = a.wrapping_mul(0x9E37_79B1) ^ b.wrapping_mul(0x85EB_CA77) ^ c.wrapping_mul(0xC2B2_AE3D);
    h ^= h >> 15;
    h = h.wrapping_mul(0x2C1B_3C6D);
    h ^= h >> 12;
    h = h.wrapping_mul(0x297A_2D39);
    h ^ (h >> 15)
}

/// Uniform value in [0, 1) from a hash.
#[inline]
pub fn unit(h: u32) -> f32 {
    (h >> 8) as f32 / (1u32 << 24) as f32
}

/// Triangular-PDF dither in (-1, 1) code values.
#[inline]
fn tpdf(x: u32, y: u32, seed: u32) -> f32 {
    let h = hash3(x, y, seed);
    unit(h) + unit(hash3(h, seed, 0x51ED_270B)) - 1.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rgba_round_trip_is_within_dither() {
        let (w, h) = (16, 9);
        let mut rgba = Vec::new();
        for i in 0..w * h {
            rgba.extend_from_slice(&[(i * 7 % 256) as u8, (i * 13 % 256) as u8, (i * 29 % 256) as u8, 255]);
        }
        let f = Frame::from_rgba(&rgba, w, h, 0.0, true);
        assert!(f.alpha.is_none(), "opaque input drops alpha");
        let back = f.to_rgba(1);
        for (a, b) in rgba.iter().zip(&back) {
            assert!((*a as i32 - *b as i32).abs() <= 1, "{a} vs {b}");
        }
    }

    #[test]
    fn grey_has_neutral_chroma() {
        let f = Frame::from_rgba(&[100, 100, 100, 255], 1, 1, 0.0, false);
        assert!((f.planes[0].data[0] - 100.0).abs() < 1e-3);
        assert!((f.planes[1].data[0] - 128.0).abs() < 1e-3);
        assert!((f.planes[2].data[0] - 128.0).abs() < 1e-3);
    }

    #[test]
    fn transparency_is_kept() {
        let f = Frame::from_rgba(&[10, 20, 30, 40, 1, 2, 3, 255], 2, 1, 0.0, true);
        assert_eq!(f.alpha.as_ref().map(|a| a.data.clone()), Some(vec![40.0, 255.0]));
        assert_eq!(f.to_rgba(0)[3], 40);
    }
}
