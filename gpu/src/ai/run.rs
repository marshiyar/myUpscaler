//! The network on the GPU: one compute pass per convolution, then the pixel shuffle with the nearest-neighbour
//! addition, all in one submission.

use super::model::{Model, Rgb};
use crate::context::Gpu;
use bytemuck::{Pod, Zeroable};

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
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
    pad: [u32; 3],
}

struct LayerInfo {
    cin: usize,
    cout: usize,
    w_off: usize,
    b_off: usize,
    a_off: usize,
    prelu: bool,
}

/// The pipelines and the weights of one model on the device.
pub struct TileRunner {
    conv: wgpu::ComputePipeline,
    shuffle: wgpu::ComputePipeline,
    layout: wgpu::BindGroupLayout,
    weights: wgpu::Buffer,
    layers: Vec<LayerInfo>,
    scale: usize,
}

fn entry(binding: u32, ty: wgpu::BufferBindingType) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::COMPUTE,
        ty: wgpu::BindingType::Buffer { ty, has_dynamic_offset: false, min_binding_size: None },
        count: None,
    }
}

impl TileRunner {
    /// `None` when the weights do not fit the device's buffers.
    pub fn new(gpu: &Gpu, model: &Model) -> Option<TileRunner> {
        let mut flat: Vec<f32> = Vec::new();
        let mut layers = Vec::new();
        for l in model.layers() {
            let w_off = flat.len();
            flat.extend_from_slice(&l.weights);
            let b_off = flat.len();
            flat.extend_from_slice(&l.bias);
            let a_off = flat.len();
            flat.extend(l.slopes.iter().flatten());
            layers.push(LayerInfo { cin: l.cin, cout: l.cout, w_off, b_off, a_off, prelu: l.slopes.is_some() });
        }
        if flat.len() > u32::MAX as usize || !gpu.fits(flat.len() as u64 * 4) {
            return None;
        }
        let module = gpu.device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("ai"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders/conv.wgsl").into()),
        });
        let ro = wgpu::BufferBindingType::Storage { read_only: true };
        let rw = wgpu::BufferBindingType::Storage { read_only: false };
        let layout = gpu.device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[
                entry(0, wgpu::BufferBindingType::Uniform),
                entry(1, ro),
                entry(2, ro),
                entry(3, rw),
                entry(4, ro),
            ],
        });
        let pipeline_layout = gpu.device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: None,
            bind_group_layouts: &[Some(&layout)],
            immediate_size: 0,
        });
        let make = |name: &str| {
            gpu.device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some(name),
                layout: Some(&pipeline_layout),
                module: &module,
                entry_point: Some(name),
                compilation_options: Default::default(),
                cache: None,
            })
        };
        Some(TileRunner {
            conv: make("conv"),
            shuffle: make("shuffle"),
            layout,
            weights: gpu.storage(bytemuck::cast_slice(&flat)),
            layers,
            scale: model.scale(),
        })
    }

    pub fn scale(&self) -> usize {
        self.scale
    }

    /// Bytes of the largest buffer a tile of `w` x `h` pixels needs.
    fn largest_buffer(&self, w: usize, h: usize) -> Option<u64> {
        let widest = self.layers.iter().map(|l| l.cout).max()?;
        widest.checked_mul(w)?.checked_mul(h)?.checked_mul(4).map(|bytes| bytes as u64)
    }

    /// Runs the network on one tile. `None` when the buffers do not fit or the readback fails.
    pub fn run(&self, gpu: &Gpu, tile: &Rgb) -> Option<Rgb> {
        let (w, h, s) = (tile.w, tile.h, self.scale);
        if w == 0 || h == 0 {
            return Some(Rgb::new(w * s, h * s, 0.0));
        }
        if w > u32::MAX as usize / s || h > u32::MAX as usize / s {
            return None;
        }
        let plane = w * h;
        let (ow, oh) = (w * s, h * s);
        let map_bytes = self.largest_buffer(w, h)?;
        if !(gpu.fits(map_bytes) && gpu.fits((3 * plane * 4) as u64) && gpu.fits((3 * ow * oh * 4) as u64)) {
            return None;
        }
        let _guard = gpu.lock.lock().unwrap_or_else(|e| e.into_inner());
        let input: Vec<f32> = tile.planes.iter().flat_map(|p| p.iter().map(|v| v / 255.0)).collect();
        let input = gpu.storage(bytemuck::cast_slice(&input));
        let ping = gpu.empty_storage(map_bytes);
        let pong = gpu.empty_storage(map_bytes);
        let output = gpu.empty_storage((3 * ow * oh * 4) as u64);
        let group = |p: &Params, src: &wgpu::Buffer, dst: &wgpu::Buffer| {
            let uniform = gpu.uniform(bytemuck::bytes_of(p));
            gpu.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: None,
                layout: &self.layout,
                entries: &[
                    wgpu::BindGroupEntry { binding: 0, resource: uniform.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 1, resource: self.weights.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 2, resource: src.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 3, resource: dst.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 4, resource: input.as_entire_binding() },
                ],
            })
        };
        let mut passes = Vec::new();
        let mut src = &input;
        let mut next = &ping;
        for l in &self.layers {
            let p = Params {
                cin: l.cin as u32,
                cout: l.cout as u32,
                w: w as u32,
                h: h as u32,
                w_off: l.w_off as u32,
                b_off: l.b_off as u32,
                a_off: l.a_off as u32,
                prelu: l.prelu as u32,
                scale: s as u32,
                pad: [0; 3],
            };
            passes.push((&self.conv, group(&p, src, next), (w, h, l.cout.div_ceil(8))));
            src = next;
            next = if std::ptr::eq(next, &ping) { &pong } else { &ping };
        }
        let p = Params {
            cin: 0,
            cout: 0,
            w: w as u32,
            h: h as u32,
            w_off: 0,
            b_off: 0,
            a_off: 0,
            prelu: 0,
            scale: s as u32,
            pad: [0; 3],
        };
        passes.push((&self.shuffle, group(&p, src, &output), (ow, oh, 3)));

        let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for (pipeline, bind, (x, y, z)) in &passes {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, bind, &[]);
            pass.dispatch_workgroups(x.div_ceil(8) as u32, y.div_ceil(8) as u32, *z as u32);
        }
        gpu.queue.submit([encoder.finish()]);
        let data = gpu.read_f32(&output, 3 * ow * oh).ok()?;
        let mut out = Rgb::new(ow, oh, 0.0);
        for (c, plane) in out.planes.iter_mut().enumerate() {
            for (d, v) in plane.iter_mut().zip(&data[c * ow * oh..(c + 1) * ow * oh]) {
                *d = v * 255.0;
            }
        }
        Some(out)
    }
}

/// Runs `model` on one tile with zero padding at the tile's edges, like [`super::cpu_forward`]. `None` when the
/// buffers do not fit the device or the readback fails.
pub fn run_tile(gpu: &Gpu, model: &Model, tile: &Rgb) -> Option<Rgb> {
    TileRunner::new(gpu, model)?.run(gpu, tile)
}
