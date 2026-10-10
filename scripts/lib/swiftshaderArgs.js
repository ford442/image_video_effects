/**
 * Chromium flags that give a working software WebGPU adapter (SwiftShader via
 * Vulkan) on GPU-less hosts. All of them matter: without --use-angle=swiftshader
 * canvas presentation drops the Dawn instance and later readbacks reject.
 * Compositor screenshots stay blank; read pixels back through the renderer.
 * Shared by playwright.config.ts and scripts/generate-shader-thumbnails.js.
 */
const SWIFTSHADER_WEBGPU_ARGS = [
  '--enable-unsafe-webgpu',
  '--enable-features=Vulkan',
  '--use-vulkan=swiftshader',
  '--use-webgpu-adapter=swiftshader',
  '--enable-unsafe-swiftshader',
  '--use-angle=swiftshader',
  '--use-fake-device-for-media-stream',
  '--use-fake-ui-for-media-stream',
  '--autoplay-policy=no-user-gesture-required',
];

module.exports = { SWIFTSHADER_WEBGPU_ARGS };
