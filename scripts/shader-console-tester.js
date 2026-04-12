/**
 * Shader Console Tester - Paste this into browser console on the site
 * Tests all shaders for compilation errors and parameter functionality
 * 
 * Usage:
 * 1. Open https://test.1ink.us/image_video_effects/index.html
 * 2. Open browser DevTools (F12)
 * 3. Paste this entire script into Console
 * 4. Press Enter to run
 * 5. Wait for results (takes ~2-5 minutes for all shaders)
 */

(function ShaderTester() {
  console.log('%c🔬 Shader Console Tester', 'font-size: 20px; font-weight: bold; color: #FFD700;');
  console.log('%cStarting comprehensive shader validation...', 'color: #aaa');
  
  const results = {
    passed: [],
    failed: [],
    skipped: [],
    startTime: Date.now()
  };

  // Collect all shaders from dropdowns
  function getAllShaders() {
    const shaders = [];
    const selects = document.querySelectorAll('select');
    
    for (const select of selects) {
      if (select.options.length > 5) {
        const category = select.name || select.id || select.className || 'unknown';
        for (const option of select.options) {
          if (option.value && option.text && !option.value.includes('placeholder')) {
            shaders.push({
              id: option.value,
              name: option.text.trim(),
              category: category,
              element: select
            });
          }
        }
      }
    }
    
    // Remove duplicates
    return shaders.filter((s, i, arr) => 
      arr.findIndex(t => t.id === s.id) === i
    );
  }

  // Test a single shader
  async function testShader(shader, index, total) {
    const prefix = `[${index + 1}/${total}]`;
    
    try {
      // Clear WebGPU errors
      const previousErrors = [...consoleErrors];
      
      // Select the shader
      shader.element.value = shader.id;
      shader.element.dispatchEvent(new Event('change', { bubbles: true }));
      
      // Wait for compilation
      await new Promise(r => setTimeout(r, 1500));
      
      // Check for new errors
      const newErrors = consoleErrors.filter(e => !previousErrors.includes(e));
      const shaderErrors = newErrors.filter(e => 
        e.toLowerCase().includes('shader') ||
        e.toLowerCase().includes('webgpu') ||
        e.toLowerCase().includes('pipeline') ||
        e.toLowerCase().includes('compilation') ||
        e.toLowerCase().includes('wgsl')
      );
      
      if (shaderErrors.length > 0) {
        results.failed.push({
          name: shader.name,
          category: shader.category,
          id: shader.id,
          errors: shaderErrors
        });
        console.log(`%c${prefix} ❌ FAIL: ${shader.name}`, 'color: #ff4444');
        shaderErrors.forEach(e => console.log('   →', e.substring(0, 100)));
        return { status: 'fail', errors: shaderErrors };
      }
      
      // Check parameters
      const params = document.querySelectorAll('input[type="range"]');
      const paramInfo = Array.from(params).map(p => ({
        name: p.name || p.id || 'unnamed',
        value: parseFloat(p.value),
        min: parseFloat(p.min) || 0,
        max: parseFloat(p.max) || 1,
        defaultValue: p.defaultValue
      }));
      
      // Test parameter setting
      let paramsWork = true;
      for (const param of params) {
        const originalValue = param.value;
        const min = parseFloat(param.min) || 0;
        const max = parseFloat(param.max) || 1;
        const testValue = min + (max - min) * 0.75;
        
        param.value = testValue;
        param.dispatchEvent(new Event('input', { bubbles: true }));
        
        if (Math.abs(parseFloat(param.value) - testValue) > 0.01) {
          paramsWork = false;
        }
        
        // Restore original
        param.value = originalValue;
        param.dispatchEvent(new Event('input', { bubbles: true }));
      }
      
      results.passed.push({
        name: shader.name,
        category: shader.category,
        params: paramInfo.length,
        paramsWork: paramsWork
      });
      
      const paramStr = paramInfo.length > 0 
        ? `(${paramInfo.length} params${paramsWork ? ' ✅' : ' ⚠️'})`
        : '(no params)';
      
      console.log(`%c${prefix} ✅ PASS: ${shader.name} ${paramStr}`, 'color: #44ff44');
      
      return { status: 'pass', params: paramInfo.length };
      
    } catch (err) {
      results.failed.push({
        name: shader.name,
        category: shader.category,
        error: err.message
      });
      console.log(`%c${prefix} ❌ ERROR: ${shader.name} - ${err.message}`, 'color: #ff4444');
      return { status: 'error', message: err.message };
    }
  }

  // Store console errors
  const consoleErrors = [];
  const originalError = console.error;
  console.error = function(...args) {
    consoleErrors.push(args.join(' '));
    originalError.apply(console, args);
  };

  // Main test runner
  async function runTests() {
    const shaders = getAllShaders();
    console.log(`\n📋 Found ${shaders.length} shaders to test\n`);
    
    if (shaders.length === 0) {
      console.error('❌ No shaders found! Make sure the page is fully loaded.');
      return;
    }
    
    // Test in batches to avoid overwhelming the GPU
    const batchSize = 5;
    for (let i = 0; i < shaders.length; i += batchSize) {
      const batch = shaders.slice(i, i + batchSize);
      
      for (let j = 0; j < batch.length; j++) {
        await testShader(batch[j], i + j, shaders.length);
      }
      
      // Brief pause between batches
      if (i + batchSize < shaders.length) {
        await new Promise(r => setTimeout(r, 500));
      }
    }
    
    // Print summary
    const duration = ((Date.now() - results.startTime) / 1000).toFixed(1);
    
    console.log('\n' + '='.repeat(60));
    console.log('%c📊 TEST SUMMARY', 'font-size: 16px; font-weight: bold; color: #FFD700;');
    console.log('='.repeat(60));
    console.log(`Total shaders: ${shaders.length}`);
    console.log(`%c✅ Passed: ${results.passed.length}`, 'color: #44ff44');
    console.log(`%c❌ Failed: ${results.failed.length}`, 'color: #ff4444');
    console.log(`Duration: ${duration}s`);
    console.log('='.repeat(60));
    
    if (results.failed.length > 0) {
      console.log('\n%c❌ FAILED SHADERS:', 'font-weight: bold; color: #ff4444;');
      results.failed.forEach((f, i) => {
        console.log(`\n${i + 1}. ${f.name}`);
        console.log(`   Category: ${f.category}`);
        if (f.errors) {
          f.errors.forEach(e => console.log(`   Error: ${e.substring(0, 120)}`));
        }
        if (f.error) {
          console.log(`   Error: ${f.error}`);
        }
      });
    }
    
    // Create downloadable report
    const report = {
      timestamp: new Date().toISOString(),
      url: window.location.href,
      userAgent: navigator.userAgent,
      webgpuSupported: !!navigator.gpu,
      summary: {
        total: shaders.length,
        passed: results.passed.length,
        failed: results.failed.length
      },
      results
    };
    
    const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    console.log('\n' + '='.repeat(60));
    console.log('💾 Report ready for download');
    console.log('Right-click and save this link: ' + url);
    console.log('Or copy the report object:');
    console.log('window.shaderTestReport');
    
    // Expose report globally
    window.shaderTestReport = report;
    
    // Restore console
    console.error = originalError;
    
    return results;
  }

  // Run the tests
  return runTests();
})();
