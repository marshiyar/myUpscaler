//! BM3D denoising on the GPU: the same grid, search window, group size, threshold and window as the CPU stage in
//! `up60p::filters::bm3d`, whose tables it uploads. Groups are matched, transformed and aggregated by one
//! invocation each; the sums into the shared result use compare-and-swap, so they differ from the CPU's only by
//! the order of the floating point additions (and, where two candidates match equally well, possibly the pick).

use crate::context::Gpu;
use bytemuck::{Pod, Zeroable};
use up60p::filters::bm3d::{Bm3d, N, STEP};
use up60p::frame::Plane;

/// Reference blocks per submission, so one dispatch stays short enough for the display driver's watchdog.
const BLOCKS_PER_SUBMIT: usize = 4096;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
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

pub struct Bm3dStage {
    denoise: wgpu::ComputePipeline,
    finish: wgpu::ComputePipeline,
    layout: wgpu::BindGroupLayout,
    tables: Vec<f32>,
}

fn entry(binding: u32, ty: wgpu::BufferBindingType) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::COMPUTE,
        ty: wgpu::BindingType::Buffer { ty, has_dynamic_offset: false, min_binding_size: None },
        count: None,
    }
}

/// Number of reference positions along a side of `len` samples: every STEP, plus the last block.
fn grid_len(len: usize) -> usize {
    (len - N) / STEP + 1 + usize::from(!(len - N).is_multiple_of(STEP))
}

impl Bm3dStage {
    pub fn new(gpu: &Gpu) -> Bm3dStage {
        let module = gpu.device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("bm3d"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shaders/bm3d.wgsl").into()),
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
        let cpu = Bm3d::new(None);
        let tables = cpu.dct_basis().iter().chain(cpu.kaiser_window().iter()).flatten().copied().collect();
        Bm3dStage { denoise: make("denoise"), finish: make("finish"), layout, tables }
    }

    /// `None` when the plane does not fit the device's buffers or the readback fails.
    pub fn denoise(&self, gpu: &Gpu, p: &Plane, sigma: f32) -> Option<Plane> {
        let (w, h) = (p.w, p.h);
        if w < N || h < N {
            return Some(p.clone());
        }
        let plane_bytes = (w * h * 4) as u64;
        if !gpu.fits(plane_bytes * 2) {
            return None;
        }
        let _guard = gpu.lock.lock().unwrap_or_else(|e| e.into_inner());
        let (nx, ny) = (grid_len(w), grid_len(h));
        let params = |row_start: usize, row_count: usize| Params {
            w: w as u32,
            h: h as u32,
            nx: nx as u32,
            ny: ny as u32,
            row_start: row_start as u32,
            row_count: row_count as u32,
            sigma,
            pad: 0,
        };
        let tables = gpu.storage(bytemuck::cast_slice(&self.tables));
        let src = gpu.storage(bytemuck::cast_slice(&p.data));
        let acc = gpu.empty_storage(plane_bytes * 2);
        let out = gpu.empty_storage(plane_bytes);
        let group = |uniform: &wgpu::Buffer| {
            gpu.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: None,
                layout: &self.layout,
                entries: &[
                    wgpu::BindGroupEntry { binding: 0, resource: uniform.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 1, resource: tables.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 2, resource: src.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 3, resource: acc.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 4, resource: out.as_entire_binding() },
                ],
            })
        };
        let rows_per_submit = (BLOCKS_PER_SUBMIT / nx).max(1);
        for start in (0..ny).step_by(rows_per_submit) {
            let count = rows_per_submit.min(ny - start);
            let uniform = gpu.uniform(bytemuck::bytes_of(&params(start, count)));
            let bind = group(&uniform);
            let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
                pass.set_pipeline(&self.denoise);
                pass.set_bind_group(0, &bind, &[]);
                pass.dispatch_workgroups(nx.div_ceil(8) as u32, count.div_ceil(8) as u32, 1);
            }
            gpu.queue.submit([encoder.finish()]);
            gpu.device.poll(wgpu::PollType::wait_indefinitely()).ok()?;
        }
        let uniform = gpu.uniform(bytemuck::bytes_of(&params(0, ny)));
        let bind = group(&uniform);
        let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            pass.set_pipeline(&self.finish);
            pass.set_bind_group(0, &bind, &[]);
            pass.dispatch_workgroups((w * h).div_ceil(256) as u32, 1, 1);
        }
        gpu.queue.submit([encoder.finish()]);
        let data = gpu.read_f32(&out, w * h).ok()?;
        Some(Plane { w, h, data })
    }
}
