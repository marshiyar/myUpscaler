//! Real-ESRGAN style super resolution (the SRVGGNetCompact network): the model container, its loaders and a CPU
//! reference of the forward pass.

mod model;
mod run;
mod tiles;

pub use model::{cpu_forward, Layer, Model, Rgb};
pub use run::{run_tile, TileRunner};
pub use tiles::{AiScaler, TileOptions};
