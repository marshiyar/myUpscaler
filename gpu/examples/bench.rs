//! Times the CPU and GPU stages on a 1920x1080 plane: `cargo run --release --example bench`.

use std::time::Instant;
use up60p::accel::Accelerator;
use up60p::filters::scale::resize;
use up60p::frame::Plane;
use up60p_gpu::GpuAccelerator;

fn main() {
    let mut src = Plane::new(1920, 1080, 0.0);
    for (i, v) in src.data.iter_mut().enumerate() {
        *v = ((i * 7919) % 251) as f32;
    }
    let gpu = match GpuAccelerator::new(true) {
        Ok(g) => g,
        Err(e) => {
            println!("no GPU: {e}");
            return;
        }
    };
    println!("adapter: {}", gpu.name());
    let time = |label: &str, f: &dyn Fn() -> Plane| {
        f();
        let start = Instant::now();
        let runs = 5;
        let mut last = None;
        for _ in 0..runs {
            last = Some(f());
        }
        println!("{label:<28} {:>8.1} ms", start.elapsed().as_secs_f64() * 1000.0 / runs as f64);
        last.unwrap()
    };
    let cpu = time("lanczos x2 CPU", &|| resize(&src, 3840, 2160));
    let fast = time("lanczos x2 GPU", &|| gpu.resize(&src, 3840, 2160).unwrap());
    let d = cpu.data.iter().zip(&fast.data).map(|(a, b)| (a - b).abs()).fold(0.0f32, f32::max);
    println!("max difference {d}");
}
