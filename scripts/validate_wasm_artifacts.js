#!/usr/bin/env node
/**
 * Validate WASM artifacts for Pixelocity WASM renderer
 * Checks for:
 * - Artifact file existence
 * - Reasonable file sizes
 * - WASM magic number (0x00, 0x61, 0x73, 0x6d = "\0asm")
 * - JavaScript glue exports
 */

const fs = require('fs');
const path = require('path');

const WASM_MAGIC = Buffer.from([0x00, 0x61, 0x73, 0x6d]);
const MIN_WASM_SIZE = 50 * 1024; // 50 KB minimum size
const MAX_WASM_SIZE = 200 * 1024; // 200 KB maximum (allows growth from typical ~96 KB)

// naga_wasm links the whole naga WGSL front-end + validator, so it sits an order
// of magnitude above the renderer artifact and needs its own band.
const MIN_NAGA_WASM_SIZE = 400 * 1024; // 400 KB — well under a real build, catches a stub
const MAX_NAGA_WASM_SIZE = 1500 * 1024; // 1.5 MB — allows growth from ~805 KB

const artifacts = [
  { path: 'public/wasm/pixelocity_wasm.wasm', type: 'wasm', min: MIN_WASM_SIZE, max: MAX_WASM_SIZE },
  { path: 'public/wasm/pixelocity_wasm.js', type: 'js-module', min: 10 * 1024 }, // 10 KB min
  { path: 'public/wasm/wasm_bridge.js', type: 'js-glue', min: 500 }, // 500 B min (modular barrel bridge)
  { path: 'public/wasm/naga_wasm.wasm', type: 'wasm', min: MIN_NAGA_WASM_SIZE, max: MAX_NAGA_WASM_SIZE },
  { path: 'public/wasm/naga_wasm.js', type: 'js-glue', min: 500 }, // hand-written ABI wrapper
];

const requiredExports = [
  'initWasmRenderer',
  'shutdownWasmRenderer',
  'loadShader',
  'setActiveShader',
  'setSlotShader',
  'updateUniforms',
];

let errors = [];
let warnings = [];
let allValid = true;

/**
 * Escape special regex characters in a string
 */
function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

console.log('=== WASM Artifact Validation ===\n');

// Check each artifact
artifacts.forEach(artifact => {
  const artifactPath = path.resolve(artifact.path);
  
  console.log(`Checking: ${artifact.path}`);
  
  // Check file exists
  if (!fs.existsSync(artifactPath)) {
    errors.push(`❌ ${artifact.path}: FILE NOT FOUND`);
    allValid = false;
    return;
  }
  
  const stats = fs.statSync(artifactPath);
  const sizeKB = (stats.size / 1024).toFixed(2);
  
  console.log(`  Size: ${sizeKB} KB`);
  
  // Check file size constraints
  if (artifact.min && stats.size < artifact.min) {
    errors.push(`❌ ${artifact.path}: File too small (${sizeKB} KB < ${(artifact.min / 1024).toFixed(0)} KB min)`);
    allValid = false;
  }
  
  if (artifact.max && stats.size > artifact.max) {
    errors.push(`❌ ${artifact.path}: File too large (${sizeKB} KB > ${(artifact.max / 1024).toFixed(0)} KB max)`);
    allValid = false;
  }
  
  // Check WASM magic number
  if (artifact.type === 'wasm') {
    const buffer = Buffer.alloc(4);
    const fd = fs.openSync(artifactPath, 'r');
    fs.readSync(fd, buffer, 0, 4, 0);
    fs.closeSync(fd);
    
    if (!buffer.equals(WASM_MAGIC)) {
      errors.push(`❌ ${artifact.path}: Invalid WASM magic number. Expected "\\0asm", got "${buffer.toString('hex')}"`);
      allValid = false;
    } else {
      console.log(`  WASM magic: ✅ Valid`);
    }
  }
  
  // Check JavaScript file exports
  if (artifact.type === 'js-module' || artifact.type === 'js-glue') {
    try {
      const content = fs.readFileSync(artifactPath, 'utf8');
      
      // Check for stub (Promise.resolve({}))
      if (content.includes('Promise.resolve({})')) {
        errors.push(`❌ ${artifact.path}: File is a stub (Promise.resolve({}))`);
        allValid = false;
      }
      
      // Check that the file is not empty
      if (content.trim().length === 0) {
        errors.push(`❌ ${artifact.path}: File is empty`);
        allValid = false;
      }
      
      // For js-module, check for expected exports/functions
      // Use word boundaries and regex to match actual function declarations, not just substrings
      if (artifact.type === 'js-module') {
        const missingExports = requiredExports.filter(exp => {
          // Match function declarations or exports like: function initWasmRenderer, _initWasmRenderer:, etc.
          const escapedExp = escapeRegex(exp);
          const patterns = [
            new RegExp(`\\bfunction\\s+(?:_)?${escapedExp}\\b`),
            new RegExp(`["\']${escapedExp}["\']`),
            new RegExp(`_${escapedExp}\\s*:`),
          ];
          return !patterns.some(pattern => pattern.test(content));
        });
        if (missingExports.length > 0) {
          warnings.push(`⚠️  ${artifact.path}: Missing expected exports: ${missingExports.join(', ')}`);
        } else {
          console.log(`  Exports: ✅ Found expected functions`);
        }
      }
      
      console.log(`  Content: ✅ Valid (not a stub, ${content.length} bytes)`);
    } catch (e) {
      errors.push(`❌ ${artifact.path}: Failed to read file: ${e.message}`);
      allValid = false;
    }
  }
  
  console.log('');
});

/**
 * Fail if generated wasm_renderer / public bridge copies drift from each other
 * or from src/wasm/wasm_bridge.d.ts (hand-edited contract). JS SoT is TypeScript
 * under src/wasm/; run npm run verify:wasm-bridge-sync to compare against emit.
 */
function checkBridgeSkew() {
  const pairs = [
    ['wasm_renderer/wasm_bridge.js', 'public/wasm/wasm_bridge.js'],
    ['src/wasm/wasm_bridge.d.ts', 'wasm_renderer/wasm_bridge.d.ts'],
    ['src/wasm/wasm_bridge.d.ts', 'public/wasm/wasm_bridge.d.ts'],
  ];

  const bridgeModules = [
    'api.js',
    'capture.js',
    'diagnostics.js',
    'init.js',
    'recording.js',
    'shader.js',
    'state.js',
    'uniforms.js',
    'wgslFormat.js',
  ];
  for (const name of bridgeModules) {
    pairs.push([`wasm_renderer/bridge/${name}`, `public/wasm/bridge/${name}`]);
  }

  for (const [leftRel, rightRel] of pairs) {
    const leftPath = path.resolve(leftRel);
    const rightPath = path.resolve(rightRel);

    if (!fs.existsSync(leftPath)) {
      errors.push(`❌ ${leftRel}: bridge file not found`);
      allValid = false;
      continue;
    }

    if (!fs.existsSync(rightPath)) {
      errors.push(`❌ ${rightRel}: bridge copy missing (expected sync from src/wasm via concat_bridge.sh)`);
      allValid = false;
      continue;
    }

    const left = fs.readFileSync(leftPath);
    const right = fs.readFileSync(rightPath);

    if (!left.equals(right)) {
      errors.push(
        `❌ Bridge skew detected (${leftRel} vs ${rightRel}) — run npm run wasm:build`
      );
      allValid = false;
    } else {
      console.log(`Bridge sync: ✅ ${rightRel} matches ${leftRel}`);
    }
  }

  console.log('');
}

checkBridgeSkew();

/**
 * Toolchain pin (src/contracts/wasm_compile_flags.json emsdkVersion).
 * Emscripten 6.x minified glue does not embed the emcc version, so this can only
 * fail if a version string is present and disagrees. The real gate is
 * scripts/emcc-version-gate.sh, run by build.sh before em++.
 */
function checkToolchainPin() {
  const flagsPath = path.resolve('src/contracts/wasm_compile_flags.json');
  if (!fs.existsSync(flagsPath)) {
    errors.push('❌ src/contracts/wasm_compile_flags.json: FILE NOT FOUND (toolchain pin)');
    allValid = false;
    return;
  }
  const pin = JSON.parse(fs.readFileSync(flagsPath, 'utf8')).emsdkVersion;
  if (!/^\d+\.\d+\.\d+$/.test(pin || '')) {
    errors.push(`❌ wasm_compile_flags.json: emsdkVersion must be an exact x.y.z pin, got "${pin}"`);
    allValid = false;
    return;
  }
  const gluePath = path.resolve('public/wasm/pixelocity_wasm.js');
  if (!fs.existsSync(gluePath)) return; // reported above
  const glue = fs.readFileSync(gluePath, 'utf8');
  const embedded = glue.match(/Emscripten[^\d\n]{0,40}(\d+\.\d+\.\d+)/);
  if (!embedded) {
    console.log(`Toolchain pin: emsdk ${pin} (glue embeds no emcc version — gate is scripts/emcc-version-gate.sh)`);
  } else if (embedded[1] !== pin) {
    errors.push(`❌ public/wasm/pixelocity_wasm.js: built with Emscripten ${embedded[1]}, pin is ${pin}`);
    allValid = false;
  } else {
    console.log(`Toolchain pin: ✅ glue Emscripten ${embedded[1]} matches pin`);
  }
  console.log('');
}

checkToolchainPin();

/**
 * naga_wasm staleness + pin (src/contracts/wgsl_validation.json).
 * The artifact is committed and never rebuilt in CI, so the only thing standing
 * between a Rust edit and a silently stale validator is this mtime comparison —
 * the same guard CI applies to pixelocity_wasm.wasm.
 */
function checkNagaWasm() {
  const contractPath = path.resolve('src/contracts/wgsl_validation.json');
  if (!fs.existsSync(contractPath)) {
    errors.push('❌ src/contracts/wgsl_validation.json: FILE NOT FOUND (naga_wasm pin)');
    allValid = false;
    return;
  }
  const contract = JSON.parse(fs.readFileSync(contractPath, 'utf8'));

  if (!/^\d+\.\d+$/.test(contract.nagaCratePin || '')) {
    errors.push(`❌ wgsl_validation.json: nagaCratePin must be an x.y minor pin, got "${contract.nagaCratePin}"`);
    allValid = false;
  }

  const cargoToml = path.resolve(contract.crate, 'Cargo.toml');
  if (fs.existsSync(cargoToml)) {
    const declared = fs.readFileSync(cargoToml, 'utf8').match(/naga\s*=\s*\{\s*version\s*=\s*"([^"]+)"/);
    if (!declared) {
      errors.push(`❌ ${contract.crate}/Cargo.toml: no pinned naga dependency found`);
      allValid = false;
    } else if (declared[1] !== contract.nagaCratePin) {
      errors.push(
        `❌ ${contract.crate}/Cargo.toml pins naga "${declared[1]}" but ` +
          `wgsl_validation.json nagaCratePin is "${contract.nagaCratePin}"`,
      );
      allValid = false;
    }
  }

  const artifactPath = path.resolve(contract.artifact);
  if (!fs.existsSync(artifactPath)) return; // reported by the artifact loop above

  const artifactMtime = fs.statSync(artifactPath).mtimeMs;
  const sources = [cargoToml, ...listRustSources(path.resolve(contract.crate, 'src'))].filter((p) =>
    fs.existsSync(p),
  );
  const newer = sources.filter((p) => fs.statSync(p).mtimeMs > artifactMtime);
  if (newer.length > 0) {
    errors.push(
      `❌ ${contract.artifact} is older than ${newer.map((p) => path.relative(process.cwd(), p)).join(', ')} — ` +
        `rebuild with: ${contract.rebuildCommand}`,
    );
    allValid = false;
  } else {
    console.log(`naga_wasm: ✅ artifact fresh, naga pinned to ${contract.nagaCratePin}`);
  }
  console.log('');
}

function listRustSources(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .flatMap((e) =>
      e.isDirectory() ? listRustSources(path.join(dir, e.name)) : e.name.endsWith('.rs') ? [path.join(dir, e.name)] : [],
    );
}

checkNagaWasm();

// Summary
console.log('=== Validation Summary ===\n');

if (errors.length > 0) {
  console.log('ERRORS:');
  errors.forEach(err => console.log(err));
  console.log('');
}

if (warnings.length > 0) {
  console.log('WARNINGS:');
  warnings.forEach(warn => console.log(warn));
  console.log('');
}

if (allValid && errors.length === 0) {
  console.log('✅ All WASM artifacts are valid!');
  process.exit(0);
} else {
  console.log('❌ WASM artifact validation failed!');
  process.exit(1);
}
