# Shader Testing Tools

A collection of tools to validate WebGPU shaders on your deployed site, checking for compilation errors and parameter functionality.

---

## 🚀 Quick Start

### Option 1: Browser Console (Fastest - No Install)

1. Open your site: https://test.1ink.us/image_video_effects/index.html
2. Press `F12` to open DevTools
3. Go to the **Console** tab
4. Paste one of the scripts below and press Enter

**Quick Check Current Shader:**
```javascript
// Copy everything below and paste in console
(async function quickCheck() {
  console.log('🔍 Quick Shader Check');
  const errors = [];
  const origError = console.error;
  console.error = (...args) => { errors.push(args.join(' ')); origError(...args); };
  
  await new Promise(r => setTimeout(r, 1000));
  
  const shaderErrors = errors.filter(e => 
    e.toLowerCase().includes('shader') || 
    e.toLowerCase().includes('webgpu') ||
    e.toLowerCase().includes('compilation')
  );
  
  const params = document.querySelectorAll('input[type="range"]');
  console.log(`Found ${params.length} parameter sliders`);
  params.forEach((p, i) => {
    const val = parseFloat(p.value);
    const min = parseFloat(p.min) || 0;
    const max = parseFloat(p.max) || 1;
    console.log(`  ${p.name || p.id || 'param' + i}: ${val.toFixed(2)} [${min}-${max}] ${val >= min && val <= max ? '✅' : '❌'}`);
  });
  
  if (shaderErrors.length > 0) {
    console.error('❌ Shader errors:', shaderErrors);
  } else {
    console.log('✅ No shader errors detected');
  }
  console.error = origError;
})();
```

**Full Test (All Shaders):**
```javascript
// Copy the contents of scripts/shader-console-tester.js
// and paste into console
```

---

### Option 2: Python Script (Most Reliable)

Requires Python 3.8+ and Playwright.

**Installation:**
```bash
cd /root/image_video_effects

# Install dependencies
pip install playwright
playwright install chromium

# Make script executable
chmod +x scripts/shader_test_runner.py
```

**Run Tests:**
```bash
# Test all shaders
python scripts/shader_test_runner.py

# Test specific URL
python scripts/shader_test_runner.py https://test.1ink.us/image_video_effects/index.html

# Test with visible browser (for debugging)
python scripts/shader_test_runner.py --headful

# Test only 20 shaders (quick smoke test)
python scripts/shader_test_runner.py --sample 20
```

**Output:**
- Console report with pass/fail status
- Detailed JSON report saved to `scripts/shader-test-report.json`

---

### Option 3: Node.js Script

**Installation:**
```bash
cd /root/image_video_effects
npm install playwright
npx playwright install chromium
```

**Run Tests:**
```bash
node scripts/shader-validator.js

# Or with custom URL
node scripts/shader-validator.js https://test.1ink.us/image_video_effects/index.html
```

---

## 📊 What Gets Tested

### 1. Shader Compilation
- WebGPU pipeline creation
- WGSL syntax validation
- Bind group compatibility
- Runtime errors

### 2. Parameter Sliders
- Presence of controls
- Value ranges (min/max)
- Default values
- Slider responsiveness
- Value persistence

### 3. Categories Covered
All shader categories are tested:
- `image` - Image processing effects
- `generative` - Procedural shaders
- `interactive-mouse` - Mouse-driven effects
- `distortion` - Warp/distortion effects
- `retro-glitch` - VHS/glitch effects
- `lighting-effects` - Glow/plasma
- `simulation` - Physics/CA
- `artistic` - Creative effects

---

## 📁 File Reference

| File | Purpose | Best For |
|------|---------|----------|
| `scripts/shader_test_runner.py` | Full Python test suite | CI/CD, comprehensive testing |
| `scripts/shader-validator.js` | Node.js test suite | JavaScript environments |
| `scripts/shader-console-tester.js` | Browser console script | Quick manual testing |
| `scripts/quick-shader-check.js` | Minimal console check | Instant validation |

---

## 🔧 Interpreting Results

### Status Codes

| Icon | Status | Meaning |
|------|--------|---------|
| ✅ | PASS | Shader loads and params work |
| ❌ | FAIL | Compilation errors or crashes |
| ⚠️ | SKIP | Could not test (selection failed) |

### Common Errors

**`WebGPU pipeline creation failed`**
- WGSL syntax error in shader
- Missing bindings or uniforms
- Workgroup size mismatch

**`Shader compilation error`**
- Invalid WGSL code
- Reserved keyword usage
- Type mismatch

**`Parameter slider out of range`**
- Default value outside min/max bounds
- Slider not properly initialized

---

## 🐛 Debugging Failed Shaders

### Step 1: Check Console Errors
```javascript
// In browser console, check for errors
consoleErrors.filter(e => e.includes('shader'))
```

### Step 2: Test Shader Directly
```javascript
// Load specific shader and watch console
const select = document.querySelector('select[name="shader"]');
select.value = 'your-shader-id';
select.dispatchEvent(new Event('change'));
```

### Step 3: Check Shader File
```bash
# Validate WGSL syntax locally
cat public/shaders/your-shader.wgsl | head -50

# Check for common issues:
# - @workgroup_size(8, 8, 1) - correct size
# - fn main(@builtin(global_invocation_id) global_id: vec3<u32>) - correct signature
# - textureStore(writeTexture, ...) - output present
```

---

## 📈 Sample Report

```json
{
  "url": "https://test.1ink.us/image_video_effects/index.html",
  "timestamp": "2026-04-12 10:30:00",
  "duration_seconds": 145.2,
  "webgpu_supported": true,
  "summary": {
    "total": 50,
    "passed": 47,
    "failed": 2,
    "skipped": 1
  },
  "results": [
    {
      "name": "Liquid Ripple",
      "id": "liquid",
      "category": "image",
      "status": "pass",
      "params": 4,
      "params_work": true
    },
    {
      "name": "Broken Shader",
      "id": "broken",
      "category": "generative",
      "status": "fail",
      "errors": ["WGSL compilation failed: unexpected token"]
    }
  ]
}
```

---

## 🔒 Security Notes

- Scripts run locally in your browser
- No data is sent to external servers
- Reports are saved locally only
- WebGPU access is read-only for testing

---

## 💡 Tips

1. **Quick Smoke Test**: Use `--sample 20` to test a subset quickly
2. **Visual Debugging**: Use `--headful` to see the browser during testing
3. **CI Integration**: Python script returns exit code 1 on failures
4. **Batch Testing**: Run nightly with `cron` to catch regressions

---

## 🆘 Troubleshooting

### Playwright Installation Issues
```bash
# If playwright install fails, try:
pip install --upgrade pip
pip install playwright --force-reinstall
python -m playwright install chromium
```

### WebGPU Not Available
- Ensure you're using Chrome/Edge 113+ or Firefox Nightly
- Enable flags: `--enable-webgpu --enable-features=Vulkan`
- Check GPU compatibility

### Timeout Errors
- Increase `shaderTimeout` in scripts
- Check network connectivity to test URL
- Reduce `--sample` size for faster testing
