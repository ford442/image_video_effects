/**
 * Shader Test Bookmarklet
 * 
 * To use:
 * 1. Copy the entire line below (starting with javascript:)
 * 2. Create a new bookmark in your browser
 * 3. Paste the code as the URL
 * 4. Click the bookmark on the shader site
 * 
 * Minified version (copy this entire line to bookmark URL):
javascript:(function(){console.clear();console.log('%c🧪 Shader Test Starting...','font-size:18px;color:#FFD700');const errs=[];const origErr=console.error;console.error=(...a)=>{errs.push(a.join(' '));origErr(...a);};const selects=document.querySelectorAll('select');let shaders=[];for(const s of selects){if(s.options.length>5){for(const o of s.options){if(o.value&&!o.disabled){shaders.push({n:o.text.trim(),id:o.value,el:s});}}}}console.log(`Found ${shaders.length} shaders`);let passed=0,failed=0;const testNext=async(i)=>{if(i>=shaders.length){console.log('%c✅ DONE','font-size:16px;color:#44ff44');console.log(`Passed: ${passed}, Failed: ${failed}`);console.error=origErr;return;}const sh=shaders[i];const prevErrs=errs.length;sh.el.value=sh.id;sh.el.dispatchEvent(new Event('change',{bubbles:true}));await new Promise(r=>setTimeout(r,1500));const newErrs=errs.slice(prevErrs).filter(e=>/shader|webgpu|compilation|wgsl/i.test(e));if(newErrs.length>0){console.log(`%c❌ ${sh.n}`,'color:#ff4444');newErrs.forEach(e=>console.log('  →',e.substring(0,80)));failed++;}else{const params=document.querySelectorAll('input[type=range]').length;console.log(`%c✅ ${sh.n} ${params>0?'('+params+' params)':''}`,'color:#44ff44');passed++;}setTimeout(()=>testNext(i+1),500);};testNext(0);})();
 */

// Full readable version:
(function ShaderTest() {
  console.clear();
  console.log('%c🧪 Shader Test Starting...', 'font-size: 18px; color: #FFD700');
  
  // Capture errors
  const errs = [];
  const origErr = console.error;
  console.error = (...a) => {
    errs.push(a.join(' '));
    origErr(...a);
  };
  
  // Find all shaders
  const selects = document.querySelectorAll('select');
  let shaders = [];
  for (const s of selects) {
    if (s.options.length > 5) {
      for (const o of s.options) {
        if (o.value && !o.disabled) {
          shaders.push({ n: o.text.trim(), id: o.value, el: s });
        }
      }
    }
  }
  
  console.log(`Found ${shaders.length} shaders`);
  let passed = 0, failed = 0;
  
  // Test each shader
  const testNext = async (i) => {
    if (i >= shaders.length) {
      console.log('%c✅ DONE', 'font-size: 16px; color: #44ff44');
      console.log(`Passed: ${passed}, Failed: ${failed}`);
      console.error = origErr;
      return;
    }
    
    const sh = shaders[i];
    const prevErrs = errs.length;
    
    // Select shader
    sh.el.value = sh.id;
    sh.el.dispatchEvent(new Event('change', { bubbles: true }));
    
    // Wait for load
    await new Promise(r => setTimeout(r, 1500));
    
    // Check errors
    const newErrs = errs.slice(prevErrs).filter(e => 
      /shader|webgpu|compilation|wgsl/i.test(e)
    );
    
    if (newErrs.length > 0) {
      console.log(`%c❌ ${sh.n}`, 'color: #ff4444');
      newErrs.forEach(e => console.log('  →', e.substring(0, 80)));
      failed++;
    } else {
      const params = document.querySelectorAll('input[type=range]').length;
      console.log(`%c✅ ${sh.n} ${params > 0 ? '(' + params + ' params)' : ''}`, 'color: #44ff44');
      passed++;
    }
    
    // Next
    setTimeout(() => testNext(i + 1), 500);
  };
  
  testNext(0);
})();
