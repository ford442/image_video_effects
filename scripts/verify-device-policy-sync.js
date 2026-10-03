#!/usr/bin/env node
/**
 * verify-device-policy-sync.js
 *
 * CI check: webgpu_limits.json ↔ TS policy ↔ device.cpp CheckLimit/requiredLimits;
 * optional feature order ↔ device.ts / device.cpp;
 * slot_limits.json ↔ PHYSICAL_SLOT_LIMIT / MAX_SHADER_SLOTS;
 * canvas_configure.json ↔ buildCanvasConfigureOptions / JS_CreateSurfaceFromCanvas / ConfigureSurface; wasm_exports.json ↔ KEEPALIVE /
 * build.sh / CMakeLists (no hardcoded export lists);
 * workgroup_dispatch.json ↔ ShaderCompilation.ts ↔ wasm_internal.cpp ParseWorkgroupSize;
 * emptyPlaceholder (r32float 1×1, 4 B/row) ↔ resources.ts emptyTex ↔ resources.cpp emptyTexture_;
 * bind_group1.json ↔ simRing.ts layout ↔ group-1 limits policy ↔ WASM group-1 refusal.
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

const ONLY_WASM_INVARIANTS = process.argv.includes('--wasm-invariants');

let failed = false;

if (!ONLY_WASM_INVARIANTS) {
  const ts = extractTsLimits();
  const cppRequired = extractCppRequiredLimits();
  const cppCheck = extractCppCheckLimits();

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
}

function fail(msg) {
  console.error(msg);
  failed = true;
}

// deepWorkgroupLimits: requested only when the adapter offers all three. Both
// C++ (adapterDeepWorkgroup threshold + requiredLimits block) and TS
// (buildRequiredLimits spreading the contract block) must mirror the JSON.
function verifyDeepWorkgroupLimits() {
  const deep = contract.deepWorkgroupLimits;
  if (!deep) return;
  const cpp = fs.readFileSync(CPP_DEVICE, 'utf8');
  const gate = cpp.match(/const bool adapterDeepWorkgroup\s*=([^;]+);/);
  const block = cpp.match(/if \(adapterDeepWorkgroup\) \{([^}]+)\}/);
  if (!gate) fail('device.cpp: const bool adapterDeepWorkgroup = ... not found (deepWorkgroupLimits)');
  if (!block) fail('device.cpp: if (adapterDeepWorkgroup) { requiredLimits... } not found (deepWorkgroupLimits)');
  for (const [key, value] of Object.entries(deep)) {
    if (gate && !new RegExp(`limits\\.${key}\\s*>=\\s*${value}\\b`).test(gate[1])) {
      fail(`device.cpp adapterDeepWorkgroup must test limits.${key} >= ${value} (webgpu_limits.json deepWorkgroupLimits)`);
    }
    if (block && !new RegExp(`requiredLimits\\.${key}\\s*=\\s*${value}\\s*;`).test(block[1])) {
      fail(`device.cpp deep requiredLimits.${key} must be ${value} (webgpu_limits.json deepWorkgroupLimits)`);
    }
  }
  const ts = fs.readFileSync(TS_POLICY, 'utf8');
  if (!/webgpuLimitsContract\.deepWorkgroupLimits/.test(ts)
      || !/meetsDeepWorkgroupLimits\(adapterLimits\)\s*\?\s*DEEP_WORKGROUP_LIMITS/.test(ts)) {
    fail('webgpuDevicePolicy.ts buildRequiredLimits must spread webgpuLimitsContract.deepWorkgroupLimits when meetsDeepWorkgroupLimits(adapterLimits)');
  }
}

if (!ONLY_WASM_INVARIANTS) {
  verifyDeepWorkgroupLimits();
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

function verifyCanvasConfigure() {
  const file = 'src/contracts/canvas_configure.json';
  const c = JSON.parse(fs.readFileSync(path.join(ROOT, file), 'utf8'));

  // Conservative v1 defaults. Changing any of these is a product decision, not drift.
  const defaults = {
    alphaMode: 'opaque',
    presentModeWasm: 'fifo',
    colorSpace: 'srgb',
    toneMapping: 'standard',
  };
  for (const [key, expected] of Object.entries(defaults)) {
    if (c[key] !== expected) fail(`${file} ${key} must be '${expected}' (got ${JSON.stringify(c[key])})`);
  }
  if (JSON.stringify(c.usage) !== JSON.stringify(['RENDER_ATTACHMENT'])) {
    fail(`${file} default usage must be ["RENDER_ATTACHMENT"] (COPY_SRC is opt-in only)`);
  }
  const copyUsage = c.optIn?.copySrc?.usage || [];
  if (!copyUsage.includes('RENDER_ATTACHMENT') || !copyUsage.includes('COPY_SRC')) {
    fail(`${file} optIn.copySrc.usage must be RENDER_ATTACHMENT + COPY_SRC`);
  }
  if (c.optIn?.displayP3?.colorSpace !== 'display-p3') {
    fail(`${file} optIn.displayP3.colorSpace must be 'display-p3'`);
  }
  if (c.optIn?.extendedToneMapping?.toneMappingMode !== 'extended') {
    fail(`${file} optIn.extendedToneMapping.toneMappingMode must be 'extended'`);
  }

  // ── TS: buildCanvasConfigureOptions reads the contract ───────────────────
  const tsFile = 'src/renderer/webgpu/device.ts';
  const ts = fs.readFileSync(path.join(ROOT, tsFile), 'utf8');
  if (!/import canvasConfigureContract from '\.\.\/\.\.\/contracts\/canvas_configure\.json'/.test(ts)) {
    fail(`${tsFile} must import canvasConfigureContract from contracts/canvas_configure.json`);
  }
  const build = ts.match(/export function buildCanvasConfigureOptions\([\s\S]*?\n\}/);
  if (!build) {
    fail(`${tsFile} buildCanvasConfigureOptions not found`);
  } else {
    const body = build[0];
    if (!body.includes('canvasConfigureContract.alphaMode')) {
      fail(`${tsFile} buildCanvasConfigureOptions must take alphaMode from the contract`);
    }
    if (!body.includes('canvasConfigureContract.usage') || !body.includes('canvasConfigureContract.optIn.copySrc.usage')) {
      fail(`${tsFile} buildCanvasConfigureOptions must take usage (default + copySrc) from the contract`);
    }
    if (/presentMode/.test(body)) {
      fail(`${tsFile} buildCanvasConfigureOptions must not set a presentMode (browser-owned in TS)`);
    }
    const guard = body.indexOf('if (optIns.displayP3)');
    const color = body.indexOf('config.colorSpace');
    const tone = body.indexOf('toneMapping =');
    if (guard < 0 || color < guard || tone < guard) {
      fail(`${tsFile} colorSpace / toneMapping must only be set inside the optIns.displayP3 branch`);
    }
    if (/format:\s*['"]/.test(body)) {
      fail(`${tsFile} buildCanvasConfigureOptions must not hardcode a canvas format`);
    }
  }

  const probeFile = 'src/renderer/webgpuBootProbe.ts';
  const probe = fs.readFileSync(path.join(ROOT, probeFile), 'utf8');
  if (!probe.includes('context.configure(buildCanvasConfigureOptions(device, canvasFormat))')) {
    fail(`${probeFile} must configure the default contract first (buildCanvasConfigureOptions(device, canvasFormat))`);
  }
  if (!/probeCanvasCopySrc\(device, context, canvasFormat/.test(probe) || !/\n\s*canvasCopySrc,\n/.test(probe)) {
    fail(`${probeFile} must run probeCanvasCopySrc and publish ${c.optIn.copySrc.probeFlag} on window.webgpuProbe`);
  }

  // ── C++: JS_CreateSurfaceFromCanvas + ConfigureSurface ──────────────────
  const cpp = fs.readFileSync(CPP_DEVICE, 'utf8');
  const jsFn = cpp.match(new RegExp(`EM_JS\\([^,]+,\\s*${c.cpp.jsConfigureFunction}[\\s\\S]*?\\n\\}\\);`));
  const jsCfg = jsFn && jsFn[0].match(/ctx\.configure\(\{([\s\S]*?)\}\)/);
  if (!jsCfg) {
    fail(`device.cpp ${c.cpp.jsConfigureFunction} ctx.configure({...}) not found`);
  } else {
    const body = jsCfg[1];
    if (!new RegExp(`alphaMode:\\s*'${c.alphaMode}'`).test(body)) {
      fail(`device.cpp ${c.cpp.jsConfigureFunction} alphaMode must be '${c.alphaMode}'`);
    }
    const usage = body.match(/usage:\s*([^,\n}]+)/);
    const jsUsage = usage
      ? usage[1].split('|').map((u) => u.trim().replace(/^GPUTextureUsage\./, '')).sort()
      : [];
    if (JSON.stringify(jsUsage) !== JSON.stringify([...c.usage].sort())) {
      fail(`device.cpp ${c.cpp.jsConfigureFunction} usage must be ${c.usage.join('|')} (got ${jsUsage.join('|') || 'missing'})`);
    }
    if (!/format:\s*preferredFormat/.test(body)) {
      fail(`device.cpp ${c.cpp.jsConfigureFunction} format must be getPreferredCanvasFormat() (preferredFormat)`);
    }
    if (/colorSpace|toneMapping/.test(body)) {
      fail(`device.cpp ${c.cpp.jsConfigureFunction} must not set colorSpace/toneMapping (opt-in is TS-first)`);
    }
  }

  const surf = cpp.match(new RegExp(`void WebGPURenderer::${c.cpp.surfaceConfigureFunction}\\(\\)\\s*\\{[\\s\\S]*?\\n\\}`));
  if (!surf) {
    fail(`device.cpp WebGPURenderer::${c.cpp.surfaceConfigureFunction}() not found`);
  } else {
    const body = surf[0];
    const usage = body.match(/config\.usage\s*=\s*([^;]+);/);
    const cppUsage = usage ? usage[1].split('|').map((u) => u.trim()).sort() : [];
    const wantUsage = c.usage.map((u) => c.cpp.usageEnums[u]).sort();
    if (JSON.stringify(cppUsage) !== JSON.stringify(wantUsage)) {
      fail(`device.cpp ${c.cpp.surfaceConfigureFunction} usage must be ${wantUsage.join(' | ')} (got ${cppUsage.join(' | ') || 'missing'})`);
    }
    const alpha = c.cpp.alphaModeEnums[c.alphaMode];
    if (!new RegExp(`config\\.alphaMode\\s*=\\s*${alpha}\\b`).test(body)) {
      fail(`device.cpp ${c.cpp.surfaceConfigureFunction} alphaMode must be ${alpha}`);
    }
    const present = c.cpp.presentModeEnums[c.presentModeWasm];
    if (!new RegExp(`config\\.presentMode\\s*=\\s*${present}\\b`).test(body)) {
      fail(`device.cpp ${c.cpp.surfaceConfigureFunction} presentMode must be ${present}`);
    }
    if (!/config\.width\s*=/.test(body) || !/config\.height\s*=/.test(body)) {
      fail(`device.cpp ${c.cpp.surfaceConfigureFunction} must set explicit width/height`);
    }
    if (!/config\.format\s*=\s*surfaceFormat_/.test(body)) {
      fail(`device.cpp ${c.cpp.surfaceConfigureFunction} format must be surfaceFormat_ (negotiated preferred format)`);
    }
  }

  // Both configures are required: JS configure → importJsSurface → ConfigureSurface().
  const iImport = cpp.search(new RegExp(`=\\s*${c.cpp.jsConfigureFunction}\\(`));
  const afterImport = iImport >= 0 ? cpp.slice(iImport) : '';
  if (!new RegExp(`\\n\\s*${c.cpp.surfaceConfigureFunction}\\(\\);`).test(afterImport)) {
    fail(`device.cpp must call ${c.cpp.surfaceConfigureFunction}() after ${c.cpp.jsConfigureFunction} (second configure; black canvas without it)`);
  }

  verifyCanvasCopySrcCpp(c, cpp, surf ? surf[0] : '');
}

/**
 * C++ canvas COPY_SRC opt-in (canvas_configure.json cpp.copySrc):
 * probe EM_JS uses exactly optIn.copySrc.usage inside a validation error scope,
 * ConfigureSurface() restores render-only after it, the opt-in bits map through
 * cpp.usageEnums and are gated on the flag, and only the setter assigns the flag.
 */
function verifyCanvasCopySrcCpp(c, cpp, surfBody) {
  const cs = c.cpp.copySrc;
  if (!cs) {
    fail('canvas_configure.json cpp.copySrc block missing (C++ COPY_SRC opt-in contract)');
    return;
  }
  const optUsage = c.optIn.copySrc.usage;

  const probeFn = cpp.match(new RegExp(`EM_JS\\([^,]+,\\s*${cs.probeFunction}[\\s\\S]*?\\n\\}\\);`));
  const probeCfg = probeFn && probeFn[0].match(/ctx\.configure\(\{([\s\S]*?)\}\)/);
  if (!probeCfg) {
    fail(`device.cpp ${cs.probeFunction} ctx.configure({...}) not found`);
  } else {
    const body = probeCfg[1];
    const usage = body.match(/usage:\s*([^,\n}]+)/);
    const jsUsage = usage
      ? usage[1].split('|').map((u) => u.trim().replace(/^GPUTextureUsage\./, '')).sort()
      : [];
    if (JSON.stringify(jsUsage) !== JSON.stringify([...optUsage].sort())) {
      fail(`device.cpp ${cs.probeFunction} usage must be ${optUsage.join('|')} (got ${jsUsage.join('|') || 'missing'})`);
    }
    if (!new RegExp(`alphaMode:\\s*'${c.alphaMode}'`).test(body) || !/format:\s*preferredFormat/.test(body)) {
      fail(`device.cpp ${cs.probeFunction} must keep alphaMode '${c.alphaMode}' and format preferredFormat`);
    }
    if (/colorSpace|toneMapping/.test(body)) {
      fail(`device.cpp ${cs.probeFunction} must not set colorSpace/toneMapping (opt-in is TS-first)`);
    }
  }

  // Probe call: push scope → probe → pop scope → ConfigureSurface() (restore render-only).
  const iCall = cpp.search(new RegExp(`=\\s*${cs.probeFunction}\\(`));
  if (iCall < 0) {
    fail(`device.cpp must call ${cs.probeFunction}() at surface creation`);
  } else {
    const before = cpp.slice(0, iCall);
    const after = cpp.slice(iCall);
    const iPush = before.lastIndexOf('wgpuDevicePushErrorScope(');
    if (iPush < 0 || !/WGPUErrorFilter_Validation/.test(before.slice(iPush, iPush + 120))) {
      fail(`device.cpp ${cs.probeFunction}() must run inside wgpuDevicePushErrorScope(..., WGPUErrorFilter_Validation)`);
    }
    const iPop = after.indexOf('wgpuDevicePopErrorScope(');
    const iRestore = after.search(new RegExp(`\\n\\s*${c.cpp.surfaceConfigureFunction}\\(\\);`));
    if (iPop < 0 || iRestore < 0 || iRestore < iPop) {
      fail(`device.cpp ${cs.probeFunction}() must be followed by wgpuDevicePopErrorScope then ${c.cpp.surfaceConfigureFunction}() (restore render-only)`);
    }
    if (!new RegExp(`${cs.supportedFlag}\\s*=`).test(after.slice(0, iRestore > 0 ? iRestore : undefined))) {
      fail(`device.cpp must record the probe result in ${cs.supportedFlag} before ${c.cpp.surfaceConfigureFunction}()`);
    }
  }

  // ConfigureSurface: opt-in bits (optIn.copySrc.usage minus default usage) via cpp.usageEnums, gated on the flag.
  const extra = optUsage.filter((u) => !c.usage.includes(u));
  const wantEnums = extra.map((u) => c.cpp.usageEnums[u]);
  if (wantEnums.some((e) => !e)) {
    fail(`canvas_configure.json cpp.usageEnums missing an entry for ${extra.join(', ')}`);
  }
  const optLine = surfBody.match(new RegExp(`if\\s*\\(\\s*${cs.flag}\\s*\\)\\s*config\\.usage\\s*\\|=\\s*([^;]+);`));
  const gotEnums = optLine ? optLine[1].split('|').map((u) => u.trim()).sort() : [];
  if (JSON.stringify(gotEnums) !== JSON.stringify([...wantEnums].sort())) {
    fail(`device.cpp ${c.cpp.surfaceConfigureFunction} must have 'if (${cs.flag}) config.usage |= ${wantEnums.join(' | ')};' (got ${gotEnums.join(' | ') || 'missing'})`);
  }

  // Flag is assigned only in the setter; header defaults both flags to false.
  const header = fs.readFileSync(path.join(ROOT, 'wasm_renderer/renderer.h'), 'utf8');
  for (const flag of [cs.flag, cs.supportedFlag]) {
    if (!new RegExp(`bool\\s+${flag}\\s*=\\s*false;`).test(header)) {
      fail(`renderer.h must declare 'bool ${flag} = false;'`);
    }
  }
  const setter = cpp.match(new RegExp(`bool WebGPURenderer::${cs.setter}\\([^)]*\\)\\s*\\{[\\s\\S]*?\\n\\}`));
  if (!setter) {
    fail(`device.cpp WebGPURenderer::${cs.setter}() not found`);
  } else {
    if (!new RegExp(`${c.cpp.surfaceConfigureFunction}\\(\\);`).test(setter[0])) {
      fail(`device.cpp ${cs.setter}() must call ${c.cpp.surfaceConfigureFunction}()`);
    }
    if (!new RegExp(`!\\s*${cs.supportedFlag}`).test(setter[0])) {
      fail(`device.cpp ${cs.setter}() must refuse enabling when ${cs.supportedFlag} is false`);
    }
  }
  const assignRe = new RegExp(`\\b${cs.flag}\\s*=(?!=)`, 'g');
  const outsideSetter = setter ? cpp.replace(setter[0], '') : cpp;
  const stray = [...stripCppComments(outsideSetter).matchAll(assignRe)].length;
  const wasmSources = walkCppFiles(path.join(ROOT, 'wasm_renderer'))
    .filter((f) => f !== CPP_DEVICE && !f.endsWith('renderer.h'));
  const strayElsewhere = wasmSources.filter(
    (f) => [...stripCppComments(fs.readFileSync(f, 'utf8')).matchAll(assignRe)].length > 0,
  );
  if (stray > 0 || strayElsewhere.length > 0) {
    fail(`${cs.flag} may only be assigned inside ${cs.setter}() (found ${stray} in device.cpp, files: ${strayElsewhere.map((f) => path.relative(ROOT, f)).join(', ') || 'none'})`);
  }

  const exportsJson = JSON.parse(fs.readFileSync(path.join(ROOT, 'src/contracts/wasm_exports.json'), 'utf8'));
  for (const name of cs.exports || []) {
    if (!exportsJson.exportedFunctions.includes(name)) {
      fail(`wasm_exports.json must export ${name} (canvas_configure.json cpp.copySrc.exports)`);
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
}

function verifyWasmCompileFlags() {
  const flags = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'src/contracts/wasm_compile_flags.json'), 'utf8'),
  );
  const buildSh = fs.readFileSync(path.join(ROOT, 'wasm_renderer/build.sh'), 'utf8');
  const cmake = fs.readFileSync(path.join(ROOT, 'wasm_renderer/CMakeLists.txt'), 'utf8');
  const ci = fs.readFileSync(path.join(ROOT, '.github/workflows/ci.yml'), 'utf8');

  if (!/^\d+\.\d+\.\d+$/.test(flags.emsdkVersion || '')) {
    fail(`wasm_compile_flags.json emsdkVersion must be an exact x.y.z pin, got "${flags.emsdkVersion}"`);
  }
  if (!flags.sFlags.includes('GROWABLE_ARRAYBUFFERS=0')) {
    fail('wasm_compile_flags.json must keep GROWABLE_ARRAYBUFFERS=0 (TextDecoder + resizable heap; re-test Dawn first)');
  }

  // CI setup-emsdk must use the pin, not `latest`.
  const emsdkStep = ci.match(/uses:\s*mymindstorm\/setup-emsdk@[^\n]*[\s\S]*?version:\s*['"]?([^'"\s]+)/g) || [];
  if (emsdkStep.length === 0) fail('ci.yml: setup-emsdk step with version: not found');
  for (const step of emsdkStep) {
    const v = step.match(/version:\s*['"]?([^'"\s]+)/)[1];
    if (v !== flags.emsdkVersion) {
      fail(`ci.yml setup-emsdk version "${v}" must equal wasm_compile_flags.json emsdkVersion "${flags.emsdkVersion}"`);
    }
  }

  // build.sh / CMake must read the JSON, not hand-copy -s flags.
  if (!buildSh.includes('format-wasm-compile-flags.js')) {
    fail('build.sh must read flags via scripts/format-wasm-compile-flags.js');
  }
  if (!buildSh.includes('emcc-version-gate.sh')) {
    fail('build.sh must run scripts/emcc-version-gate.sh before compiling');
  }
  if (!cmake.includes('wasm_compile_flags.json')) {
    fail('CMakeLists.txt must file(READ) src/contracts/wasm_compile_flags.json');
  }
  for (const [name, src] of [['build.sh', buildSh], ['CMakeLists.txt', cmake]]) {
    const code = src.split('\n').filter((l) => !/^\s*#/.test(l)).join('\n');
    for (const f of flags.sFlags) {
      const key = f.split('=')[0];
      if (new RegExp(`-s${key}\\b`).test(code)) {
        fail(`${name} hardcodes -s${key}; it belongs in wasm_compile_flags.json`);
      }
    }
    if (/--use-port=emdawnwebgpu/.test(code)) {
      fail(`${name} hardcodes --use-port; it belongs in wasm_compile_flags.json`);
    }
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

function verifyEmptyPlaceholder() {
  const wgContract = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'src/contracts/workgroup_dispatch.json'), 'utf8'),
  );
  const ph = wgContract.emptyPlaceholder;
  if (!ph || ph.format !== 'r32float' || ph.bytesPerRow !== 4) {
    fail('workgroup_dispatch.json emptyPlaceholder must be { format: "r32float", bytesPerRow: 4 }');
    return;
  }

  const tsPath = path.join(ROOT, ph.tsFile || 'src/renderer/webgpu/resources.ts');
  const tsSrc = fs.readFileSync(tsPath, 'utf8');
  const emptyTexBlock = tsSrc.match(
    /const emptyTex = track\(device.createTexture\(\{[\s\S]*?writeTexture\([\s\S]*?\[1,\s*1\],/,
  );
  if (!emptyTexBlock) {
    fail('resources.ts emptyTex createTexture + writeTexture block not found');
  } else {
    const block = emptyTexBlock[0];
    if (!block.includes("format: 'r32float'") && !block.includes('format: "r32float"')) {
      fail(`resources.ts emptyTex must use format ${ph.format}`);
    }
    if (!block.includes(`bytesPerRow: ${ph.bytesPerRow}`)) {
      fail(`resources.ts emptyTex writeTexture must use bytesPerRow: ${ph.bytesPerRow}`);
    }
    if (!block.includes('new Float32Array([0])')) {
      fail('resources.ts emptyTex must upload new Float32Array([0]) (one r32float, not rgba)');
    }
  }

  const cppPath = path.join(ROOT, ph.cppFile || 'wasm_renderer/resources.cpp');
  const cppSrc = fs.readFileSync(cppPath, 'utf8');
  const marker = cppSrc.indexOf('Empty texture (1x1 r32float)');
  if (marker < 0) {
    fail('resources.cpp emptyTexture_ comment block not found');
    return;
  }
  const writeEnd = cppSrc.indexOf('sizeof(black)', marker);
  const cppBlock = cppSrc.slice(marker, writeEnd > marker ? writeEnd + 80 : marker + 1200);
  if (!cppBlock.includes('emptyTexture_')) {
    fail('emptyTexture_ not found in resources.cpp empty-placeholder block');
    return;
  }
  if (!/texDesc\.size\s*=\s*\{\s*1\s*,\s*1\s*,\s*1\s*\}/.test(cppBlock)) {
    fail('resources.cpp emptyTexture_ must set texDesc.size = {1, 1, 1}');
  }
  const sizePos = cppBlock.search(/texDesc\.size\s*=\s*\{\s*1\s*,\s*1\s*,\s*1\s*\}/);
  const formatPos = cppBlock.search(/texDesc\.format\s*=\s*WGPUTextureFormat_R32Float/);
  if (formatPos < 0 || (sizePos >= 0 && formatPos < sizePos)) {
    fail(
      'resources.cpp emptyTexture_ must set texDesc.format = WGPUTextureFormat_R32Float after 1×1 size (explicit reset)',
    );
  }
  if (/bytesPerRow\s*=\s*sizeof\(float\)\s*\*\s*4/.test(cppBlock)) {
    fail('resources.cpp emptyTexture_ must not use bytesPerRow = sizeof(float) * 4');
  }
  if (/bytesPerRow\s*=\s*16\b/.test(cppBlock)) {
    fail('resources.cpp emptyTexture_ must not use bytesPerRow = 16');
  }
  if (!/bytesPerRow\s*=\s*sizeof\(float\)/.test(cppBlock)) {
    fail('resources.cpp emptyTexture_ must use bytesPerRow = sizeof(float)');
  }
  if (/float\s+black\s*\[\s*4\s*\]/.test(cppBlock)) {
    fail('resources.cpp emptyTexture_ must upload one float, not float black[4]');
  }
  if (!/float\s+black\s*=\s*0\.0f/.test(cppBlock)) {
    fail('resources.cpp emptyTexture_ must declare float black = 0.0f');
  }
  if (!/sizeof\(black\)/.test(cppBlock)) {
    fail('resources.cpp emptyTexture_ write must use sizeof(black)');
  }
}

function verifySlotLimits() {
  const file = 'src/contracts/slot_limits.json';
  const c = JSON.parse(fs.readFileSync(path.join(ROOT, file), 'utf8'));
  const n = c.maxPhysicalSlots;
  if (!Number.isInteger(n) || n < 1) fail(`${file} maxPhysicalSlots must be a positive integer`);
  const [capLo, capHi] = c.qualityCapRange || [];
  if (!(capLo >= 1 && capHi >= capLo && capHi <= n)) {
    fail(`${file} qualityCapRange must sit inside 1..maxPhysicalSlots`);
  }

  // ── TS: PHYSICAL_SLOT_LIMIT comes from the contract, not a literal ───────
  const ts = fs.readFileSync(path.join(ROOT, c.ts.file), 'utf8');
  if (!/import slotLimitsContract from '\.\.\/contracts\/slot_limits\.json'/.test(ts)) {
    fail(`${c.ts.file} must import slotLimitsContract from contracts/slot_limits.json`);
  }
  if (!new RegExp(`export const ${c.ts.constant}(?::\\s*number)?\\s*=\\s*slotLimitsContract\\.maxPhysicalSlots;`).test(ts)) {
    fail(`${c.ts.file} ${c.ts.constant} must equal slotLimitsContract.maxPhysicalSlots`);
  }

  // ── TS policy: quality cap never exceeds the contract range ──────────────
  const policy = fs.readFileSync(path.join(ROOT, 'src/config/performancePolicy.ts'), 'utf8');
  for (const m of policy.matchAll(/maxActiveSlots:\s*(\d+)/g)) {
    const v = parseInt(m[1], 10);
    if (v < capLo || v > capHi) fail(`performancePolicy.ts maxActiveSlots ${v} outside ${file} qualityCapRange ${capLo}..${capHi}`);
  }

  // ── C++: MAX_SHADER_SLOTS equals the contract ────────────────────────────
  const header = fs.readFileSync(path.join(ROOT, c.cpp.file), 'utf8');
  const m = header.match(new RegExp(`static\\s+constexpr\\s+int\\s+${c.cpp.constant}\\s*=\\s*(\\d+)\\s*;`));
  if (!m) {
    fail(`${c.cpp.file} ${c.cpp.constant} not found`);
  } else if (parseInt(m[1], 10) !== n) {
    fail(`${c.cpp.file} ${c.cpp.constant} = ${m[1]} but ${file} maxPhysicalSlots = ${n} (TS ${c.ts.constant})`);
  }

  // Per-index output tables only cover as many slots as they list; the frame
  // loop must pick outputs by position in the chain instead.
  const frame = fs.readFileSync(path.join(ROOT, c.cpp.frameFile), 'utf8');
  if (new RegExp(`\\[\\s*${c.cpp.constant}\\s*\\]\\s*=\\s*\\{`).test(frame)) {
    fail(`${c.cpp.frameFile} must not initialise a fixed per-slot array sized ${c.cpp.constant} (breaks when the limit changes)`);
  }

  // Out-of-range slot setters log instead of returning silently.
  const slice = fs.readFileSync(path.join(ROOT, c.cpp.sliceFile), 'utf8');
  for (const setter of ['SetSlotShader', 'SetSlotParams', 'SetSlotMode']) {
    const body = slice.match(new RegExp(`void WebGPURenderer::${setter}\\([\\s\\S]*?\\n\\}`));
    const guard = body && body[0].match(new RegExp(`slotIndex >= ${c.cpp.constant}\\)\\s*\\{([\\s\\S]*?)return;`));
    if (!guard || !/printf\(/.test(guard[1])) {
      fail(`${c.cpp.sliceFile} ${setter} must printf before ignoring an out-of-range slot`);
    }
  }
}

/**
 * bind_group1.json (opt-in @group(1) sim ring) ↔ simRing.ts layout ↔ limits
 * policy ↔ WASM refusal. The group-1 limits must never leak into the
 * catalog-wide requiredLimits, and the C++ pipeline stays group-0 only.
 */
function verifyBindGroup1() {
  const contractPath = path.join(ROOT, 'src/contracts/bind_group1.json');
  const c = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
  const expected = [
    { binding: 0, name: 'simState', bufferType: 'storage' },
    { binding: 1, name: 'simIndex', bufferType: 'read-only-storage' },
    { binding: 2, name: 'simParams', bufferType: 'uniform' },
  ];
  if (c.group !== 1) fail('bind_group1.json group must be 1');
  if (!Array.isArray(c.bindings) || c.bindings.length !== expected.length) {
    fail(`bind_group1.json must declare exactly ${expected.length} bindings`);
    return;
  }
  expected.forEach((e, i) => {
    const b = c.bindings[i];
    if (b.binding !== e.binding || b.name !== e.name || b.bufferType !== e.bufferType) {
      fail(`bind_group1.json binding ${i} must be ${e.name} (${e.bufferType}) at @binding(${e.binding})`);
    }
  });
  if (c.bindings[0].elementBytes !== 16) fail('simState elementBytes must be 16 (vec4<f32>)');
  const fields = c.bindings[2].fields || [];
  if (fields.join(',') !== 'stateCount,indexCount,frame,truncated') {
    fail('simParams fields must be [stateCount, indexCount, frame, truncated]');
  }
  if (c.bindings[2].sizeBytes !== fields.length * 4) fail('simParams sizeBytes must be 4 × fields');
  if (c.barrier?.from !== 'simState' || c.barrier?.to !== 'simIndex' || c.barrier?.kind !== 'copyBufferToBuffer') {
    fail('bind_group1.json barrier must be copyBufferToBuffer simState → simIndex');
  }
  const wg = c.dispatch?.simStateWorkgroupSize || [];
  if (wg.join(',') !== '64,1,1') fail('simStateWorkgroupSize must be [64, 1, 1]');
  if ((c.dispatch?.domains || []).join(',') !== 'pixels,simState') {
    fail('dispatch.domains must be [pixels, simState]');
  }

  // TS layout ↔ JSON (binding order + buffer types).
  const tsFile = 'src/renderer/webgpu/simRing.ts';
  const ts = fs.readFileSync(path.join(ROOT, tsFile), 'utf8');
  const bgl = ts.match(/export function createSimRingBindGroupLayout[\s\S]*?\n\}/);
  if (!bgl) {
    fail(`${tsFile} must export createSimRingBindGroupLayout`);
  } else {
    const entries = [...bgl[0].matchAll(/\{\s*binding:\s*(\d+)[^}]*buffer:\s*\{\s*type:\s*'([a-z-]+)'\s*\}/g)];
    if (entries.length !== expected.length) {
      fail(`${tsFile} createSimRingBindGroupLayout declares ${entries.length} entries, contract has ${expected.length}`);
    }
    entries.forEach((m, i) => {
      const e = expected[i];
      if (!e || parseInt(m[1], 10) !== e.binding || m[2] !== e.bufferType) {
        fail(`${tsFile} layout entry ${i} is binding ${m[1]} '${m[2]}', contract wants ${e ? `${e.binding} '${e.bufferType}'` : 'nothing'}`);
      }
    });
  }
  if (!/import bindGroup1Contract from '..\/..\/contracts\/bind_group1\.json'/.test(ts)) {
    fail(`${tsFile} must import bind_group1.json (ladder, key and limits come from the contract)`);
  }
  if (!/bindGroupLayouts:\s*\[group0,\s*group1\]/.test(ts)) {
    fail(`${tsFile} createSimRingPipelineLayout must be [group0, group1]`);
  }

  // OOM ladder discipline.
  const ladder = c.oom?.ladder || [];
  if (ladder.join(',') !== '65536,32768,16384,4096') fail('sim-ring OOM ladder must be 65536 → 32768 → 16384 → 4096');
  if (c.oom?.defaultStateCount !== ladder[0]) fail('oom.defaultStateCount must be the top ladder rung');
  if (c.oom?.sessionStorageKey !== 'px_simring_oom_cap') fail('oom.sessionStorageKey must be px_simring_oom_cap');

  // Group-1 limits: within WebGPU base limits, and never catalog-wide.
  const base = c.webgpuBaseLimits || {};
  for (const [key, need] of Object.entries(c.group1RequiredLimits || {})) {
    if (!(key in base)) fail(`webgpuBaseLimits missing ${key}`);
    else if (need > base[key]) fail(`group1RequiredLimits.${key}=${need} exceeds WebGPU base ${base[key]}`);
  }
  const g0 = EXPECTED_LIMITS;
  if ('maxBindGroups' in g0) fail('webgpu_limits.json must not require maxBindGroups (group 1 is opt-in)');
  if (g0.maxStorageBuffersPerShaderStage >= c.group1RequiredLimits.maxStorageBuffersPerShaderStage) {
    fail('webgpu_limits.json maxStorageBuffersPerShaderStage was raised to the group-1 value — keep it catalog-minimal');
  }
  const policy = fs.readFileSync(TS_POLICY, 'utf8');
  if (/bind_group1|GROUP1_REQUIRED_LIMITS/.test(policy)) {
    fail('webgpuDevicePolicy.ts must not fold group-1 limits into requiredLimits');
  }

  // WASM: C++ stays single-layout; bridge refuses group-1 WGSL before LoadShader.
  const pipelineCpp = fs.readFileSync(path.join(ROOT, 'wasm_renderer/pipeline.cpp'), 'utf8');
  if (!/bindGroupLayoutCount\s*=\s*1\s*;/.test(pipelineCpp)) {
    fail('wasm_renderer/pipeline.cpp must keep bindGroupLayoutCount = 1 (feature freeze)');
  }
  const bridgeFile = 'src/wasm/bridge/shader.ts';
  const bridge = fs.readFileSync(path.join(ROOT, bridgeFile), 'utf8');
  for (const fnName of ['loadShader', 'reloadShader']) {
    const body = bridge.match(new RegExp(`export function ${fnName}\\([\\s\\S]*?\\n\\}`));
    const refuse = body ? body[0].indexOf('declaresBindGroup1(') : -1;
    const ccall = body ? body[0].indexOf(`ccall('${fnName}'`) : -1;
    if (refuse < 0 || ccall < 0 || refuse > ccall) {
      fail(`${bridgeFile} ${fnName} must refuse @group(1) WGSL before ccall('${fnName}')`);
    }
  }

  // Definitions that opt into the ring must dispatch at least one simState node.
  const defsDir = path.join(ROOT, 'shader_definitions');
  const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : e.name.endsWith('.json') ? [path.join(dir, e.name)] : []);
  for (const file of walk(defsDir)) {
    let def;
    try { def = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { continue; }
    if (!def.simRing) continue;
    const nodes = def.multipass?.graph?.nodes || [];
    if (!nodes.some((n) => n.dispatch === 'simState')) {
      fail(`${path.relative(ROOT, file)} declares simRing but no graph node dispatches simState`);
    }
    const n = def.simRing.stateCount;
    if (!Number.isInteger(n) || n < 1 || n > ladder[0]) {
      fail(`${path.relative(ROOT, file)} simRing.stateCount must be 1–${ladder[0]}`);
    }
  }
}

if (!ONLY_WASM_INVARIANTS) {
  verifyOptionalFeatures();
  verifyBindGroup1();
  verifyCanvasConfigure();
  verifySlotLimits();
  verifyWasmExports();
  verifyWorkgroupDispatch();
  verifyEmptyPlaceholder();
}
verifyWasmCompileFlags();
verifyWasmRuntimeInvariants();

if (failed) {
  process.exit(1);
}

console.log(
  '✅ Device policy sync OK (limits + optional features + canvas_configure + slot_limits + wasm_exports + wasm_compile_flags + workgroup_dispatch + emptyPlaceholder + bind_group1 + wasm_runtime_invariants ↔ TS/C++/shaders/wasm)',
);

function walkCppFiles(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) out.push(...walkCppFiles(p));
    else if (ent.name.endsWith('.cpp')) out.push(p);
  }
  return out;
}

function stripCppComments(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
}

function verifyWasmRuntimeInvariants() {
  const invPath = path.join(ROOT, 'src/contracts/wasm_runtime_invariants.json');
  const inv = JSON.parse(fs.readFileSync(invPath, 'utf8'));
  const { readWasmImports } = require('./wasm_import_table.js');

  for (const ban of inv.forbiddenCppSymbols || []) {
    const re = new RegExp(ban.callPattern);
    const roots = ban.globs || ['wasm_renderer/**/*.cpp'];
    for (const glob of roots) {
      const base = glob.replace(/\/\*\*\/\*\.cpp$/, '');
      for (const file of walkCppFiles(path.join(ROOT, base))) {
        const stripped = stripCppComments(fs.readFileSync(file, 'utf8'));
        if (re.test(stripped)) {
          fail(
            `${path.relative(ROOT, file)} must not call ${ban.symbol} (${ban.reason})`,
          );
        }
      }
    }

    const artifact = path.join(ROOT, ban.wasmArtifact || 'public/wasm/pixelocity_wasm.wasm');
    if (!fs.existsSync(artifact)) {
      fail(`missing wasm artifact ${ban.wasmArtifact}`);
    } else {
      let imports;
      try {
        imports = readWasmImports(artifact);
      } catch (err) {
        fail(`wasm import table: ${err instanceof Error ? err.message : String(err)}`);
        imports = [];
      }
      const names = new Set(imports.map((imp) => imp.name));
      for (const forbidden of ban.wasmImportNames || [ban.symbol]) {
        if (names.has(forbidden)) {
          fail(
            `${ban.wasmArtifact} import table contains forbidden ${forbidden} (must be DCE'd; do not call ${ban.symbol})`,
          );
        }
      }
    }
  }

  const samp = inv.requiredSamplerDefaults;
  if (samp) {
    const cppPath = path.join(ROOT, samp.cppFile);
    const cpp = fs.readFileSync(cppPath, 'utf8');
    const assignRe = new RegExp(samp.assignmentPattern);
    const assign = assignRe.exec(cpp);
    if (!assign) {
      fail(`${samp.cppFile} must assign ${samp.assignmentPattern} (Dawn rejects maxAnisotropy < ${samp.maxAnisotropy})`);
    }
    const createRe = new RegExp(samp.createSamplerPattern, 'g');
    const creates = [];
    let m;
    while ((m = createRe.exec(cpp))) creates.push(m.index);
    if (creates.length !== samp.createSamplerCount) {
      fail(
        `${samp.cppFile} expected ${samp.createSamplerCount} wgpuDeviceCreateSampler calls, found ${creates.length}`,
      );
    }
    if (assign && creates.some((idx) => idx < assign.index)) {
      fail(
        `${samp.cppFile} samplerDesc.maxAnisotropy = ${samp.maxAnisotropy} must precede all ${samp.createSamplerCount} wgpuDeviceCreateSampler calls (filtering, non-filtering, comparison)`,
      );
    }
  }

  const ladder = inv.historyTexLadder;
  if (ladder) {
    const vram = fs.readFileSync(path.join(ROOT, 'src/config/vramBudget.ts'), 'utf8');
    const probe = fs.readFileSync(path.join(ROOT, 'src/renderer/webgpu/historyTexProbe.ts'), 'utf8');
    const constants = fs.readFileSync(path.join(ROOT, 'src/renderer/webgpu/webgpuConstants.ts'), 'utf8');
    const keyRe = new RegExp(`HISTORY_OOM_CAP_KEY\\s*=\\s*['"]${ladder.sessionStorageKey}['"]`);
    if (!keyRe.test(vram)) {
      fail(`vramBudget.ts HISTORY_OOM_CAP_KEY must be '${ladder.sessionStorageKey}'`);
    }
    const full = vram.match(/HISTORY_FULL_WORKING_SIZE\s*=\s*(\d+)/);
    const safe = vram.match(/HISTORY_SAFE_WORKING_SIZE\s*=\s*(\d+)/);
    const depth = constants.match(/HISTORY_DEPTH\s*=\s*(\d+)/);
    if (!full || !safe || !depth) {
      fail('history size/depth constants missing from vramBudget.ts / webgpuConstants.ts');
    } else {
      const expected = ladder.rungs;
      const actual = [
        [parseInt(full[1], 10), parseInt(depth[1], 10)],
        [parseInt(safe[1], 10), parseInt(depth[1], 10)],
        [parseInt(safe[1], 10), 4],
        [parseInt(safe[1], 10), 1],
      ];
      if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        fail(
          `historyTex ladder mismatch: contract ${JSON.stringify(expected)} vs sources ${JSON.stringify(actual)}`,
        );
      }
    }
    const rungsBlock = probe.match(/export\s+const\s+HISTORY_PROBE_RUNGS(?:\s*:\s*[^=]+)?\s*=\s*\[([\s\S]*?)\];/m);
    if (!rungsBlock) {
      fail('historyTexProbe.ts missing HISTORY_PROBE_RUNGS');
    }
    if (ladder.defaultWorkingSize != null) {
      if (!safe || parseInt(safe[1], 10) !== ladder.defaultWorkingSize) {
        fail(
          `historyTex defaultWorkingSize: contract ${ladder.defaultWorkingSize} vs HISTORY_SAFE_WORKING_SIZE ${safe && safe[1]}`,
        );
      }
      if (!/function getHistoryWorkingSizeCap[\s\S]*return HISTORY_SAFE_WORKING_SIZE/.test(vram)) {
        fail('vramBudget.ts getHistoryWorkingSizeCap() must default to HISTORY_SAFE_WORKING_SIZE (1024)');
      }
      // The WASM bridge is emitted unbundled and cannot import vramBudget.ts, so its
      // first-commit size cap is a literal that must track the contract.
      const bridgeInit = fs.readFileSync(path.join(ROOT, 'src/wasm/bridge/init.ts'), 'utf8');
      const bridgeCap = bridgeInit.match(/const\s+sizeCap\s*=\s*(\d+)/);
      if (!bridgeCap || parseInt(bridgeCap[1], 10) !== ladder.defaultWorkingSize) {
        fail(
          `src/wasm/bridge/init.ts sizeCap ${bridgeCap && bridgeCap[1]} must equal historyTexLadder.defaultWorkingSize ${ladder.defaultWorkingSize}`,
        );
      }
      if (bridgeInit.includes(`'${ladder.sessionStorageKey}'`)) {
        fail(`src/wasm/bridge/init.ts must not hardcode '${ladder.sessionStorageKey}' (owned by vramBudget.ts)`);
      }
    }
    if (ladder.minMaxBufferSizeForFull != null) {
      const minBuf = vram.match(/MIN_MAX_BUFFER_SIZE_FOR_FULL\s*=\s*(\d+)/);
      if (!minBuf || parseInt(minBuf[1], 10) !== ladder.minMaxBufferSizeForFull) {
        fail(
          `MIN_MAX_BUFFER_SIZE_FOR_FULL must be ${ladder.minMaxBufferSizeForFull} (working-size heuristic only — not maxTextureDimension2D)`,
        );
      }
      if (!vram.includes('function allowsFullWorkingSize')) {
        fail('vramBudget.ts must export allowsFullWorkingSize for the 2048 upgrade gate');
      }
    }
    if (!probe.includes('HISTORY_PROBE_RUNGS')) {
      fail('historyTexProbe.ts must export HISTORY_PROBE_RUNGS');
    } else {
      const normalized = rungsBlock[1].replace(/\s+/g, ' ');
      const expectedRungs = [
        '{ size: HISTORY_FULL_WORKING_SIZE, layers: HISTORY_DEPTH }',
        '{ size: HISTORY_SAFE_WORKING_SIZE, layers: HISTORY_DEPTH }',
        '{ size: HISTORY_SAFE_WORKING_SIZE, layers: 4 }',
        '{ size: HISTORY_SAFE_WORKING_SIZE, layers: 1 }',
      ];
      for (const rung of expectedRungs) {
        if (!normalized.includes(rung)) {
          fail(`historyTexProbe.ts HISTORY_PROBE_RUNGS missing expected rung ${rung}`);
        }
      }
      const actualRungs = normalized.match(/\{\s*size:\s*[^}]+?\}/g) || [];
      if (actualRungs.length !== expectedRungs.length) {
        fail(`historyTexProbe.ts HISTORY_PROBE_RUNGS must have ${expectedRungs.length} rungs (found ${actualRungs.length})`);
      }
    }
  }

  const fmt = inv.storageFormatRewrite;
  if (fmt) {
    const tsRewrite = fs.readFileSync(path.join(ROOT, fmt.tsFile), 'utf8');
    if (!tsRewrite.includes(fmt.catalogWgslFormat)) {
      fail(`${fmt.tsFile} must keep catalog authored format ${fmt.catalogWgslFormat}`);
    }
    const cppRewrite = fs.readFileSync(path.join(ROOT, fmt.cppRewriteFile), 'utf8');
    if (!/\bRewriteWgslStorageFormats\s*\(/.test(cppRewrite)) {
      fail(`${fmt.cppRewriteFile} must define RewriteWgslStorageFormats`);
    }
    const cppProbe = fs.readFileSync(path.join(ROOT, fmt.cppProbeFile), 'utf8');
    if (!cppProbe.includes('InternalColorFormat::Rgba16Float')) {
      fail(`${fmt.cppProbeFile} must prefer rgba16float (Rgba16Float) after a successful storage probe`);
    }
    if (fmt.rewriteStorageDeclsToActiveColorFormat && !cppRewrite.includes('texture_storage_2d')) {
      fail(`${fmt.cppRewriteFile} must rewrite texture_storage_2d declarations to the active colour format`);
    }

    const pipelineFile = fmt.pipelineFile || 'wasm_renderer/pipeline.cpp';
    const pipelineCpp = fs.readFileSync(path.join(ROOT, pipelineFile), 'utf8');
    const bglPat = new RegExp(fmt.bglStorageFormatPattern || 'RgbaStorageFormat\\(colorFormat_\\)', 'g');
    const bglHits = pipelineCpp.match(bglPat) || [];
    const wantBgl = fmt.bglStorageBindingCount != null ? fmt.bglStorageBindingCount : 3;
    if (bglHits.length < wantBgl) {
      fail(
        `${pipelineFile} must set storage texture format via RgbaStorageFormat(colorFormat_) ` +
          `at least ${wantBgl} times (bindings 2/7/8); found ${bglHits.length}`,
      );
    }
    const rewriteCall = new RegExp(fmt.loadShaderRewriteCall || 'RewriteWgslStorageFormats\\s*\\(');
    if (!rewriteCall.test(pipelineCpp)) {
      fail(`${pipelineFile} LoadShader must call RewriteWgslStorageFormats`);
    }
    if (fmt.loadShaderErrorScope && !pipelineCpp.includes(fmt.loadShaderErrorScope)) {
      fail(`${pipelineFile} LoadShader must PushErrorScope around CreateComputePipeline`);
    }
    if (fmt.loadShaderSkipHadError && !pipelineCpp.includes(fmt.loadShaderSkipHadError)) {
      fail(`${pipelineFile} LoadShader must skip storing the pipeline when pop.hadError`);
    }
    if (fmt.loadShaderWaitAnyFailSoft && !pipelineCpp.includes(fmt.loadShaderWaitAnyFailSoft)) {
      fail(`${pipelineFile} LoadShader must treat WaitAny failure as invalid (waitFailed)`);
    }

    const resourcesFile = fmt.resourcesFile || 'wasm_renderer/resources.cpp';
    const resourcesCpp = fs.readFileSync(path.join(ROOT, resourcesFile), 'utf8');
    const depthLabel = fmt.depthWriteLabel || 'Depth Texture Write';
    const copySrc = fmt.copySrcUsage || 'WGPUTextureUsage_CopySrc';
    const labelIdx = [];
    let searchFrom = 0;
    while (true) {
      const i = resourcesCpp.indexOf(depthLabel, searchFrom);
      if (i < 0) break;
      labelIdx.push(i);
      searchFrom = i + depthLabel.length;
    }
    if (labelIdx.length < 2) {
      fail(`${resourcesFile} must create "${depthLabel}" in CreateResources and RecreateTextures (found ${labelIdx.length})`);
    }
    for (const idx of labelIdx) {
      const windowStart = Math.max(0, idx - 400);
      const before = resourcesCpp.slice(windowStart, idx);
      if (!before.includes(copySrc)) {
        fail(`${resourcesFile} "${depthLabel}" usage must include ${copySrc} (feedback CopyTextureToTexture)`);
      }
    }

    const frameFile = fmt.frameFile || 'wasm_renderer/frame.cpp';
    const frameCpp = fs.readFileSync(path.join(ROOT, frameFile), 'utf8');
    const copyPat = new RegExp(fmt.depthFeedbackCopyPattern || 'CopyTex\\s*\\([^;]*depthTextureWrite_');
    if (!copyPat.test(frameCpp)) {
      fail(`${frameFile} must CopyTex depthTextureWrite_ → depthTextureRead_ (keep in sync with CopySrc on the write texture)`);
    }
    if (fmt.depthFeedbackGatePattern) {
      const gatePat = new RegExp(fmt.depthFeedbackGatePattern, 'g');
      const gated = (frameCpp.match(gatePat) || []).length;
      const ungated = (frameCpp.match(new RegExp(copyPat.source, 'g')) || []).length;
      const want = fmt.depthFeedbackGateCount ?? 1;
      if (gated < want || ungated !== gated) {
        fail(`${frameFile} must gate every depthTextureWrite_ → depthTextureRead_ copy on anyWritesDepth (found ${gated} gated of ${ungated}, want ${want}); an ungated copy clobbers uploaded depth maps`);
      }
    }
  }

  const wg = inv.maxComputeWorkgroupsPerDimension;
  if (wg) {
    if (wg.value !== 65535) {
      fail('maxComputeWorkgroupsPerDimension contract value must be 65535');
    }
    const host = fs.readFileSync(path.join(ROOT, wg.hostFile), 'utf8');
    if (!host.includes('assertDispatchWithinLimits')) {
      fail(`${wg.hostFile} must route chores dispatches through assertDispatchWithinLimits`);
    }
    const rawCeil = host.match(/\.dispatchWorkgroups\(\s*Math\.ceil/g);
    if (rawCeil) {
      fail(`${wg.hostFile} must not call dispatchWorkgroups(Math.ceil(...)) directly`);
    }
    const dispatchCount = (host.match(/this\.dispatchWorkgroupsSafe\(/g) || []).length;
    if (dispatchCount !== 5) {
      fail(
        `${wg.hostFile} must route all five chore passes through dispatchWorkgroupsSafe (found ${dispatchCount})`,
      );
    }
    const dispatchTs = fs.readFileSync(path.join(ROOT, 'src/gpuChores/dispatch.ts'), 'utf8');
    if (!dispatchTs.includes(`DEFAULT_MAX_WORKGROUPS_PER_DIMENSION = ${wg.value}`)) {
      fail(`dispatch.ts DEFAULT_MAX_WORKGROUPS_PER_DIMENSION must equal contract ${wg.value}`);
    }
  }

  const rebind = inv.mediaRebindAfterBackendSwitch;
  if (rebind) {
    const bridge = fs.readFileSync(path.join(ROOT, rebind.tsFile), 'utf8');
    if (!new RegExp(`export async function ${rebind.function}\\b`).test(bridge)) {
      fail(`${rebind.tsFile} must export ${rebind.function}`);
    }
    const manager = fs.readFileSync(path.join(ROOT, rebind.managerFile), 'utf8');
    if (!new RegExp(`\\b${rebind.function}\\s*\\(`).test(manager)) {
      fail(`${rebind.managerFile} must call ${rebind.function} after a successful backend switch`);
    }
  }
}
