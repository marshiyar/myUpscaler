//! The graphics device and the small helpers every stage shares.

use std::sync::Mutex;
use wgpu::util::DeviceExt;

pub struct Gpu {
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub adapter_name: String,
    pub limits: wgpu::Limits,
    /// Compute work is submitted one stage at a time.
    pub(crate) lock: Mutex<()>,
}

impl Gpu {
    /// Opens the best adapter. With `allow_software`, a software adapter is accepted when no real one exists.
    pub fn new(allow_software: bool) -> Result<Gpu, String> {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle());
        let mut adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            compatible_surface: None,
            apply_limit_buckets: false,
        }));
        if adapter.is_err() && allow_software {
            adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::LowPower,
                force_fallback_adapter: true,
                compatible_surface: None,
                apply_limit_buckets: false,
            }));
        }
        let adapter = adapter.map_err(|e| format!("no graphics adapter: {e}"))?;
        let info = adapter.get_info();
        if info.device_type == wgpu::DeviceType::Cpu && !allow_software {
            return Err(format!("only a software adapter ({}) is available", info.name));
        }
        let limits = adapter.limits();
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("up60p"),
            required_features: wgpu::Features::empty(),
            required_limits: limits.clone(),
            ..Default::default()
        }))
        .map_err(|e| format!("cannot open {}: {e}", info.name))?;
        Ok(Gpu { device, queue, adapter_name: info.name, limits, lock: Mutex::new(()) })
    }

    /// Whether a buffer of `bytes` bytes can be bound as storage on this device.
    pub fn fits(&self, bytes: u64) -> bool {
        bytes <= self.limits.max_storage_buffer_binding_size.min(self.limits.max_buffer_size)
    }

    pub(crate) fn storage(&self, data: &[u8]) -> wgpu::Buffer {
        self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: None,
            contents: data,
            usage: wgpu::BufferUsages::STORAGE,
        })
    }

    pub(crate) fn uniform(&self, data: &[u8]) -> wgpu::Buffer {
        self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: None,
            contents: data,
            usage: wgpu::BufferUsages::UNIFORM,
        })
    }

    pub(crate) fn empty_storage(&self, bytes: u64) -> wgpu::Buffer {
        self.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: bytes,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        })
    }

    /// Copies a storage buffer back to the CPU as floats.
    pub(crate) fn read_f32(&self, buffer: &wgpu::Buffer, count: usize) -> Result<Vec<f32>, String> {
        let bytes = (count * 4) as u64;
        let staging = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: bytes,
            usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        encoder.copy_buffer_to_buffer(buffer, 0, &staging, 0, bytes);
        self.queue.submit([encoder.finish()]);
        let (tx, rx) = std::sync::mpsc::channel();
        staging.slice(..).map_async(wgpu::MapMode::Read, move |r| {
            let _ = tx.send(r);
        });
        self.device.poll(wgpu::PollType::wait_indefinitely()).map_err(|e| format!("gpu wait failed: {e}"))?;
        rx.recv().map_err(|e| e.to_string())?.map_err(|e| format!("gpu readback failed: {e}"))?;
        let view = staging.slice(..).get_mapped_range().map_err(|e| format!("gpu readback failed: {e}"))?;
        let out = bytemuck::cast_slice::<u8, f32>(&view).to_vec();
        drop(view);
        staging.unmap();
        Ok(out)
    }
}
