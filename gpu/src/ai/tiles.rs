//! Whole images through the network in tiles. Each tile carries `overlap` extra pixels on every side; the network
//! sees them but only the centre of its output is kept, so with an overlap of at least the model radius the result
//! does not depend on where the tile borders fall. At the image borders the tile content is the image mirrored
//! across its edge pixel row or column (reflect padding).

use super::model::{Model, Rgb};
use super::run::TileRunner;
use crate::context::Gpu;

/// Sustained speed assumed by [`AiScaler::estimate_seconds`], in floating point operations per second: the rate
/// measured for this kernel on a mid-range desktop GPU.
const ASSUMED_FLOPS: f64 = 0.7e12;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TileOptions {
    /// Side of a tile in input pixels, overlap included.
    pub tile: usize,
    /// Extra input pixels on each side of a tile that are computed but not kept.
    pub overlap: usize,
}

impl TileOptions {
    /// 256 pixel tiles with the receptive-field radius of the model as overlap.
    pub fn for_model(model: &Model) -> TileOptions {
        TileOptions { tile: 256, overlap: model.radius() }
    }
}

pub struct AiScaler {
    runner: TileRunner,
    options: TileOptions,
    /// Multiply-adds per input pixel of one pass through all layers.
    macs_per_pixel: usize,
}

/// Index of `i` after mirroring into `0..n` without repeating the edge pixel; `i` may lie any distance outside.
fn reflect(i: isize, n: usize) -> usize {
    if n == 1 {
        return 0;
    }
    let period = 2 * (n as isize - 1);
    let m = i.rem_euclid(period);
    (if m >= n as isize { period - m } else { m }) as usize
}

impl AiScaler {
    /// Uploads the model. Fails when the tile has no centre left after removing the overlap, or when the weights do
    /// not fit the device.
    pub fn new(gpu: &Gpu, model: &Model, options: TileOptions) -> Result<AiScaler, String> {
        if options.tile <= 2 * options.overlap {
            return Err(format!("tile {} is too small for an overlap of {}", options.tile, options.overlap));
        }
        let runner = TileRunner::new(gpu, model).ok_or("the model does not fit the graphics device")?;
        let macs_per_pixel = model.layers().iter().map(|l| l.cin * l.cout * 9).sum();
        Ok(AiScaler { runner, options, macs_per_pixel })
    }

    pub fn options(&self) -> TileOptions {
        self.options
    }

    /// Rough time to enlarge an image of `w` x `h` pixels, for showing before a run.
    pub fn estimate_seconds(&self, w: usize, h: usize) -> f64 {
        let core = self.options.tile - 2 * self.options.overlap;
        let side = self.options.tile as f64;
        let tiles = (w.div_ceil(core) * h.div_ceil(core)) as f64;
        tiles * 2.0 * self.macs_per_pixel as f64 * side * side / ASSUMED_FLOPS
    }

    /// The enlarged image, `scale` times the size of `img`. `None` when the buffers of a tile do not fit the device
    /// or a readback fails.
    pub fn upscale(&self, gpu: &Gpu, img: &Rgb) -> Option<Rgb> {
        let s = self.runner.scale();
        let (w, h) = (img.w, img.h);
        let overlap = self.options.overlap;
        let core = self.options.tile - 2 * overlap;
        let (ow, oh) = (w.checked_mul(s)?, h.checked_mul(s)?);
        ow.checked_mul(oh)?.checked_mul(3 * 4)?;
        let mut out = Rgb::new(ow, oh, 0.0);
        for y0 in (0..h).step_by(core) {
            for x0 in (0..w).step_by(core) {
                let (cw, ch) = (core.min(w - x0), core.min(h - y0));
                let (tw, th) = (cw + 2 * overlap, ch + 2 * overlap);
                let mut tile = Rgb::new(tw, th, 0.0);
                for (plane, src) in tile.planes.iter_mut().zip(&img.planes) {
                    for ty in 0..th {
                        let sy = reflect(y0 as isize + ty as isize - overlap as isize, h);
                        for tx in 0..tw {
                            let sx = reflect(x0 as isize + tx as isize - overlap as isize, w);
                            plane[ty * tw + tx] = src[sy * w + sx];
                        }
                    }
                }
                let result = self.runner.run(gpu, &tile)?;
                for (dst, src) in out.planes.iter_mut().zip(&result.planes) {
                    for row in 0..ch * s {
                        let from = (overlap * s + row) * result.w + overlap * s;
                        let to = (y0 * s + row) * ow + x0 * s;
                        dst[to..to + cw * s].copy_from_slice(&src[from..from + cw * s]);
                    }
                }
            }
        }
        Some(out)
    }
}

#[cfg(test)]
mod tests {
    use super::reflect;

    #[test]
    fn reflect_mirrors_without_repeating_the_edge() {
        let got: Vec<usize> = (-4..9).map(|i| reflect(i, 4)).collect();
        assert_eq!(got, [2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1, 2]);
        assert_eq!(reflect(-5, 1), 0);
        assert_eq!(reflect(7, 2), 1);
    }
}
