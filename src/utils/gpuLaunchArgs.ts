/**
 * Chromium flags for real-GPU Playwright runs (WASM_GPU_TESTS=1, #1357 T1).
 *
 * Without them headless Chromium returns no adapter. Linux needs the Vulkan +
 * ANGLE set (X11 and Wayland both); Windows stays on its D3D12 default so the
 * comparison is the one users get. No --ozone-platform: it fights the session.
 */
export const GPU_LAUNCH_ARGS_COMMON = [
  '--enable-unsafe-webgpu',
  '--ignore-gpu-blocklist',
  '--use-webgpu-adapter=default',
];

export const GPU_LAUNCH_ARGS_LINUX = [
  '--enable-features=Vulkan,VulkanFromANGLE',
  '--use-angle=vulkan',
  '--use-vulkan=native',
  '--disable-vulkan-surface',
];

/**
 * Un-quantised GPU timestamps (WASM_BENCH_DEV_FEATURES=1, #1080). Chromium
 * otherwise rounds timestamp-query to 100 µs buckets. Off by default (#1357 Q1).
 */
export const GPU_LAUNCH_ARGS_DEV_FEATURES = [
  '--enable-webgpu-developer-features',
  '--enable-dawn-features=allow_unsafe_apis',
];

export function buildGpuLaunchArgs(platform: string, gpuTests: boolean, devFeatures = false): string[] {
  if (!gpuTests) return [];
  return [
    ...GPU_LAUNCH_ARGS_COMMON,
    ...(platform === 'linux' ? GPU_LAUNCH_ARGS_LINUX : []),
    ...(devFeatures ? GPU_LAUNCH_ARGS_DEV_FEATURES : []),
  ];
}

export function isBenchDevFeaturesEnabled(env: Record<string, string | undefined> = process.env): boolean {
  return env.WASM_BENCH_DEV_FEATURES === '1';
}
