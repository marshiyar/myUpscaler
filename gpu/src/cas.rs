//! Contrast-adaptive sharpening on the GPU: the same per-pixel arithmetic as `Cas::apply` in `up60p`, so the result
//! differs from it only by floating point rounding in the square root and division.

use crate::context::Gpu;
use bytemuck::{Pod, Zeroable};
use up60p::frame::Plane;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Params {
    w: u32,
    h: u32,
    peak: f32,
    pad: u32,
}

pub struct Cas {
    pipeline: wgpu::ComputePipeline,
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

impl Cas {
    pub fn new(gpu: &Gpu) -> Cas {
        let module = gpu.device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("cas"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders/cas.wgsl").into()),
        });
        let layout = gpu.device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[
                entry(0, wgpu::BufferBindingType::Uniform),
                entry(1, wgpu::BufferBindingType::Storage { read_only: true }),
                entry(2, wgpu::BufferBindingType::Storage { read_only: false }),
            ],
        });
        let pipeline_layout = gpu.device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: None,
            bind_group_layouts: &[Some(&layout)],
            immediate_size: 0,
        });
        let pipeline = gpu.device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("cas"),
            layout: Some(&pipeline_layout),
            module: &module,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });
        Cas { pipeline, layout }
    }

    /// `None` when the plane is empty, does not fit the device's buffers, or the readback fails.
    pub fn apply(&self, gpu: &Gpu, p: &Plane, strength: f32) -> Option<Plane> {
        let bytes = (p.w * p.h * 4) as u64;
        if p.w == 0 || p.h == 0 || !gpu.fits(bytes) {
            return None;
        }
        let strength = strength.clamp(0.0, 1.0);
        let _guard = gpu.lock.lock().unwrap_or_else(|e| e.into_inner());
        let params = Params { w: p.w as u32, h: p.h as u32, peak: -1.0 / (8.0 + (5.0 - 8.0) * strength), pad: 0 };
        let params = gpu.uniform(bytemuck::bytes_of(&params));
        let src = gpu.storage(bytemuck::cast_slice(&p.data));
        let out = gpu.empty_storage(bytes);
        let bind = gpu.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &self.layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: params.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: src.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 2, resource: out.as_entire_binding() },
            ],
        });
        let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &bind, &[]);
            pass.dispatch_workgroups(p.w.div_ceil(16) as u32, p.h.div_ceil(16) as u32, 1);
        }
        gpu.queue.submit([encoder.finish()]);
        let data = gpu.read_f32(&out, p.w * p.h).ok()?;
        Some(Plane { w: p.w, h: p.h, data })
    }
}
