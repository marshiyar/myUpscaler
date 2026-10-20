//! Contrast, brightness and saturation: contrast scales luma around mid-grey, brightness offsets it (a fraction of
//! the full range), saturation scales the chroma planes around neutral.

use super::Spatial;
use crate::frame::Frame;

pub struct Eq {
    pub contrast: f32,
    pub brightness: f32,
    pub saturation: f32,
}

impl Eq {
    pub fn new(contrast: f64, brightness: f64, saturation: f64) -> Eq {
        Eq {
            contrast: contrast.clamp(-1000.0, 1000.0) as f32,
            brightness: (brightness.clamp(-1.0, 1.0) * 255.0) as f32,
            saturation: saturation.clamp(0.0, 3.0) as f32,
        }
    }

    pub fn is_identity(&self) -> bool {
        self.contrast == 1.0 && self.brightness == 0.0 && self.saturation == 1.0
    }
}

impl Spatial for Eq {
    fn describe(&self) -> String {
        format!(
            "eq(contrast={:.3}, brightness={:.3}, saturation={:.3})",
            self.contrast,
            self.brightness / 255.0,
            self.saturation
        )
    }

    fn apply(&mut self, frame: &mut Frame) {
        for v in frame.planes[0].data.iter_mut() {
            *v = (*v - 128.0) * self.contrast + 128.0 + self.brightness;
        }
        for plane in &mut frame.planes[1..] {
            for v in plane.data.iter_mut() {
                *v = (*v - 128.0) * self.saturation + 128.0;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::testutil::clean;

    #[test]
    fn applies_contrast_brightness_saturation() {
        let mut f = clean(4, 4);
        f.planes[0].data[0] = 138.0;
        f.planes[1].data[0] = 138.0;
        Eq::new(2.0, 0.1, 0.5).apply(&mut f);
        assert!((f.planes[0].data[0] - (148.0 + 25.5)).abs() < 1e-3);
        assert!((f.planes[1].data[0] - 133.0).abs() < 1e-3);
        assert!(Eq::new(1.0, 0.0, 1.0).is_identity());
    }
}
