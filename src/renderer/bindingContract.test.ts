/**
 * Regression guard for the 14-entry compute bind group contract (bindings 0–13).
 */

import { MINIMUM_COMPUTE_LIMITS } from './webgpuDevicePolicy';
import { HISTORY_DEPTH } from './webgpu/webgpuConstants';

/** Core bindings 0–12 required; binding 13 is the optional history ring extension. */
const BINDING_LAYOUT = [
  { index: 0, resource: 'sampler', access: 'filtering' },
  { index: 1, resource: 'texture_2d<f32>', access: 'sample' },
  { index: 2, resource: 'texture_storage rgba32float', access: 'write' },
  { index: 3, resource: 'uniform Uniforms', access: 'read' },
  { index: 4, resource: 'texture_2d<f32>', access: 'sample' },
  { index: 5, resource: 'sampler', access: 'non-filtering' },
  { index: 6, resource: 'texture_storage r32float', access: 'write' },
  { index: 7, resource: 'texture_storage rgba32float', access: 'write' },
  { index: 8, resource: 'texture_storage rgba32float', access: 'write' },
  { index: 9, resource: 'texture_2d<f32>', access: 'sample' },
  { index: 10, resource: 'storage array<f32>', access: 'read_write' },
  { index: 11, resource: 'sampler_comparison', access: 'compare' },
  { index: 12, resource: 'storage read-only', access: 'read' },
  { index: 13, resource: 'texture_2d_array<f32>', access: 'sample', optional: true },
] as const;

describe('binding contract', () => {
  it('defines 14 layout entries (bindings 0–13)', () => {
    expect(BINDING_LAYOUT).toHaveLength(14);
    expect(BINDING_LAYOUT[0].index).toBe(0);
    expect(BINDING_LAYOUT[13].index).toBe(13);
    expect(BINDING_LAYOUT[13].optional).toBe(true);
  });

  it('requires maxBindingsPerBindGroup >= 14 in device policy', () => {
    expect(MINIMUM_COMPUTE_LIMITS.maxBindingsPerBindGroup).toBe(14);
  });

  it('keeps HISTORY_DEPTH aligned with BINDING_CONTRACT.md', () => {
    expect(HISTORY_DEPTH).toBe(8);
  });

  it('samples enough textures for readTexture, dataTextureC, and historyTexture', () => {
    expect(MINIMUM_COMPUTE_LIMITS.maxSampledTexturesPerShaderStage).toBeGreaterThanOrEqual(3);
  });
});
