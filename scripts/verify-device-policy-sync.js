#!/usr/bin/env node
/**
 * verify-device-policy-sync.js
 *
 * CI check: webgpu_limits.json ↔ TS policy ↔ device.cpp CheckLimit/requiredLimits;
 * optional feature order ↔ device.ts / device.cpp;
 * slot_limits.json ↔ PHYSICAL_SLOT_LIMIT / MAX_SHADER_SLOTS;
 * canvas_configure.json ↔ buildCanvasConfigureOptions / JS_CreateSurfaceFromCanvas / ConfigureSurface; wasm_exports.json ↔ KEEPALIVE /
 * build.sh (no hardcoded export lists; build.sh is the only build, CMakeLists.txt was removed);
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

/** webgpu_limits.json key -> the generated C++ constant name (kMaxTextureDimension2D). */
const cppConst = (key, ns = 'webgpu_limits') => `${ns}::${require('./gen-webgpu-limits-header.js').constName(key)}`;

function extractCppRequiredLimits() {
  const src = fs.readFileSync(CPP_DEVICE, 'utf8');
  const out = {};
  for (const key of Object.keys(EXPECTED_LIMITS)) {
    if (key === 'maxUniformBufferBindingSize') {
      if (!/requiredLimits\.maxUniformBufferBindingSize\s*=\s*sizeof\(Uniforms\)/.test(src)) {
        throw new Error('requiredLimits.maxUniformBufferBindingSize = sizeof(Uniforms) not found in device.cpp');
      }
      if (!/static_assert\(sizeof\(Uniforms\)\s*==\s*webgpu_limits::kMaxUniformBufferBindingSize/.test(src)) {
        throw new Error('device.cpp must static_assert(sizeof(Uniforms) == webgpu_limits::kMaxUniformBufferBindingSize)');
      }
      out[key] = EXPECTED_LIMITS[key];
      continue;
    }
    // The value comes from webgpu_limits.h (checked against the JSON below); a
    // literal here is the drift this header exists to remove.
    const m = src.match(new RegExp(`requiredLimits\\.${key}\\s*=\\s*([^;]+);`));
    if (!m) throw new Error(`requiredLimits.${key} not found in device.cpp`);
    if (m[1].trim() !== cppConst(key)) {
      throw new Error(`device.cpp requiredLimits.${key} must be ${cppConst(key)} (found '${m[1].trim()}')`);
    }
    out[key] = EXPECTED_LIMITS[key];
  }
  return out;
}

function extractCppCheckLimits() {
  const src = fs.readFileSync(CPP_DEVICE, 'utf8');
  const adapterBlock = src.match(
    /Adapter limits \(validating against 14-entry compute contract\):[\s\S]*?maxComputeInvocationsPerWorkgroup,\s*[^,]+,/,
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
      new RegExp(`CheckLimit\\("${key}",\\s*limits\\.${key},\\s*([^,]+),`),
    );
    if (!m) throw new Error(`CheckLimit("${key}", ...) not found in adapter block`);
    if (m[1].trim() !== cppConst(key)) {
      throw new Error(`device.cpp CheckLimit ${key} must use ${cppConst(key)} (found '${m[1].trim()}')`);
    }
    out[key] = expected;
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
  for (const key of Object.keys(deep)) {
    const want = cppConst(key, 'webgpu_limits::deep');
    if (gate && !new RegExp(`limits\\.${key}\\s*>=\\s*${want}\\b`).test(gate[1])) {
      fail(`device.cpp adapterDeepWorkgroup must test limits.${key} >= ${want} (webgpu_limits.json deepWorkgroupLimits)`);
    }
    if (block && !new RegExp(`requiredLimits\\.${key}\\s*=\\s*${want}\\s*;`).test(block[1])) {
      fail(`device.cpp deep requiredLimits.${key} must be ${want} (webgpu_limits.json deepWorkgroupLimits)`);
    }
  }
  const ts = fs.readFileSync(TS_POLICY, 'utf8');
  if (!/webgpuLimitsContract\.deepWorkgroupLimits/.test(ts)
      || !/meetsDeepWorkgroupLimits\(adapterLimits\)\s*\?\s*DEEP_WORKGROUP_LIMITS/.test(ts)) {
    fail('webgpuDevicePolicy.ts buildRequiredLimits must spread webgpuLimitsContract.deepWorkgroupLimits when meetsDeepWorkgroupLimits(adapterLimits)');
  }
}

// bufferSizeLimits: TS requests the adapter's value above the floor so the 2048
// working-size gate (maxBufferSize >= 1 GiB) can pass. C++ deliberately does not
// mirror it (WASM R&D freeze); the contract must say so explicitly.
function verifyBufferSizeLimits() {
  const floors = contract.bufferSizeLimits;
  if (!floors) return;
  if (contract.cppMirror?.bufferSizeLimits !== false || !contract.notes?.bufferSizeLimits) {
    fail('webgpu_limits.json bufferSizeLimits needs cppMirror.bufferSizeLimits: false and a notes.bufferSizeLimits reason');
  }
  const ts = fs.readFileSync(TS_POLICY, 'utf8');
  if (!/webgpuLimitsContract\.bufferSizeLimits/.test(ts) || !/\.\.\.bufferSizeRequest\(adapterLimits\)/.test(ts)) {
    fail('webgpuDevicePolicy.ts buildRequiredLimits must spread bufferSizeRequest(adapterLimits) built from webgpuLimitsContract.bufferSizeLimits');
  }
  for (const key of Object.keys(floors)) {
    if (!ts.includes(`'${key}'`)) fail(`webgpuDevicePolicy.ts bufferSizeRequest must request ${key}`);
  }
}

// wasm_renderer/webgpu_limits.h is generated from webgpu_limits.json; device.cpp
// must include it (the constants are what extractCpp*Limits above verify).
function verifyLimitsHeader() {
  const gen = require('./gen-webgpu-limits-header.js');
  const headerFile = gen.headerPath(contract);
  const have = fs.existsSync(headerFile) ? fs.readFileSync(headerFile, 'utf8') : '';
  if (have !== gen.renderHeader(contract)) {
    fail(`${contract.cpp.header} is stale or missing; run: npm run gen:webgpu-limits`);
  }
  if (!/#include "webgpu_limits\.h"/.test(fs.readFileSync(CPP_DEVICE, 'utf8'))) {
    fail('device.cpp must #include "webgpu_limits.h"');
  }
}

// wasm_renderer/bind_group0.h is generated from bind_group0.json; pipeline.cpp
// must include it and TS pipeline.ts must build its layout from the same JSON.
// readDepthTexture is unfilterable-float in both renderers, so no shader may
// sample it through the filtering u_sampler (compiles under one, fails the other).
function verifyBindGroup0() {
  const gen = require('./gen-bind-group0-header.js');
  const bg0 = gen.loadContract();
  const headerFile = gen.headerPath(bg0);
  let want = '';
  try {
    want = gen.renderHeader(bg0);
  } catch (e) {
    fail(e.message);
  }
  const have = fs.existsSync(headerFile) ? fs.readFileSync(headerFile, 'utf8') : '';
  if (have !== want) fail(`${bg0.cpp.header} is stale or missing; run: npm run gen:bind-group0`);
  // pipeline.cpp still carries its own kComputeBindings table until it switches to
  // bind_group0.h (needs a pinned-emsdk rebuild of public/wasm/). Until then the hand
  // table must mirror the contract binding for binding.
  const pipelineCpp = fs.readFileSync(path.join(ROOT, 'wasm_renderer/pipeline.cpp'), 'utf8');
  if (!/#include "bind_group0\.h"/.test(pipelineCpp)) {
    const legacyKind = {
      FilteringSampler: 'filteringSampler', NonFilteringSampler: 'nonFilteringSampler',
      ComparisonSampler: 'comparisonSampler', SampledRgba: 'sampledColor',
      SampledRgbaArray: 'sampledColorArray', SampledR32: 'sampledDepth', StorageRgba: 'storageColor',
      StorageR32: 'storageDepth', UniformBuffer: 'uniformBuffer', StorageBuffer: 'storageBuffer',
      ReadOnlyStorageBuffer: 'readOnlyStorageBuffer',
    };
    const rows = [...pipelineCpp.matchAll(/\{\s*(\d+),\s*BindingKind::(\w+),\s*BindingResource::(\w+)\s*\}/g)];
    if (rows.length !== bg0.bindings.length) {
      fail(`pipeline.cpp kComputeBindings has ${rows.length} rows; bind_group0.json has ${bg0.bindings.length}`);
    }
    for (const [, binding, kind, resource] of rows) {
      const want = bg0.bindings[Number(binding)];
      if (!want || legacyKind[kind] !== want.kind || resource !== want.resource) {
        fail(`pipeline.cpp kComputeBindings binding ${binding} (${kind}, ${resource}) does not match bind_group0.json`);
      }
    }
  }
  const pipelineTs = fs.readFileSync(path.join(ROOT, 'src/renderer/webgpu/pipeline.ts'), 'utf8');
  if (!pipelineTs.includes("contracts/bind_group0.json'") || !pipelineTs.includes('bindGroup0Contract.bindings.map')) {
    fail('src/renderer/webgpu/pipeline.ts must build computeBGL from src/contracts/bind_group0.json');
  }
  const depthNames = bg0.bindings.filter((b) => b.kind === 'sampledDepth').map((b) => b.name);
  const filteringNames = bg0.bindings.filter((b) => b.kind === 'filteringSampler').map((b) => b.name);
  const re = new RegExp(
    `textureSample\\w*\\(\\s*(${depthNames.join('|')})\\s*,\\s*(${filteringNames.join('|')})\\b`,
  );
  const shaderDir = path.join(ROOT, 'public/shaders');
  for (const f of fs.readdirSync(shaderDir)) {
    if (!f.endsWith('.wgsl')) continue;
    const src = stripWgslComments(fs.readFileSync(path.join(shaderDir, f), 'utf8'));
    const m = src.match(re);
    if (m) {
      fail(`public/shaders/${f}: samples ${m[1]} (unfilterable-float) with filtering ${m[2]}; use non_filtering_sampler or textureLoad`);
    }
  }
}

if (!ONLY_WASM_INVARIANTS) {
  verifyLimitsHeader();
  verifyBindGroup0();
  verifyDeepWorkgroupLimits();
  verifyBufferSizeLimits();
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

  // WGPUFeatureName_* / WGPUDeviceLostReason_* are enum members, not macros:
  // an #ifdef on them is always false and silently compiles the feature out
  // (timestamp-query and subgroups were dead in every artifact until 2026-10).
  const cppDir = path.join(ROOT, 'wasm_renderer');
  for (const f of fs.readdirSync(cppDir).filter((n) => /\.(cpp|h)$/.test(n))) {
    const src = fs.readFileSync(path.join(cppDir, f), 'utf8');
    const m = src.match(/#\s*if(?:n?def|\s+defined\s*\(?)\s*(WGPU(?:FeatureName|DeviceLostReason)_\w+)/);
    if (m) {
      fail(`wasm_renderer/${f}: preprocessor guard on enum member ${m[1]} is always false; test it at runtime instead`);
    }
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
  verifyCanvasCapabilities(c, file);

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
    for (const cap of Object.keys(c.optIn || {})) {
      if (!body.includes(`optIns.${cap}`)) {
        fail(`${tsFile} buildCanvasConfigureOptions must read capability optIns.${cap} (canvas_configure.json optIn)`);
      }
    }
  }
  if (!/TEXTURE_USAGE_FALLBACK[^=]*=\s*canvasConfigureContract\.usageBits/.test(ts)) {
    fail(`${tsFile} TEXTURE_USAGE_FALLBACK must come from canvasConfigureContract.usageBits`);
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
    verifyEmJsConfigureFromHeader(c.cpp.jsConfigureFunction, body, /usage:\s*usage\s*>>>\s*0/);
    verifyHeaderCallSite(cpp, c.cpp.jsConfigureFunction, 'kUsage');
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
    const code = stripCppComments(body);
    if (!/config\.alphaMode\s*=\s*canvas_configure::kAlphaMode;/.test(code)) {
      fail(`device.cpp ${c.cpp.surfaceConfigureFunction} alphaMode must be canvas_configure::kAlphaMode`);
    }
    if (!/config\.presentMode\s*=\s*canvas_configure::kPresentMode;/.test(code)) {
      fail(`device.cpp ${c.cpp.surfaceConfigureFunction} presentMode must be canvas_configure::kPresentMode`);
    }
    const literal = code.match(/\b(WGPUTextureUsage_\w+|WGPUCompositeAlphaMode_\w+|WGPUPresentMode_\w+)/);
    if (literal) {
      fail(`device.cpp ${c.cpp.surfaceConfigureFunction} must take usage/alphaMode/presentMode from canvas_configure.h (found ${literal[1]})`);
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
 * canvas_configure.json optIn is the capabilities object: each entry names the
 * configure keys it controls and the backends that implement it. The C++
 * header is generated from the same JSON and must be current.
 */
function verifyCanvasCapabilities(c, file) {
  // `format`: the HDR canvas (#1512) swaps the swapchain format; the caller still passes the preferred one.
  const known = new Set(['usage', 'colorSpace', 'toneMapping', 'format']);
  const caps = c.optIn || {};
  for (const [name, cap] of Object.entries(caps)) {
    const backends = cap.backends || [];
    if (!backends.includes('ts') || backends.some((b) => b !== 'ts' && b !== 'wasm')) {
      fail(`${file} optIn.${name}.backends must include "ts" and only name "ts" / "wasm" (got ${JSON.stringify(cap.backends)})`);
    }
    const keys = cap.configureKeys || [];
    if (keys.length === 0 || keys.some((k) => !known.has(k))) {
      fail(`${file} optIn.${name}.configureKeys must be a non-empty subset of ${[...known].join(', ')}`);
    }
    if (cap.requires !== undefined && !caps[cap.requires]) {
      fail(`${file} optIn.${name}.requires names unknown capability '${cap.requires}'`);
    }
    if (backends.includes('wasm') && !c.cpp?.[name]) {
      fail(`${file} optIn.${name} lists backend "wasm" but has no cpp.${name} block`);
    }
  }
  for (const name of Object.keys(c.usageBits || {})) {
    if (!c.cpp?.usageEnums?.[name]) fail(`${file} usageBits.${name} has no cpp.usageEnums entry`);
  }

  // The WASM configures may only write keys of capabilities that list "wasm".
  const cppSrc = stripCppComments(fs.readFileSync(CPP_DEVICE, 'utf8'));
  const configures = [...cppSrc.matchAll(/ctx\.configure\(\{([\s\S]*?)\}\)/g)].map((m) => m[1]);
  for (const [name, cap] of Object.entries(caps)) {
    if ((cap.backends || []).includes('wasm')) continue;
    // usage and format are written by every configure (the default path); only TS-only keys are banned.
    for (const key of (cap.configureKeys || []).filter((k) => k !== 'usage' && k !== 'format')) {
      if (configures.some((body) => new RegExp(`\\b${key}\\s*:`).test(body))) {
        fail(`device.cpp ctx.configure sets ${key}, but optIn.${name} does not list backend "wasm"`);
      }
    }
  }

  const gen = require('./gen-canvas-configure-header.js');
  const headerFile = gen.headerPath(c);
  const have = fs.existsSync(headerFile) ? fs.readFileSync(headerFile, 'utf8') : '';
  let want = null;
  try {
    want = gen.renderHeader(c);
  } catch (err) {
    fail(`${c.cpp.header} cannot be generated: ${err.message}`);
  }
  if (want !== null && have !== want) {
    fail(`${c.cpp.header} is stale or missing; run: npm run gen:canvas-configure`);
  }
  if (!/#include "canvas_configure\.h"/.test(fs.readFileSync(CPP_DEVICE, 'utf8'))) {
    fail('device.cpp must #include "canvas_configure.h"');
  }
}

/** An EM_JS ctx.configure body takes usage / alphaMode from its parameters, never literals. */
function verifyEmJsConfigureFromHeader(fn, body, usageRe) {
  if (!usageRe.test(body) || /GPUTextureUsage\./.test(body)) {
    fail(`device.cpp ${fn} usage must be the passed canvas_configure.h value, not a GPUTextureUsage literal`);
  }
  if (!/alphaMode:\s*UTF8ToString\(alphaModePtr\)/.test(body)) {
    fail(`device.cpp ${fn} alphaMode must be UTF8ToString(alphaModePtr) (canvas_configure::kAlphaModeJs)`);
  }
}

/** Every call of an EM_JS configure passes the canvas_configure.h usage constant and kAlphaModeJs. */
function verifyHeaderCallSite(cpp, fn, usageConst) {
  const calls = [...stripCppComments(cpp).matchAll(new RegExp(`=\\s*${fn}\\(([^;]*)\\);`, 'g'))];
  if (calls.length === 0) {
    fail(`device.cpp ${fn}() call not found`);
    return;
  }
  for (const [, args] of calls) {
    if (!args.includes(`canvas_configure::${usageConst}`) || !args.includes('canvas_configure::kAlphaModeJs')) {
      fail(`device.cpp ${fn}() must be called with canvas_configure::${usageConst} and canvas_configure::kAlphaModeJs`);
    }
  }
}

/**
 * C++ canvas COPY_SRC opt-in (canvas_configure.json cpp.copySrc):
 * probe EM_JS uses exactly optIn.copySrc.usage inside a validation error scope,
 * ConfigureSurface() restores render-only after it, the opt-in usage comes from
 * canvas_configure.h and is gated on the flag, and only the setter assigns the flag.
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
    verifyEmJsConfigureFromHeader(cs.probeFunction, body, /usage:\s*want\b/);
    verifyHeaderCallSite(cpp, cs.probeFunction, 'kCopySrcUsage');
    if (!/var want = usage\s*>>>\s*0;/.test(probeFn[0]) || !/\(readback\.usage & want\) !== want/.test(probeFn[0])) {
      fail(`device.cpp ${cs.probeFunction} must configure and read back the passed usage (want = usage >>> 0)`);
    }
    if (!/format:\s*preferredFormat/.test(body)) {
      fail(`device.cpp ${cs.probeFunction} must keep format preferredFormat`);
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

  // ConfigureSurface: kCopySrcUsage (optIn.copySrc.usage) only while the flag is set, else kUsage.
  const wantLine = new RegExp(`config\\.usage\\s*=\\s*${cs.flag}\\s*\\?\\s*canvas_configure::kCopySrcUsage\\s*:\\s*canvas_configure::kUsage;`);
  if (!wantLine.test(surfBody)) {
    fail(`device.cpp ${c.cpp.surfaceConfigureFunction} must have 'config.usage = ${cs.flag} ? canvas_configure::kCopySrcUsage : canvas_configure::kUsage;'`);
  }
  if (optUsage.some((u) => !c.cpp.usageEnums[u])) {
    fail(`canvas_configure.json cpp.usageEnums missing an entry for one of ${optUsage.join(', ')}`);
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
  if (/_initWasmRenderer,_shutdownWasmRenderer/.test(buildSh)) {
    fail('build.sh must not hardcode EXPORTED_FUNCTIONS; use format-wasm-exports.js');
  }
  if (!buildSh.includes('format-wasm-exports.js')) {
    fail('build.sh must invoke scripts/format-wasm-exports.js');
  }
  // build.sh is the only build. A second build file must not come back with
  // its own export/flag lists to keep in sync.
  if (fs.existsSync(path.join(ROOT, 'wasm_renderer/CMakeLists.txt'))) {
    fail('wasm_renderer/CMakeLists.txt was removed: build.sh is the only WASM build (keep one flag/export path)');
  }
}

function verifyWasmCompileFlags() {
  const flags = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'src/contracts/wasm_compile_flags.json'), 'utf8'),
  );
  const buildSh = fs.readFileSync(path.join(ROOT, 'wasm_renderer/build.sh'), 'utf8');
  // The emsdk build lives in wasm.yml (path-filtered + weekly since WASM froze as R&D, #1080).
  const ci = fs.readFileSync(path.join(ROOT, '.github/workflows/wasm.yml'), 'utf8');

  if (!/^\d+\.\d+\.\d+$/.test(flags.emsdkVersion || '')) {
    fail(`wasm_compile_flags.json emsdkVersion must be an exact x.y.z pin, got "${flags.emsdkVersion}"`);
  }
  for (const f of flags.extraFlags || []) {
    if (typeof f !== 'string' || !f.startsWith('-') || f.startsWith('-s')) {
      fail(`wasm_compile_flags.json extraFlags entry "${f}" must be a plain em++ flag (put -s settings in sFlags)`);
    }
  }
  // Profiles layer on the release flags; the debug build must stay out of public/wasm/.
  for (const [name, p] of Object.entries(flags.profiles || {})) {
    for (const f of [...(p.extraFlags || []), ...(p.asan?.extraFlags || [])]) {
      if (typeof f !== 'string' || !f.startsWith('-') || f.startsWith('-s')) {
        fail(`wasm_compile_flags.json profiles.${name} extraFlags entry "${f}" must be a plain em++ flag (put -s settings in sFlags)`);
      }
    }
    for (const f of p.dropExtraFlags || []) {
      if (!(flags.extraFlags || []).includes(f)) fail(`profiles.${name}.dropExtraFlags "${f}" is not a release extraFlags entry`);
    }
    if (p.outDir && (path.isAbsolute(p.outDir) || p.outDir.includes('..') || !p.outDir.startsWith('build/'))) {
      fail(`profiles.${name}.outDir must be under wasm_renderer/build/ (never public/wasm/), got "${p.outDir}"`);
    }
  }
  if (!flags.sFlags.includes('GROWABLE_ARRAYBUFFERS=0')) {
    fail('wasm_compile_flags.json must keep GROWABLE_ARRAYBUFFERS=0 (TextDecoder + resizable heap; re-test Dawn first)');
  }

  // CI setup-emsdk must use the pin, not `latest`.
  const emsdkStep = ci.match(/uses:\s*mymindstorm\/setup-emsdk@[^\n]*[\s\S]*?version:\s*['"]?([^'"\s]+)/g) || [];
  if (emsdkStep.length === 0) fail('wasm.yml: setup-emsdk step with version: not found');
  for (const step of emsdkStep) {
    const v = step.match(/version:\s*['"]?([^'"\s]+)/)[1];
    if (v !== flags.emsdkVersion) {
      fail(`wasm.yml setup-emsdk version "${v}" must equal wasm_compile_flags.json emsdkVersion "${flags.emsdkVersion}"`);
    }
  }

  // build.sh must read the JSON, not hand-copy -s flags.
  if (!buildSh.includes('format-wasm-compile-flags.js')) {
    fail('build.sh must read flags via scripts/format-wasm-compile-flags.js');
  }
  if (!buildSh.includes('emcc-version-gate.sh')) {
    fail('build.sh must run scripts/emcc-version-gate.sh before compiling');
  }
  verifyWasmBuildVariants(flags);

  // Async mode (ASYNCIFY / JSPI) lives only in the contract.
  const pkg = fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8');
  for (const [name, src, comment] of [
    ['build.sh', buildSh, /^\s*#/],
    ['wasm.yml', ci, /^\s*#/],
    ['package.json', pkg, null],
  ]) {
    const code = comment ? src.split('\n').filter((l) => !comment.test(l)).join('\n') : src;
    const m = code.match(/-s\s*(ASYNCIFY|JSPI)\w*/);
    if (m) {
      fail(`${name} hardcodes ${m[0]}; async mode belongs in wasm_compile_flags.json (asyncify / jspi graphs)`);
    }
  }

  for (const [name, src] of [['build.sh', buildSh]]) {
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
    for (const f of flags.extraFlags || []) {
      if (code.split(/\s+/).includes(f)) {
        fail(`${name} hardcodes ${f}; it belongs in wasm_compile_flags.json extraFlags`);
      }
    }
    // No second -s list at all: only the export lists (from wasm_exports.json) are spelled here.
    for (const m of code.matchAll(/(?:^|[\s"'])-s([A-Z][A-Z0-9_]*)/g)) {
      if (m[1] !== 'EXPORTED_FUNCTIONS' && m[1] !== 'EXPORTED_RUNTIME_METHODS') {
        fail(`${name} hardcodes -s${m[1]}; -s settings belong in wasm_compile_flags.json sFlags`);
      }
    }
  }

  verifyWasmCompileSources(flags, buildSh);
}

/**
 * One TU list (wasm_compile_flags.json `sources`) feeds build.sh and the clangd
 * compile database; the database carries build.sh's exact flag list. CMake was
 * removed on purpose (its two-step emdawn compile leaked -sUSE_WEBGPU=1).
 */
function verifyWasmCompileSources(flags, buildSh) {
  const { compileCommands, emccArgs } = require('./format-wasm-compile-flags.js');
  const rendererDir = path.join(ROOT, 'wasm_renderer');
  const onDisk = fs.readdirSync(rendererDir).filter((f) => f.endsWith('.cpp')).sort();
  const sources = Array.isArray(flags.sources) ? flags.sources : [];
  if (JSON.stringify([...sources].sort()) !== JSON.stringify(onDisk)) {
    fail(`wasm_compile_flags.json sources [${sources.join(', ')}] must equal wasm_renderer/*.cpp [${onDisk.join(', ')}]`);
  }
  const code = buildSh.split('\n').filter((l) => !/^\s*#/.test(l)).join('\n');
  if (!/format-wasm-compile-flags\.js"?\s+sources/.test(code)) {
    fail('build.sh must read its TU list via `format-wasm-compile-flags.js sources`');
  }
  if (/\b[\w/$.{}-]+\.cpp\b/.test(code)) {
    fail('build.sh must not list .cpp files; add them to wasm_compile_flags.json sources');
  }
  for (const cm of ['CMakeLists.txt', 'wasm_renderer/CMakeLists.txt']) {
    if (fs.existsSync(path.join(ROOT, cm))) {
      fail(`${cm} must not exist: build.sh is the only WASM build (compile_commands.json comes from npm run wasm:compdb)`);
    }
  }

  const stubCflags = ['--target=wasm32-unknown-emscripten', '--sysroot=/stub/sysroot'];
  const cmds = compileCommands(flags, { cflags: stubCflags, emCache: '/stub/cache', rendererDir });
  const expected = emccArgs(flags);
  const files = cmds.map((c) => path.basename(c.file)).sort();
  if (JSON.stringify(files) !== JSON.stringify([...sources].sort())) {
    fail(`compile_commands.json must have one entry per TU; got [${files.join(', ')}]`);
  }
  for (const c of cmds) {
    if (!path.isAbsolute(c.file) || !path.isAbsolute(c.directory)) {
      fail(`compile_commands.json entry for ${c.file} must use absolute paths`);
    }
    const missing = expected.filter((a) => !c.arguments.includes(a));
    if (missing.length) {
      fail(`compile_commands.json ${path.basename(c.file)} is missing build flags: ${missing.join(' ')}`);
    }
    if (!c.arguments.includes(`-I${rendererDir}`)) {
      fail(`compile_commands.json ${path.basename(c.file)} must include -I${rendererDir}`);
    }
    if (!stubCflags.every((a) => c.arguments.includes(a))) {
      fail(`compile_commands.json ${path.basename(c.file)} must carry em++ --cflags (target / sysroot)`);
    }
  }
  const clangdPath = path.join(rendererDir, '.clangd');
  if (!fs.existsSync(clangdPath)) {
    fail('wasm_renderer/.clangd must exist (strips -s / --use-port from the compile database)');
  } else {
    const clangd = fs.readFileSync(clangdPath, 'utf8');
    for (const f of flags.sFlags) {
      const key = f.split('=')[0];
      if (!clangd.includes(`- -s${key}*`)) {
        fail(`wasm_renderer/.clangd Remove must list -s${key}* (one entry per wasm_compile_flags.json sFlags key)`);
      }
    }
    if (/-\s+-s\*\s*$/m.test(clangd)) fail('wasm_renderer/.clangd must not Remove a bare -s* (it strips -std=c++20)');
  }
  const gitignore = fs.readFileSync(path.join(ROOT, '.gitignore'), 'utf8');
  if (!/^wasm_renderer\/compile_commands\.json$/m.test(gitignore)) {
    fail('.gitignore must list wasm_renderer/compile_commands.json (it embeds the machine emsdk path)');
  }
}

/**
 * Two build graphs from one contract: the top-level ASYNCIFY fallback and the
 * `jspi` primary. Checks they differ only in the async mode, that jspiExports
 * covers every WaitAny site, and that the bridge ccalls exactly those exports
 * with { async: true } (src/wasm/bridge/call.ts SUSPENDING_EXPORTS).
 */
function verifyWasmBuildVariants(flags) {
  if (flags.asyncifyFallback !== true) {
    fail('wasm_compile_flags.json asyncifyFallback must be true — never ship JSPI-only');
  }
  if (!flags.sFlags.includes('ASYNCIFY') || flags.sFlags.some((f) => /^JSPI/.test(f))) {
    fail('wasm_compile_flags.json top-level sFlags is the ASYNCIFY fallback: must contain ASYNCIFY and no JSPI*');
  }
  const j = flags.jspi;
  if (!j || !Array.isArray(j.sFlags) || !Array.isArray(j.jspiExports)) {
    fail('wasm_compile_flags.json must define jspi { sFlags, jspiExports, jsOutputName }');
    return;
  }
  const expected = flags.sFlags.map((f) => (f === 'ASYNCIFY' ? 'JSPI' : f));
  if (JSON.stringify(j.sFlags) !== JSON.stringify(expected)) {
    fail(
      `wasm_compile_flags.json jspi.sFlags must equal fallback sFlags with ASYNCIFY→JSPI.\n  expected ${JSON.stringify(expected)}\n  got      ${JSON.stringify(j.sFlags)}`,
    );
  }
  if (!j.jsOutputName || j.jsOutputName === flags.jsOutputName) {
    fail('wasm_compile_flags.json jspi.jsOutputName must be set and differ from the fallback jsOutputName');
  }

  const exportsJson = JSON.parse(
    fs.readFileSync(path.join(ROOT, 'src/contracts/wasm_exports.json'), 'utf8'),
  );
  const exported = new Set(exportsJson.exportedFunctions);
  const graph = j.waitAnyCallGraph || {};
  for (const name of j.jspiExports) {
    if (!exported.has(`_${name}`)) fail(`jspi.jspiExports ${name} is not in wasm_exports.json exportedFunctions`);
    if (!graph[name]) fail(`jspi.waitAnyCallGraph has no path for ${name}`);
  }
  for (const name of Object.keys(graph)) {
    if (!j.jspiExports.includes(name)) fail(`jspi.waitAnyCallGraph lists ${name} but jspiExports does not`);
  }

  // Every function that calls wgpuInstanceWaitAny must appear in some documented
  // path — a new WaitAny site means a (possibly new) suspending export.
  const graphText = Object.values(graph).join(' ');
  for (const file of walkCppFiles(path.join(ROOT, 'wasm_renderer'))) {
    const src = stripCppComments(fs.readFileSync(file, 'utf8'));
    const defs = [...src.matchAll(/^[A-Za-z][\w:<>\*& ]*?WebGPURenderer::(\w+)\s*\(/gm)].map((m) => ({
      name: m[1],
      at: m.index,
    }));
    for (const call of src.matchAll(/wgpuInstanceWaitAny\s*\(/g)) {
      const owner = defs.filter((d) => d.at < call.index).pop();
      const rel = path.relative(ROOT, file);
      if (!owner) {
        fail(`${rel}: wgpuInstanceWaitAny outside a WebGPURenderer method — add its export path to jspi.waitAnyCallGraph`);
      } else if (!new RegExp(`\\b${owner.name}\\b`).test(graphText)) {
        fail(
          `${rel}: ${owner.name}() calls wgpuInstanceWaitAny but is not on any jspi.waitAnyCallGraph path — find the exports that reach it and add them to jspiExports`,
        );
      }
    }
  }

  const callTs = fs.readFileSync(path.join(ROOT, 'src/wasm/bridge/call.ts'), 'utf8');
  const listMatch = callTs.match(/SUSPENDING_EXPORTS\s*=\s*\[([^\]]*)\]/);
  if (!listMatch) {
    fail('src/wasm/bridge/call.ts must declare SUSPENDING_EXPORTS = [...]');
  } else {
    const bridgeList = [...listMatch[1].matchAll(/['"](\w+)['"]/g)].map((m) => m[1]);
    if (JSON.stringify([...bridgeList].sort()) !== JSON.stringify([...j.jspiExports].sort())) {
      fail(
        `call.ts SUSPENDING_EXPORTS ${JSON.stringify(bridgeList)} must equal jspi.jspiExports ${JSON.stringify(j.jspiExports)}`,
      );
    }
  }
  // No bridge module may ccall a suspending export directly (sync shape).
  const bridgeDir = path.join(ROOT, 'src/wasm/bridge');
  for (const name of fs.readdirSync(bridgeDir)) {
    if (!name.endsWith('.ts') || name === 'call.ts' || name.endsWith('.test.ts')) continue;
    const src = fs.readFileSync(path.join(bridgeDir, name), 'utf8');
    for (const exp of j.jspiExports) {
      if (new RegExp(`\\.ccall\\(\\s*['"]${exp}['"]`).test(src)) {
        fail(`src/wasm/bridge/${name} ccalls '${exp}' directly — use callSuspending() from call.ts`);
      }
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
/** Drop // and block comments so a commented-out declaration does not count. */
function stripWgslComments(wgsl) {
  return wgsl.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

function verifyBindGroup1() {
  const contractPath = path.join(ROOT, 'src/contracts/bind_group1.json');
  const c = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
  const expected = [
    { binding: 0, name: 'simState', bufferType: 'storage' },
    { binding: 1, name: 'simIndex', bufferType: 'read-only-storage' },
    { binding: 2, name: 'simParams', bufferType: 'uniform' },
  ];
  if (c.group !== 1) fail('bind_group1.json group must be 1');
  if (c.version !== 2) fail('bind_group1.json version must be 2 (adds the optional spatialHash binding)');
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

  // Optional spatial hash (binding 3): contract shape, TS layout, WGSL helper constants.
  const h = c.spatialHash || {};
  if (h.binding !== 3 || h.name !== 'simHash' || h.bufferType !== 'storage') {
    fail('bind_group1.json spatialHash must be binding 3 simHash (storage)');
  }
  if (h.wgsl !== 'var<storage, read_write> simHash: array<atomic<u32>>') {
    fail('bind_group1.json spatialHash.wgsl must be `var<storage, read_write> simHash: array<atomic<u32>>`');
  }
  if (h.gridWidth !== 128 || h.gridHeight !== 128) fail('spatialHash grid must be 128 × 128');
  if (h.cellCount !== h.gridWidth * h.gridHeight) fail('spatialHash.cellCount must be gridWidth × gridHeight');
  if (h.headsOffset !== 0 || h.nextOffset !== h.cellCount) {
    fail('spatialHash layout must be heads at 0, then one `next` per agent at cellCount');
  }
  if (h.emptyHead !== 0xffffffff) fail('spatialHash.emptyHead must be 0xFFFFFFFF');
  if (JSON.stringify(h.visitCap) !== '[8,16]') fail('spatialHash.visitCap must be [8, 16]');
  if (h.build?.countsAsPass !== true) fail('spatialHash.build.countsAsPass must be true (the scatter is a counted pass)');
  const hashLimits = h.group1RequiredLimits || {};
  for (const [key, need] of Object.entries(hashLimits)) {
    if (!(key in (c.webgpuBaseLimits || {}))) fail(`webgpuBaseLimits missing ${key}`);
    else if (need > c.webgpuBaseLimits[key]) fail(`spatialHash.group1RequiredLimits.${key}=${need} exceeds WebGPU base ${c.webgpuBaseLimits[key]}`);
    if (need < (c.group1RequiredLimits?.[key] ?? 0)) fail(`spatialHash.group1RequiredLimits.${key} must not be below the base ring's`);
  }
  if (hashLimits.maxStorageBuffersPerShaderStage !== (c.group1RequiredLimits?.maxStorageBuffersPerShaderStage ?? 0) + 1) {
    fail('spatialHash needs exactly one more storage buffer than the base ring (simHash)');
  }
  const hashBgl = ts.match(/export function createSimRingHashBindGroupLayout[\s\S]*?\n\}/);
  if (!hashBgl) {
    fail(`${tsFile} must export createSimRingHashBindGroupLayout`);
  } else {
    const hashEntries = [...hashBgl[0].matchAll(/\{\s*binding:\s*([\w_]+)[^}]*buffer:\s*\{\s*type:\s*'([a-z-]+)'\s*\}/g)];
    const want = [...expected.map((e) => [String(e.binding), e.bufferType]), ['SIM_HASH_BINDING', 'storage']];
    if (hashEntries.length !== want.length || hashEntries.some((m, i) => m[1] !== want[i][0] || m[2] !== want[i][1])) {
      fail(`${tsFile} createSimRingHashBindGroupLayout must be bindings 0–2 as the base ring plus SIM_HASH_BINDING 'storage'`);
    }
  }
  const hashTs = fs.readFileSync(path.join(ROOT, 'src/renderer/webgpu/simHash.ts'), 'utf8');
  if (!/import bindGroup1Contract from '..\/..\/contracts\/bind_group1\.json'/.test(hashTs)) {
    fail('src/renderer/webgpu/simHash.ts must import bind_group1.json (grid and offsets come from the contract)');
  }
  const helperFile = 'public/shaders/_sim_hash.wgsl';
  const helper = stripWgslComments(fs.readFileSync(path.join(ROOT, helperFile), 'utf8'));
  const wgslConst = (name) => {
    const m = helper.match(new RegExp(`const\\s+${name}\\s*:\\s*u32\\s*=\\s*(0x[0-9A-Fa-f]+|\\d+)u\\s*;`));
    return m ? Number(m[1]) : null;
  };
  for (const [name, want] of [
    ['HASH_GRID', h.gridWidth],
    ['HASH_CELLS', h.cellCount],
    ['HASH_NEXT', h.nextOffset],
    ['HASH_EMPTY', h.emptyHead],
  ]) {
    if (wgslConst(name) !== want) fail(`${helperFile} const ${name} must equal bind_group1.json spatialHash (${want})`);
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
    const body = bridge.match(new RegExp(`export async function ${fnName}\\([\\s\\S]*?\\n\\}`));
    const refuse = body ? body[0].indexOf('declaresBindGroup1(') : -1;
    const ccall = body ? body[0].indexOf(`callSuspending(wasmRef.module, '${fnName}'`) : -1;
    if (refuse < 0 || ccall < 0 || refuse > ccall) {
      fail(`${bridgeFile} ${fnName} must refuse @group(1) WGSL before callSuspending(wasmRef.module, '${fnName}')`);
    }
  }

  // Definitions that opt into the ring must dispatch at least one simState node.
  // simRing.spatialHash is the same kind of promise: the graph has to read the simHash role (so the
  // planner builds it) in an entry that declares binding 3, and nothing may read it without asking.
  const entryDeclaresHash = (entry) => {
    const file = path.join(ROOT, 'public/shaders', `${entry}.wgsl`);
    if (!fs.existsSync(file)) return null;
    return /@group\(\s*1\s*\)\s*@binding\(\s*3\s*\)/.test(stripWgslComments(fs.readFileSync(file, 'utf8')));
  };
  const defsDir = path.join(ROOT, 'shader_definitions');
  const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : e.name.endsWith('.json') ? [path.join(dir, e.name)] : []);
  for (const file of walk(defsDir)) {
    let def;
    try { def = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { continue; }
    const rel = path.relative(ROOT, file);
    const graphNodes = def.multipass?.graph?.nodes || [];
    const hashReaders = graphNodes.filter((n) => (n.reads || []).includes('simHash'));
    const declaring = graphNodes.filter((n) => entryDeclaresHash(n.entry) === true);
    if (!def.simRing?.spatialHash && (hashReaders.length > 0 || declaring.length > 0)) {
      fail(`${rel} reads or declares simHash but simRing.spatialHash is not set`);
    }
    if (!def.simRing) continue;
    if (def.simRing.spatialHash !== undefined && typeof def.simRing.spatialHash !== 'boolean') {
      fail(`${rel} simRing.spatialHash must be a boolean`);
    }
    if (def.simRing.spatialHash === true) {
      if (hashReaders.length === 0) {
        fail(`${rel} sets simRing.spatialHash but no graph node reads the simHash role`);
      }
      for (const n of hashReaders) {
        if (entryDeclaresHash(n.entry) === false) {
          fail(`${rel} node ${n.id} reads simHash but ${n.entry}.wgsl does not declare @group(1) @binding(3) simHash`);
        }
      }
      if (hashReaders.length > 0 && !hashReaders.some((n) => entryDeclaresHash(n.entry) !== false)) {
        fail(`${rel} sets simRing.spatialHash but never reads the binding`);
      }
    }
    const nodes = graphNodes;
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

/** True when `rel` is tracked by git (a committed artifact, not a fresh CI build). */
function isGitTracked(rel) {
  try {
    require('child_process').execFileSync('git', ['ls-files', '--error-unmatch', rel], {
      cwd: ROOT,
      stdio: 'ignore',
    });
    return true;
  } catch {
    return false;
  }
}

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

    const pending = new Set(inv.artifactsPendingPinnedBuild || []);
    for (const rel of ban.wasmArtifacts || [ban.wasmArtifact || 'public/wasm/pixelocity_wasm.wasm']) {
      const artifact = path.join(ROOT, rel);
      if (!fs.existsSync(artifact)) {
        if (pending.has(rel)) {
          console.log(`⏳ ${rel} not built yet (artifactsPendingPinnedBuild) — import table unchecked`);
          continue;
        }
        fail(`missing wasm artifact ${rel}`);
        continue;
      }
      if (pending.has(rel) && isGitTracked(rel)) {
        fail(`${rel} is committed — remove it from wasm_runtime_invariants.json artifactsPendingPinnedBuild`);
      }
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
            `${rel} import table contains forbidden ${forbidden} (must be DCE'd; do not call ${ban.symbol})`,
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
        `${pipelineFile} kComputeBindings must declare bindings 2/7/8 as BindingKind::StorageRgba ` +
          `(layout format = RgbaStorageFormat(colorFormat_)); found ${bglHits.length} of ${wantBgl}`,
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
