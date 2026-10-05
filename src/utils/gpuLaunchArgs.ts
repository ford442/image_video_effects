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

export function buildGpuLaunchArgs(platform: string, gpuTests: boolean): string[] {
  if (!gpuTests) return [];
  return platform === 'linux'
    ? [...GPU_LAUNCH_ARGS_COMMON, ...GPU_LAUNCH_ARGS_LINUX]
    : [...GPU_LAUNCH_ARGS_COMMON];
}
