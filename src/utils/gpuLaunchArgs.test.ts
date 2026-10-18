import { buildGpuLaunchArgs, isBenchDevFeaturesEnabled } from './gpuLaunchArgs';

describe('buildGpuLaunchArgs', () => {
  it('adds nothing when GPU tests are off', () => {
    expect(buildGpuLaunchArgs('linux', false)).toEqual([]);
    expect(buildGpuLaunchArgs('win32', false)).toEqual([]);
  });

  it('uses Vulkan + ANGLE on Linux', () => {
    const args = buildGpuLaunchArgs('linux', true);
    expect(args).toEqual(expect.arrayContaining([
      '--enable-unsafe-webgpu',
      '--ignore-gpu-blocklist',
      '--enable-features=Vulkan,VulkanFromANGLE',
      '--use-angle=vulkan',
      '--use-vulkan=native',
      '--disable-vulkan-surface',
    ]));
  });

  it('keeps Windows on its D3D12 default', () => {
    const args = buildGpuLaunchArgs('win32', true);
    expect(args).toContain('--enable-unsafe-webgpu');
    expect(args).toContain('--ignore-gpu-blocklist');
    expect(args.some((a) => /vulkan/i.test(a))).toBe(false);
  });

  it('never pins an ozone platform', () => {
    expect(buildGpuLaunchArgs('linux', true).some((a) => a.startsWith('--ozone-platform'))).toBe(false);
  });

  it('adds developer features only on request', () => {
    expect(buildGpuLaunchArgs('linux', true)).not.toContain('--enable-webgpu-developer-features');
    const args = buildGpuLaunchArgs('linux', true, true);
    expect(args).toContain('--enable-webgpu-developer-features');
    expect(args).toContain('--enable-dawn-features=allow_unsafe_apis');
    expect(buildGpuLaunchArgs('linux', false, true)).toEqual([]);
  });

  it('reads WASM_BENCH_DEV_FEATURES', () => {
    expect(isBenchDevFeaturesEnabled({ WASM_BENCH_DEV_FEATURES: '1' })).toBe(true);
    expect(isBenchDevFeaturesEnabled({})).toBe(false);
  });
});
