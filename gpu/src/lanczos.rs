//! Lanczos-3 resampling on the GPU. The tap tables come from the CPU implementation, so the result differs from it
//! only by the order of the floating point sums.

use crate::context::Gpu;
use bytemuck::{Pod, Zeroable};
use up60p::filters::scale::taps;
use up60p::frame::Plane;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Dims {
    src_w: u32,
    src_h: u32,
    dst_w: u32,
    dst_h: u32,
}

pub struct Lanczos {
    horizontal: wgpu::ComputePipeline,
    vertical: wgpu::ComputePipeline,
    layout: wgpu::BindGroupLayout,
}

fn entry(binding: u32, ty: wgpu::BufferBindingType) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::COMPUTE,
        ty: wgpu::BindingType::Buffer { ty, has_dynamic_offset: false, min_binding_size: None },
        count: None,
    }
}

/// Flattens tap tables into `(first, count, offset, 0)` quadruples and one weight list.
fn flatten(taps: Vec<(usize, Vec<f32>)>) -> (Vec<u32>, Vec<f32>) {
    let mut table = Vec::with_capacity(taps.len() * 4);
    let mut weights = Vec::new();
    for (first, w) in taps {
        table.extend([first as u32, w.len() as u32, weights.len() as u32, 0]);
        weights.extend(w);
    }
    (table, weights)
}

impl Lanczos {
    pub fn new(gpu: &Gpu) -> Lanczos {
        let module = gpu.device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("lanczos"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders/lanczos.wgsl").into()),
        });
        let ro = wgpu::BufferBindingType::Storage { read_only: true };
        let rw = wgpu::BufferBindingType::Storage { read_only: false };
        let layout = gpu.device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[
                entry(0, wgpu::BufferBindingType::Uniform),
                entry(1, ro),
                entry(2, ro),
                entry(3, ro),
                entry(4, rw),
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
        Lanczos { horizontal: make("horizontal"), vertical: make("vertical"), layout }
    }

    /// `None` when the planes do not fit the device's buffers or the readback fails.
    pub fn resize(&self, gpu: &Gpu, p: &Plane, w: usize, h: usize) -> Option<Plane> {
        if p.w == w && p.h == h {
            return Some(p.clone());
        }
        let (src_bytes, mid_bytes, out_bytes) = ((p.w * p.h * 4) as u64, (w * p.h * 4) as u64, (w * h * 4) as u64);
        if ![src_bytes, mid_bytes, out_bytes].iter().all(|b| gpu.fits(*b)) {
            return None;
        }
        let _guard = gpu.lock.lock().unwrap_or_else(|e| e.into_inner());
        let (tx, wx) = flatten(taps(p.w, w));
        let (ty, wy) = flatten(taps(p.h, h));
        let dims = Dims { src_w: p.w as u32, src_h: p.h as u32, dst_w: w as u32, dst_h: h as u32 };
        let dims = gpu.uniform(bytemuck::bytes_of(&dims));
        let (tx, wx) = (gpu.storage(bytemuck::cast_slice(&tx)), gpu.storage(bytemuck::cast_slice(&wx)));
        let (ty, wy) = (gpu.storage(bytemuck::cast_slice(&ty)), gpu.storage(bytemuck::cast_slice(&wy)));
        let src = gpu.storage(bytemuck::cast_slice(&p.data));
        let mid = gpu.empty_storage(mid_bytes);
        let out = gpu.empty_storage(out_bytes);
        let group = |taps: &wgpu::Buffer, weights: &wgpu::Buffer, input: &wgpu::Buffer, output: &wgpu::Buffer| {
            gpu.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: None,
                layout: &self.layout,
                entries: &[
                    wgpu::BindGroupEntry { binding: 0, resource: dims.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 1, resource: taps.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 2, resource: weights.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 3, resource: input.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 4, resource: output.as_entire_binding() },
                ],
            })
        };
        let first = group(&tx, &wx, &src, &mid);
        let second = group(&ty, &wy, &mid, &out);
        let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for (pipeline, bind, x, y) in [(&self.horizontal, &first, w, p.h), (&self.vertical, &second, w, h)] {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, bind, &[]);
            pass.dispatch_workgroups(x.div_ceil(16) as u32, y.div_ceil(16) as u32, 1);
        }
        gpu.queue.submit([encoder.finish()]);
        let data = gpu.read_f32(&out, w * h).ok()?;
        Some(Plane { w, h, data })
    }
}
