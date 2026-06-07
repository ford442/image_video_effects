/**
 * Quick Shader Check - Minimal console script for fast testing
 * Paste into browser console for instant shader validation
 */

// Quick check current shader
(async function quickCheck() {
  console.log('🔍 Quick Shader Check');
  
  const errors = [];
  const origError = console.error;
  console.error = (...args) => {
    errors.push(args.join(' '));
    origError(...args);
  };
  
  // Get current shader
  const selects = document.querySelectorAll('select');
  let currentShader = null;
  
  for (const sel of selects) {
    if (sel.value && sel.options.length > 5) {
      currentShader = {
        name: sel.options[sel.selectedIndex]?.text || 'unknown',
        id: sel.value,
        category: sel.name || sel.id
      };
    }
  }
  
  console.log('Current shader:', currentShader?.name || 'none selected');
  
  // Check params
  const params = document.querySelectorAll('input[type="range"]');
  console.log(`Found ${params.length} parameter sliders`);
  
  params.forEach((p, i) => {
    const val = parseFloat(p.value);
    const min = parseFloat(p.min) || 0;
    const max = parseFloat(p.max) || 1;
    const def = p.defaultValue !== undefined ? parseFloat(p.defaultValue) : 'N/A';
    
    console.log(`  Param ${i + 1}: ${p.name || p.id || 'unnamed'}`);
    console.log(`    Value: ${val.toFixed(3)} (range: ${min}-${max}, default: ${def})`);
    console.log(`    Status: ${val >= min && val <= max ? '✅ OK' : '❌ OUT OF RANGE'}`);
  });
  
  // Wait for any async errors
  await new Promise(r => setTimeout(r, 1000));
  
  const shaderErrors = errors.filter(e => 
    e.toLowerCase().includes('shader') ||
    e.toLowerCase().includes('webgpu') ||
    e.toLowerCase().includes('compilation')
  );
  
  if (shaderErrors.length > 0) {
    console.error('❌ Shader errors detected:');
    shaderErrors.forEach(e => console.error('  →', e));
  } else {
    console.log('✅ No shader errors detected');
  }
  
  console.error = origError;
})();
