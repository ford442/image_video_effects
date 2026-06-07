const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 }
  });
  const page = await context.newPage();
  
  const logs = [];
  const errors = [];
  
  // Capture console logs
  page.on('console', msg => {
    const logEntry = {
      type: msg.type(),
      text: msg.text(),
      location: msg.location()
    };
    logs.push(logEntry);
    console.log(`[${msg.type()}] ${msg.text()}`);
  });
  
  // Capture page errors
  page.on('pageerror', error => {
    errors.push(error.message);
    console.error(`[PAGE ERROR] ${error.message}`);
  });
  
  // Capture request failures
  page.on('requestfailed', request => {
    console.error(`[REQUEST FAILED] ${request.url()}: ${request.failure().errorText}`);
  });
  
  try {
    console.log('=== WebGPU Feature Test Report ===\n');
    console.log('Target URL: https://test.1ink.us/image_video_effects/index.html');
    console.log('Timestamp: ' + new Date().toISOString());
    console.log('Browser: Chromium (Headless)\n');
    
    console.log('--- Navigation ---');
    await page.goto('https://test.1ink.us/image_video_effects/index.html', {
      waitUntil: 'networkidle',
      timeout: 30000
    });
    console.log('✓ Page loaded successfully\n');
    
    // Wait for React to mount
    await page.waitForTimeout(2000);
    
    console.log('--- WebGPU Detection ---');
    const webgpuInfo = await page.evaluate(async () => {
      const info = {
        webgpuSupported: false,
        webgpuDetails: null,
        adapterInfo: null,
        error: null
      };
      
      try {
        if (!navigator.gpu) {
          info.error = 'navigator.gpu not available - WebGPU not supported';
          return info;
        }
        
        info.webgpuSupported = true;
        
        // Try to request adapter
        const adapter = await navigator.gpu.requestAdapter();
        if (!adapter) {
          info.error = 'WebGPU adapter not available (may need hardware or flags)';
          return info;
        }
        
        // Get adapter info
        if (adapter.info) {
          info.adapterInfo = {
            vendor: adapter.info.vendor,
            architecture: adapter.info.architecture,
            device: adapter.info.device,
            description: adapter.info.description
          };
        }
        
        // Try to request device
        const device = await adapter.requestDevice();
        if (device) {
          info.webgpuDetails = {
            features: Array.from(device.features || []),
            limits: device.limits ? {
              maxTextureDimension2D: device.limits.maxTextureDimension2D,
              maxComputeInvocationsPerWorkgroup: device.limits.maxComputeInvocationsPerWorkgroup,
              maxComputeWorkgroupSizeX: device.limits.maxComputeWorkgroupSizeX,
              maxComputeWorkgroupSizeY: device.limits.maxComputeWorkgroupSizeY
            } : null
          };
          device.destroy();
        }
      } catch (e) {
        info.error = e.message;
      }
      
      return info;
    });
    
    console.log('WebGPU Supported:', webgpuInfo.webgpuSupported);
    if (webgpuInfo.adapterInfo) {
      console.log('Adapter:', JSON.stringify(webgpuInfo.adapterInfo, null, 2));
    }
    if (webgpuInfo.webgpuDetails) {
      console.log('Device Features:', webgpuInfo.webgpuDetails.features.slice(0, 10).join(', ') + '...');
      console.log('Limits:', JSON.stringify(webgpuInfo.webgpuDetails.limits, null, 2));
    }
    if (webgpuInfo.error) {
      console.log('Error:', webgpuInfo.error);
    }
    console.log('');
    
    console.log('--- Shader Loading Check ---');
    const shaderCheck = await page.evaluate(async () => {
      const results = {};
      try {
        // Check if shader lists are accessible
        const lists = [
          'shader-lists/generative.json',
          'shader-lists/image.json',
          'shader-lists/liquid-effects.json'
        ];
        
        for (const list of lists) {
          try {
            const resp = await fetch(list);
            if (resp.ok) {
              const data = await resp.json();
              results[list] = { ok: true, count: Array.isArray(data) ? data.length : 0 };
            } else {
              results[list] = { ok: false, status: resp.status };
            }
          } catch (e) {
            results[list] = { ok: false, error: e.message };
          }
        }
      } catch (e) {
        results.error = e.message;
      }
      return results;
    });
    
    Object.entries(shaderCheck).forEach(([list, result]) => {
      if (result.ok) {
        console.log(`✓ ${list}: ${result.count} shaders`);
      } else {
        console.log(`✗ ${list}: ${result.status || result.error}`);
      }
    });
    console.log('');
    
    console.log('--- Console Summary ---');
    console.log(`Total console messages: ${logs.length}`);
    console.log(`Error messages: ${logs.filter(l => l.type === 'error').length}`);
    console.log(`Warning messages: ${logs.filter(l => l.type === 'warning').length}`);
    console.log(`Page errors: ${errors.length}\n`);
    
    // Take screenshot
    console.log('--- Screenshot ---');
    await page.screenshot({ path: '/root/image_video_effects/webgpu-test-result.png', fullPage: false });
    console.log('✓ Screenshot saved to webgpu-test-result.png\n');
    
    console.log('=== Test Complete ===');
    
  } catch (e) {
    console.error('Test failed:', e.message);
  } finally {
    await browser.close();
  }
})();
