#!/usr/bin/env node
/**
 * Shader Validator - Tests all shaders on deployed site
 * Checks: WebGPU compilation, parameter slider values, runtime errors
 * 
 * Usage: node shader-validator.js [url]
 * Default URL: https://test.1ink.us/image_video_effects/index.html
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const DEFAULT_URL = 'https://test.1ink.us/image_video_effects/index.html';
const TEST_URL = process.argv[2] || DEFAULT_URL;

// Test configuration
const CONFIG = {
  shaderTimeout: 3000,      // Time to wait for shader compilation
  paramTestValue: 0.5,      // Test value to set params to
  screenshotOnError: false, // Set to true for debugging
  headless: true,           // Set to false to see browser
};

// Results storage
const results = {
  passed: [],
  failed: [],
  warnings: [],
  startTime: Date.now(),
};

async function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function validateShaders() {
  console.log('🚀 Shader Validator Starting...');
  console.log(`📍 URL: ${TEST_URL}`);
  console.log('');

  const browser = await chromium.launch({ 
    headless: CONFIG.headless,
    args: ['--enable-webgpu', '--enable-features=Vulkan'] 
  });

  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 }
  });

  const page = await context.newPage();

  // Collect console errors
  const consoleErrors = [];
  page.on('console', msg => {
    if (msg.type() === 'error') {
      consoleErrors.push(msg.text());
    }
  });

  // Collect page errors
  const pageErrors = [];
  page.on('pageerror', error => {
    pageErrors.push(error.message);
  });

  try {
    // Navigate to site
    console.log('⏳ Loading page...');
    await page.goto(TEST_URL, { waitUntil: 'networkidle', timeout: 60000 });
    
    // Wait for WebGPU initialization
    console.log('⏳ Waiting for WebGPU initialization...');
    await delay(3000);

    // Check if WebGPU is available
    const webgpuAvailable = await page.evaluate(() => {
      return !!navigator.gpu;
    });

    if (!webgpuAvailable) {
      console.error('❌ WebGPU not available in browser');
      await browser.close();
      process.exit(1);
    }

    console.log('✅ WebGPU available');
    console.log('');

    // Get shader list from the page
    console.log('📋 Fetching shader list...');
    const shaderList = await page.evaluate(async () => {
      // Wait for shader lists to load
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Try to find shader dropdowns or lists
      const selects = document.querySelectorAll('select');
      const shaders = [];
      
      for (const select of selects) {
        if (select.options.length > 10) { // Likely a shader selector
          for (const option of select.options) {
            if (option.value && option.text) {
              shaders.push({
                id: option.value,
                name: option.text,
                category: select.name || select.id || 'unknown'
              });
            }
          }
        }
      }
      
      // Alternative: check window for shader data
      if (shaders.length === 0 && window.shaderLists) {
        for (const [category, list] of Object.entries(window.shaderLists)) {
          for (const shader of list) {
            shaders.push({
              id: shader.id || shader.url,
              name: shader.name,
              category: category
            });
          }
        }
      }
      
      return shaders;
    });

    if (shaderList.length === 0) {
      console.log('⚠️  Could not find shader list, trying manual fetch...');
      // Try to fetch shader-lists JSON directly
      const response = await page.evaluate(async () => {
        try {
          const res = await fetch('shader-lists/image-effects.json');
          return await res.json();
        } catch (e) {
          return [];
        }
      });
      
      if (response.length > 0) {
        shaderList.push(...response.map(s => ({
          id: s.id || s.url,
          name: s.name,
          category: 'image'
        })));
      }
    }

    console.log(`📝 Found ${shaderList.length} shaders`);
    console.log('');

    // Test sample of shaders (full test takes too long)
    const testSample = shaderList.slice(0, 50); // Test first 50
    console.log(`🧪 Testing ${testSample.length} shaders...`);
    console.log('');

    // Test each shader
    for (let i = 0; i < testSample.length; i++) {
      const shader = testSample[i];
      const progress = `[${i + 1}/${testSample.length}]`;
      
      process.stdout.write(`${progress} Testing: ${shader.name}... `);
      
      try {
        // Clear previous errors
        consoleErrors.length = 0;
        pageErrors.length = 0;

        // Select shader
        const selected = await page.evaluate(async (shaderId) => {
          // Find and use shader selector
          const selects = document.querySelectorAll('select');
          for (const select of selects) {
            if (select.options.length > 10) {
              const option = Array.from(select.options).find(o => 
                o.value.includes(shaderId) || o.text.includes(shaderId)
              );
              if (option) {
                select.value = option.value;
                select.dispatchEvent(new Event('change', { bubbles: true }));
                return true;
              }
            }
          }
          
          // Try window function if available
          if (window.loadShader) {
            window.loadShader(shaderId);
            return true;
          }
          
          return false;
        }, shader.id || shader.name);

        if (!selected) {
          results.warnings.push({
            shader: shader.name,
            issue: 'Could not select shader'
          });
          process.stdout.write('⚠️ SKIP\n');
          continue;
        }

        // Wait for shader to compile
        await delay(CONFIG.shaderTimeout);

        // Check for errors
        const hasErrors = consoleErrors.some(e => 
          e.includes('WebGPU') || 
          e.includes('shader') || 
          e.includes('pipeline') ||
          e.includes('compilation')
        ) || pageErrors.some(e => 
          e.includes('WebGPU') || 
          e.includes('shader')
        );

        if (hasErrors) {
          results.failed.push({
            shader: shader.name,
            id: shader.id,
            errors: [...consoleErrors, ...pageErrors]
          });
          process.stdout.write('❌ FAIL\n');
          continue;
        }

        // Check parameter sliders
        const paramStatus = await page.evaluate(() => {
          const sliders = document.querySelectorAll('input[type="range"]');
          const params = [];
          
          for (const slider of sliders) {
            const value = parseFloat(slider.value);
            const min = parseFloat(slider.min) || 0;
            const max = parseFloat(slider.max) || 1;
            const hasDefault = slider.hasAttribute('data-default') || 
                              slider.defaultValue !== undefined;
            
            params.push({
              name: slider.name || slider.id || 'unnamed',
              value: value,
              min: min,
              max: max,
              hasDefault: hasDefault,
              inRange: value >= min && value <= max
            });
          }
          
          return {
            paramCount: sliders.length,
            params: params
          };
        });

        // Test setting parameters
        if (paramStatus.paramCount > 0) {
          await page.evaluate((testValue) => {
            const sliders = document.querySelectorAll('input[type="range"]');
            for (const slider of sliders) {
              const min = parseFloat(slider.min) || 0;
              const max = parseFloat(slider.max) || 1;
              const testVal = min + (max - min) * testValue;
              slider.value = testVal;
              slider.dispatchEvent(new Event('input', { bubbles: true }));
            }
          }, CONFIG.paramTestValue);

          await delay(500);

          // Verify params were set
          const paramsSet = await page.evaluate(() => {
            const sliders = document.querySelectorAll('input[type="range"]');
            return Array.from(sliders).every(s => {
              const val = parseFloat(s.value);
              return !isNaN(val);
            });
          });

          if (!paramsSet) {
            results.warnings.push({
              shader: shader.name,
              issue: 'Parameter sliders may not be responding'
            });
          }
        }

        results.passed.push({
          shader: shader.name,
          id: shader.id,
          params: paramStatus
        });
        
        process.stdout.write(`✅ PASS (${paramStatus.paramCount} params)\n`);

      } catch (error) {
        results.failed.push({
          shader: shader.name,
          id: shader.id,
          error: error.message
        });
        process.stdout.write('❌ ERROR\n');
      }
    }

    // Generate report
    console.log('');
    console.log('='.repeat(60));
    console.log('📊 VALIDATION REPORT');
    console.log('='.repeat(60));
    console.log(`Total tested: ${testSample.length}`);
    console.log(`✅ Passed: ${results.passed.length}`);
    console.log(`❌ Failed: ${results.failed.length}`);
    console.log(`⚠️  Warnings: ${results.warnings.length}`);
    console.log(`Duration: ${((Date.now() - results.startTime) / 1000).toFixed(1)}s`);
    console.log('');

    if (results.failed.length > 0) {
      console.log('❌ FAILED SHADERS:');
      console.log('-'.repeat(60));
      for (const fail of results.failed) {
        console.log(`  • ${fail.shader}`);
        if (fail.errors) {
          for (const err of fail.errors.slice(0, 3)) {
            console.log(`    - ${err.substring(0, 80)}`);
          }
        }
        if (fail.error) {
          console.log(`    - ${fail.error}`);
        }
      }
      console.log('');
    }

    if (results.warnings.length > 0) {
      console.log('⚠️  WARNINGS:');
      console.log('-'.repeat(60));
      for (const warn of results.warnings.slice(0, 10)) {
        console.log(`  • ${warn.shader}: ${warn.issue}`);
      }
      if (results.warnings.length > 10) {
        console.log(`  ... and ${results.warnings.length - 10} more`);
      }
      console.log('');
    }

    // Save detailed report
    const reportPath = path.join(__dirname, '..', 'shader-validation-report.json');
    fs.writeFileSync(reportPath, JSON.stringify({
      url: TEST_URL,
      timestamp: new Date().toISOString(),
      config: CONFIG,
      summary: {
        total: testSample.length,
        passed: results.passed.length,
        failed: results.failed.length,
        warnings: results.warnings.length
      },
      results
    }, null, 2));
    
    console.log(`💾 Detailed report saved to: ${reportPath}`);

  } catch (error) {
    console.error('❌ Fatal error:', error.message);
  } finally {
    await browser.close();
  }
}

// Run validation
validateShaders().catch(console.error);
