#!/usr/bin/env node
/**
 * verify-device-policy-sync.js
 *
 * CI check: webgpu_limits.json ↔ TS policy ↔ device.cpp CheckLimit/requiredLimits;
 * optional feature order ↔ device.ts / device.cpp; wasm_exports.json ↔ KEEPALIVE /
 * build.sh / CMakeLists (no hardcoded export lists);
 * workgroup_dispatch.json ↔ ShaderCompilation.ts ↔ wasm_internal.cpp ParseWorkgroupSize.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const CONTRACT = path.join(ROOT, 'src/contracts/webgpu_limits.json');
const TS_POLICY = path.join(ROOT, 'src/renderer/webgpuDevicePolicy.ts');
const CPP_DEVICE = path.join(ROOT, 'wasm_renderer/device.cpp');

const contract = JSON.parse(fs.readFileSync(CONTRACT, 'utf8'));
const EXPECTED_LIMITS = contract.minimumComputeLimits;

function extractTsLimits() {
  const src = fs.readFileSync(TS_POLICY, 'utf8');
  const usesContractSpread = /\.\.\.webgpuLimitsContract\.minimumComputeLimits/.test(src);
  const out = {};

  if (usesContractSpread) {
    Object.assign(out, EXPECTED_LIMITS);
    const uniformOverride = src.match(/maxUniformBufferBindingSize:\s*UNIFORM_BUFFER_LAYOUT\.TOTAL_SIZE/);
    if (!uniformOverride) {
      throw new Error('Expected maxUniformBufferBindingSize: UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE in TS policy');
    }
    const typesSrc = fs.readFileSync(path.join(ROOT, 'src/renderer/types.ts'), 'utf8');
    const totalSize = typesSrc.match(/TOTAL_SIZE:\s*(\d+)/);
    if (!totalSize) throw new Error('UNIFORM_BUFFER_LAYOUT.TOTAL_SIZE not found in types.ts');
    out.maxUniformBufferBindingSize = parseInt(totalSize[1], 10);
    return out;
  }

  const block = src.match(/MINIMUM_COMPUTE_LIMITS\s*=\s*\{([^}]+)\}/s);
  if (!block) throw new Error('MINIMUM_COMPUTE_LIMITS not found in TS policy');
  for (const key of Object.keys(EXPECTED_LIMITS)) {
    const m = block[1].match(new RegExp(`${key}:\\s*(\\d+)`));
    if (!m) throw new Error(`Missing ${key} in TS MINIMUM_COMPUTE_LIMITS`);
    out[key] = parseInt(m[1], 10);
  }
  return out;
}

function extractCppRequiredLimits() {
  const src = fs.readFileSync(CPP_DEVICE, 'utf8');
  const out = {};
  for (const key of Object.keys(EXPECTED_LIMITS)) {
    if (key === 'maxUniformBufferBindingSize') {
      if (!/requiredLimits\.maxUniformBufferBindingSize\s*=\s*sizeof\(Uniforms\)/.test(src)) {
        throw new Error('requiredLimits.maxUniformBufferBindingSize = sizeof(Uniforms) not found in device.cpp');
      }
      out[key] = EXPECTED_LIMITS[key];
      continue;
    }
    const m = src.match(new RegExp(`requiredLimits\\.${key}\\s*=\\s*(\\d+)`));
    if (!m) throw new Error(`requiredLimits.${key} not found in device.cpp`);
    out[key] = parseInt(m[1], 10);
  }
  return out;
}

function extractCppCheckLimits() {
  const src = fs.readFileSync(CPP_DEVICE, 'utf8');
  const adapterBlock = src.match(
    /Adapter limits \(validating against 14-entry compute contract\):[\s\S]*?maxComputeInvocationsPerWorkgroup,\s*(\d+)/,
  );
  if (!adapterBlock) {
    throw new Error('Adapter CheckLimit block not found in device.cpp');
  }
  const block = adapterBlock[0];
  const out = {};
  for (const [key, expected] of Object.entries(EXPECTED_LIMITS)) {
    if (key === 'maxUniformBufferBindingSize') {
      // CheckLimit table validates compute limits only; uniform size is in requiredLimits
      out[key] = expected;
      continue;
    }
    const m = block.match(
      new RegExp(`CheckLimit\\("${key}",\\s*limits\\.${key},\\s*(\\d+)`),
    );
    if (!m) throw new Error(`CheckLimit("${key}", ...) not found in adapter block`);
    out[key] = parseInt(m[1], 10);
    if (out[key] !== expected) {
      throw new Error(`CheckLimit ${key} need=${m[1]} does not match contract ${expected}`);
    }
  }
  return out;
}

const ts = extractTsLimits();
const cppRequired = extractCppRequiredLimits();
const cppCheck = extractCppCheckLimits();
let failed = false;

for (const [key, expected] of Object.entries(EXPECTED_LIMITS)) {
  if (ts[key] !== expected) {
    console.error(`TS ${key}: expected ${expected}, got ${ts[key]}`);
    failed = true;
  }
  if (cppRequired[key] !== expected) {
    console.error(`C++ requiredLimits.${key}: expected ${expected}, got ${cppRequired[key]}`);
    failed = true;
  }
  if (cppCheck[key] !== expected && key !== 'maxUniformBufferBindingSize') {
    console.error(`C++ CheckLimit ${key}: expected ${expected}, got ${cppCheck[key]}`);
    failed = true;
  }
}

function fail(msg) {
  console.error(msg);
  failed = true;
}

function verifyOptionalFeatures() {
  const feat = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'src/contracts/webgpu_optional_features.json'), 'utf8'),
  );
  const tsDevice = fs.readFileSync(path.join(ROOT, 'src/renderer/webgpu/device.ts'), 'utf8');
  const fn = tsDevice.match(
    /export function collectOptionalDeviceFeatures\([\s\S]*?\n\}/,
  );
  if (!fn) {
    fail('collectOptionalDeviceFeatures not found in device.ts');
    return;
  }
  const body = fn[0];
  const i32 = body.indexOf("'float32-filterable'");
  const iTs = body.indexOf("'timestamp-query'");
  const iSg = body.indexOf('resolveSubgroupFeatureName');
  if (i32 < 0 || iTs < 0 || iSg < 0) {
    fail('device.ts collectOptionalDeviceFeatures missing float32 / timestamp-query / resolveSubgroupFeatureName');
  } else if (!(i32 < iTs && iTs < iSg)) {
    fail('device.ts collectOptionalDeviceFeatures order must be float32 → timestamp-query → subgroups');
  }
  if (!feat.timestampQueryAlwaysOnWhenAvailable) {
    fail('webgpu_optional_features.json must keep timestampQueryAlwaysOnWhenAvailable true (#1007)');
  }

  const cpp = fs.readFileSync(CPP_DEVICE, 'utf8');
  const arr = cpp.match(/WGPUFeatureName requiredFeatures\[(\d+)\]/);
  if (!arr || parseInt(arr[1], 10) < feat.requiredFeaturesArrayMin) {
    fail(
      `device.cpp requiredFeatures[] must be >= ${feat.requiredFeaturesArrayMin} (got ${arr ? arr[1] : 'missing'})`,
    );
  }
  const optBlock = cpp.match(/Optional features:[\s\S]*?deviceDesc\.requiredFeatureCount/);
  if (!optBlock) {
    fail('device.cpp optional-features request block not found');
    return;
  }
  const block = optBlock[0];
  const pF32 = block.indexOf('WGPUFeatureName_Float32Filterable');
  const pTs = block.indexOf('WGPUFeatureName_TimestampQuery');
  const pSg = block.indexOf('WGPUFeatureName_Subgroups');
  if (pF32 < 0 || pTs < 0 || pSg < 0) {
    fail('device.cpp must request Float32Filterable, TimestampQuery, and Subgroups');
  } else if (!(pF32 < pTs && pTs < pSg)) {
    fail('device.cpp feature request order must be float32 → timestamp-query → subgroups');
  }
  if (pSg >= 0 && pTs >= 0 && pSg < pTs) {
    fail('device.cpp must not request subgroups before timestamp-query');
  }

  const scanner = path.join(ROOT, 'src/utils/requestPixelocityDevice.ts');
  if (fs.existsSync(scanner)) {
    const src = fs.readFileSync(scanner, 'utf8');
    if (!src.includes('collectOptionalDeviceFeatures')) {
      fail(
        'requestPixelocityDevice.ts must call collectOptionalDeviceFeatures (timestamp-query always-on when available)',
      );
    }
  }
}

function verifyWasmExports() {
  const json = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'src/contracts/wasm_exports.json'), 'utf8'),
  );
  const runtimeOnly = new Set(json.runtimeOnlyExports || ['_main', '_malloc', '_free']);
  const jsonKeep = new Set(
    json.exportedFunctions.filter((n) => !runtimeOnly.has(n)),
  );

  const mainCpp = fs.readFileSync(path.join(ROOT, 'wasm_renderer/main.cpp'), 'utf8');
  const keepalive = new Set();
  const re = /EMSCRIPTEN_KEEPALIVE[\s\S]*?\n[\w\s\*]+\s+(\w+)\s*\(/g;
  let m;
  while ((m = re.exec(mainCpp))) {
    keepalive.add(`_${m[1]}`);
  }
  for (const name of jsonKeep) {
    if (!keepalive.has(name)) fail(`wasm_exports.json has ${name} but main.cpp has no matching KEEPALIVE`);
  }
  for (const name of keepalive) {
    if (!jsonKeep.has(name)) fail(`main.cpp KEEPALIVE ${name} missing from wasm_exports.json`);
  }

  const buildSh = fs.readFileSync(path.join(ROOT, 'wasm_renderer/build.sh'), 'utf8');
  const cmake = fs.readFileSync(path.join(ROOT, 'wasm_renderer/CMakeLists.txt'), 'utf8');
  if (/_initWasmRenderer,_shutdownWasmRenderer/.test(buildSh)) {
    fail('build.sh must not hardcode EXPORTED_FUNCTIONS; use format-wasm-exports.js');
  }
  if (!buildSh.includes('format-wasm-exports.js')) {
    fail('build.sh must invoke scripts/format-wasm-exports.js');
  }
  if (/_initWasmRenderer,_shutdownWasmRenderer/.test(cmake)) {
    fail('CMakeLists.txt must not hardcode EXPORTED_FUNCTIONS; read wasm_exports.json');
  }
  if (!cmake.includes('wasm_exports.json')) {
    fail('CMakeLists.txt must file(READ) src/contracts/wasm_exports.json');
  }
  if (!cmake.includes('GROWABLE_ARRAYBUFFERS=0')) {
    fail('CMakeLists.txt must set -sGROWABLE_ARRAYBUFFERS=0 to match build.sh');
  }
}

function verifyWorkgroupDispatch() {
  const wgContract = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'src/contracts/workgroup_dispatch.json'), 'utf8'),
  );
  const fallback = wgContract.unparsedFallback;
  if (!fallback || fallback.x !== 16 || fallback.y !== 16) {
    fail('workgroup_dispatch.json unparsedFallback must be { x: 16, y: 16 }');
  }

  const tsShader = fs.readFileSync(
    path.join(ROOT, 'src/renderer/ShaderCompilation.ts'),
    'utf8',
  );
  if (!tsShader.includes("from '../contracts/workgroup_dispatch.json'")) {
    fail('ShaderCompilation.ts must import workgroup_dispatch.json');
  }
  if (!tsShader.includes('workgroupDispatchContract.unparsedFallback.x')) {
    fail('ShaderCompilation.ts unparsed fallback must use workgroupDispatchContract.unparsedFallback.x');
  }
  if (!tsShader.includes('workgroupDispatchContract.unparsedFallback.y')) {
    fail('ShaderCompilation.ts unparsed fallback must use workgroupDispatchContract.unparsedFallback.y');
  }
  if (/\breturn\s*\{\s*x:\s*8\s*,\s*y:\s*8\s*\}/.test(tsShader)) {
    fail('ShaderCompilation.ts must not return hardcoded 8x8 unparsed fallback');
  }

  const cppInternal = fs.readFileSync(
    path.join(ROOT, wgContract.cppReferences.file),
    'utf8',
  );
  const fnBlock = cppInternal.match(
    /void ParseWorkgroupSize\([\s\S]*?\n\}/,
  );
  if (!fnBlock) {
    fail('ParseWorkgroupSize not found in wasm_internal.cpp');
    return;
  }
  const init = fnBlock[0].match(/x\s*=\s*(\d+);\s*\n\s*y\s*=\s*(\d+);/);
  if (!init) {
    fail('ParseWorkgroupSize default x/y assignment not found in wasm_internal.cpp');
  } else {
    const cppX = parseInt(init[1], 10);
    const cppY = parseInt(init[2], 10);
    if (cppX !== fallback.x || cppY !== fallback.y) {
      fail(
        `wasm_internal.cpp ParseWorkgroupSize default: expected ${fallback.x}x${fallback.y}, got ${cppX}x${cppY}`,
      );
    }
  }

  const shadersDir = path.join(ROOT, 'public/shaders');
  const forbidden = /@compute\s+@workgroup_size\(\s*8\s*,\s*8/;
  for (const name of fs.readdirSync(shadersDir)) {
    if (!name.endsWith('.wgsl')) continue;
    const content = fs.readFileSync(path.join(shadersDir, name), 'utf8');
    if (forbidden.test(content)) {
      fail(`public/shaders/${name} still declares @workgroup_size(8, 8, …); use canonical 16x16`);
    }
  }
}

verifyOptionalFeatures();
verifyWasmExports();
verifyWorkgroupDispatch();

if (failed) {
  process.exit(1);
}

console.log(
  '✅ Device policy sync OK (limits + optional features + wasm_exports + workgroup_dispatch ↔ TS/C++/shaders)',
);
