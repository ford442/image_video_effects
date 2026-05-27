import { defineConfig, devices } from '@playwright/test';

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

  // Define projects
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
  ],

  // Global setup/teardown (optional)
  webServer: undefined, // We start servers manually in tests
});
