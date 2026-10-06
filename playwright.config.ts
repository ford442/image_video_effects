import { defineConfig, devices } from '@playwright/test';
import { buildGpuLaunchArgs, isBenchDevFeaturesEnabled } from './src/utils/gpuLaunchArgs';

/** Real-GPU runs (WASM_GPU_TESTS=1, #1357): GPU flags + new headless on the chromium project. */
const GPU_TESTS = process.env.WASM_GPU_TESTS === '1';
export const GPU_LAUNCH_ARGS = buildGpuLaunchArgs(process.platform, GPU_TESTS, isBenchDevFeaturesEnabled());

/** Desktop Chrome viewport without its spoofed Windows user agent (GPU runs report the real platform). */
const { userAgent: _spoofedUserAgent, ...desktopChromeNoUa } = devices['Desktop Chrome'];

/** Chromium flags that give a working software WebGPU adapter (see tests/engine2.swiftshader.spec.ts). */
export const SWIFTSHADER_WEBGPU_ARGS = [
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

/**
 * Playwright configuration for smoke tests.
 * Configured for reliable testing in both local and CI environments.
 */
export default defineConfig({
  testDir: './tests',
  testMatch: '**/*.spec.ts',
  
  // Fail on console errors (except warnings)
  fullyParallel: false,
  
  // Test timeout: 30 seconds per test
  timeout: 30 * 1000,
  
  // Expect timeout: 5 seconds
  expect: {
    timeout: 5 * 1000,
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.25,
    },
  },

  // Retry failed tests once in CI, 0 times locally
  retries: process.env.CI ? 1 : 0,

  // Run 1 test at a time to avoid port conflicts
  workers: 1,

  // Report configuration
  reporter: [
    ['html', { outputFolder: 'playwright-report' }],
    ['json', { outputFile: 'test-results/playwright-results.json' }],
    ['junit', { outputFile: 'test-results/junit.xml' }],
    ['list'],
  ],

  // Shared settings for all browsers
  use: {
    // Use action to get verbose logs
    actionTimeout: 10 * 1000,
    navigationTimeout: 30 * 1000,
    
    // Enable video on failures for CI debugging
    video: process.env.CI ? 'retain-on-failure' : 'off',
    
    // Screenshot on failure
    screenshot: 'only-on-failure',
  },

  // Chromium only: every npm script and CI job passes --project=chromium.
  // Specs start their own servers, so there is no webServer block.
  projects: [
    {
      name: 'chromium',
      testIgnore: '**/*.swiftshader.spec.ts',
      // channel 'chromium' = new headless (full browser); headless-shell disables GPU compositing.
      use: GPU_TESTS
        ? { ...desktopChromeNoUa, channel: 'chromium', launchOptions: { args: GPU_LAUNCH_ARGS } }
        : { ...devices['Desktop Chrome'] },
    },
    {
      // Software WebGPU on GPU-less hosts (Cloud VM, CI). SwiftShader via Vulkan;
      // without --use-angle=swiftshader canvas presentation drops the Dawn instance.
      // Compositor screenshots stay blank: read pixels back through the renderer.
      name: 'swiftshader',
      testMatch: '**/*.swiftshader.spec.ts',
      timeout: 120 * 1000,
      use: {
        ...devices['Desktop Chrome'],
        launchOptions: { args: SWIFTSHADER_WEBGPU_ARGS },
      },
    },
    {
      // The existing renderer smoke suites on the software device. Run once per
      // render thread: PX_RENDER_THREAD=main|worker (default worker, #1314).
      name: 'swiftshader-smoke',
      testMatch: ['**/wasm-renderer.smoke.spec.ts', '**/layerChain.smoke.spec.ts'],
      timeout: 120 * 1000,
      use: {
        ...devices['Desktop Chrome'],
        launchOptions: { args: SWIFTSHADER_WEBGPU_ARGS },
      },
    },
  ],
});
