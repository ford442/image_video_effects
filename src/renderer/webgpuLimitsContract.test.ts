/**
 * Contract test: MINIMUM_COMPUTE_LIMITS (TS) must match src/contracts/webgpu_limits.json
 * and stay aligned with wasm_renderer/device.cpp (enforced by verify:device-policy in CI).
 */

import contract from '../contracts/webgpu_limits.json';
import { MINIMUM_COMPUTE_LIMITS } from './webgpuDevicePolicy';
import { UNIFORM_BUFFER_LAYOUT } from './types';

const CONTRACT_LIMITS = contract.minimumComputeLimits;

describe('webgpu limits contract (shared JSON)', () => {
  it('exports the expected contract version', () => {
    expect(contract.version).toBe(1);
  });

  it('matches MINIMUM_COMPUTE_LIMITS for every shared limit key', () => {
    const keys = Object.keys(CONTRACT_LIMITS) as (keyof typeof CONTRACT_LIMITS)[];
    expect(keys.length).toBeGreaterThan(0);

    for (const key of keys) {
      expect(MINIMUM_COMPUTE_LIMITS[key]).toBe(CONTRACT_LIMITS[key]);
    }
  });

  it('keeps maxUniformBufferBindingSize aligned with Uniforms buffer layout', () => {
    expect(CONTRACT_LIMITS.maxUniformBufferBindingSize).toBe(UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE);
    expect(MINIMUM_COMPUTE_LIMITS.maxUniformBufferBindingSize).toBe(UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE);
  });

  it('requires at least 14 bindings for the compute bind group', () => {
    expect(CONTRACT_LIMITS.maxBindingsPerBindGroup).toBeGreaterThanOrEqual(14);
  });
});
