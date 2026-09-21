/**
 * Group-1 opt-in: only shaders that declare @group(1) get the two-group layout.
 * Catalog shaders keep compiling and dispatching on the single-group layout.
 */

import { WebGPUPipelineModule, WebGPUShaderManager } from './pipeline';

const HEADER = /* wgsl */ `
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
`;

const PLAIN = `${HEADER}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  textureStore(writeTexture, gid.xy, vec4<f32>(0.0));
}
`;

const RING = `${HEADER}
struct SimParams { stateCount: u32, indexCount: u32, frame: u32, truncated: u32 };
@group(1) @binding(0) var<storage, read_write> simState: array<vec4<f32>>;
@group(1) @binding(1) var<storage, read> simIndex: array<u32>;
@group(1) @binding(2) var<uniform> simParams: SimParams;
@compute @workgroup_size(64, 1, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= simParams.stateCount) { return; }
  simState[gid.x] = simState[gid.x] + vec4<f32>(0.0, 0.0, 0.0, 1.0);
}
`;

beforeAll(() => {
  (global as unknown as Record<string, unknown>).GPUShaderStage = { VERTEX: 1, FRAGMENT: 2, COMPUTE: 4 };
});

function makeDevice() {
  const createComputePipeline = jest.fn((desc: GPUComputePipelineDescriptor) => ({
    label: desc.label,
    layout: desc.layout,
  }));
  const createPipelineLayout = jest.fn((desc: GPUPipelineLayoutDescriptor) => ({
    label: desc.label,
    groups: Array.from(desc.bindGroupLayouts),
  }));
  const device = {
    pushErrorScope: jest.fn(),
    popErrorScope: jest.fn(async () => null),
    createShaderModule: jest.fn(() => ({ getCompilationInfo: jest.fn(async () => ({ messages: [] })) })),
    createComputePipeline,
    createPipelineLayout,
    createBindGroupLayout: jest.fn((desc: GPUBindGroupLayoutDescriptor) => ({ label: desc.label })),
  };
  return { device: device as unknown as GPUDevice, createComputePipeline, createPipelineLayout };
}

const SINGLE = { label: 'computePL' } as unknown as GPUPipelineLayout;
const TWO = { label: 'computePL-simRing' } as unknown as GPUPipelineLayout;

describe('WebGPUShaderManager sim-ring opt-in', () => {
  it('compiles catalog shaders on the single-group layout and never asks for the ring', async () => {
    const { device, createComputePipeline } = makeDevice();
    const provider = jest.fn(async () => TWO);
    const mgr = new WebGPUShaderManager();

    await expect(mgr.compile(device, SINGLE, 'plain', PLAIN, provider)).resolves.toBe(true);
    expect(provider).not.toHaveBeenCalled();
    expect(createComputePipeline.mock.calls[0][0].layout).toBe(SINGLE);
    expect(mgr.getBindingUsage('plain').usesSimRing).toBe(false);
  });

  it('compiles @group(1) shaders on the two-group layout from the provider', async () => {
    const { device, createComputePipeline } = makeDevice();
    const provider = jest.fn(async () => TWO);
    const mgr = new WebGPUShaderManager();

    await expect(mgr.compile(device, SINGLE, 'walkers', RING, provider)).resolves.toBe(true);
    expect(provider).toHaveBeenCalledTimes(1);
    expect(createComputePipeline.mock.calls[0][0].layout).toBe(TWO);
    expect(mgr.getBindingUsage('walkers').usesSimRing).toBe(true);
    expect(mgr.getWorkgroupSize('walkers')).toEqual({ x: 64, y: 1 });
  });

  it('fails soft (no pipeline) when the ring cannot be allocated', async () => {
    const { device, createComputePipeline } = makeDevice();
    const mgr = new WebGPUShaderManager();
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});

    await expect(mgr.compile(device, SINGLE, 'walkers', RING, async () => null)).resolves.toBe(false);
    await expect(mgr.compile(device, SINGLE, 'walkers', RING)).resolves.toBe(false);
    warn.mockRestore();

    expect(createComputePipeline).not.toHaveBeenCalled();
    expect(mgr.hasPipeline('walkers')).toBe(false);
  });
});

describe('WebGPUPipelineModule layouts', () => {
  it('keeps the default layout single-group and builds [group0, group1] lazily', () => {
    const { device, createPipelineLayout } = makeDevice();
    const mod = new WebGPUPipelineModule();
    mod.setupComputeLayout(device, false);

    expect(createPipelineLayout).toHaveBeenCalledTimes(1);
    expect((mod.pipelineLayout as unknown as { groups: unknown[] }).groups).toHaveLength(1);
    expect(mod.simRingBindGroupLayout).toBeNull();

    const two = mod.getSimRingPipelineLayout(device) as unknown as { groups: unknown[] };
    expect(two.groups).toEqual([mod.bindGroupLayout, mod.simRingBindGroupLayout]);
    expect(mod.getSimRingPipelineLayout(device)).toBe(two);

    // Colour-format change rebuilds group 0, so the two-group layout must follow it.
    mod.setColorFormat(device, 'rgba16float');
    const rebuilt = mod.getSimRingPipelineLayout(device) as unknown as { groups: unknown[] };
    expect(rebuilt).not.toBe(two);
    expect(rebuilt.groups[0]).toBe(mod.bindGroupLayout);
  });
});
