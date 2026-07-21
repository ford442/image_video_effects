/**
 * Tests for parseWorkgroupSize — entry-point-aware workgroup size parsing.
 *
 * Regression: shaders that declare a 1D helper kernel (e.g.
 * `@workgroup_size(64, 1, 1) fn update_boids`) BEFORE the 2D `main` entry
 * used to dispatch `main` with the helper's workgroup size, covering only a
 * fraction of the frame with massive Y overdraw. The parser must return the
 * workgroup size of the entry point actually dispatched (`main`).
 */

import { parseWorkgroupSize } from './ShaderCompilation';

describe('parseWorkgroupSize', () => {
  it('parses a standard 2D workgroup size', () => {
    const wgsl = `
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {}
`;
    expect(parseWorkgroupSize(wgsl)).toEqual({ x: 16, y: 16 });
  });

  it('returns the workgroup size of `main`, not the first entry point in the file', () => {
    // The boids.wgsl / kimi_flock_symphony.wgsl bug shape
    const wgsl = `
@compute @workgroup_size(64, 1, 1)
fn update_boids(@builtin(global_invocation_id) gid: vec3<u32>) {}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {}
`;
    expect(parseWorkgroupSize(wgsl)).toEqual({ x: 16, y: 16 });
  });

  it('honors an explicit entry point argument', () => {
    const wgsl = `
@compute @workgroup_size(64, 1, 1)
fn update_boids(@builtin(global_invocation_id) gid: vec3<u32>) {}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {}
`;
    expect(parseWorkgroupSize(wgsl, 'update_boids')).toEqual({ x: 64, y: 1 });
  });

  it('does not match a different entry point with a shared prefix (main2)', () => {
    const wgsl = `
@compute @workgroup_size(32, 8, 1)
fn main2(@builtin(global_invocation_id) gid: vec3<u32>) {}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {}
`;
    expect(parseWorkgroupSize(wgsl)).toEqual({ x: 16, y: 16 });
  });

  it('falls back to the first match when no `main` entry point exists', () => {
    const wgsl = `
@compute @workgroup_size(8, 4, 1)
fn simulate(@builtin(global_invocation_id) gid: vec3<u32>) {}
`;
    expect(parseWorkgroupSize(wgsl)).toEqual({ x: 8, y: 4 });
  });

  it('tolerates whitespace and newlines between attributes and fn', () => {
    const wgsl = `
@compute
@workgroup_size(
  16,
  16,
  1
)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {}
`;
    expect(parseWorkgroupSize(wgsl)).toEqual({ x: 16, y: 16 });
  });

  it('defaults to 8x8 when no workgroup size can be parsed', () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    expect(parseWorkgroupSize('fn main() {}')).toEqual({ x: 8, y: 8 });
    warn.mockRestore();
  });
});
