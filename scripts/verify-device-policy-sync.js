#!/usr/bin/env node
/**
 * verify-device-policy-sync.js
 *
 * CI check: MINIMUM_COMPUTE_LIMITS in webgpuDevicePolicy.ts must match
 * device.cpp CheckLimit / requiredLimits values.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const TS_POLICY = path.join(ROOT, 'src/renderer/webgpuDevicePolicy.ts');
const CPP_DEVICE = path.join(ROOT, 'wasm_renderer/device.cpp');

const EXPECTED = {
  maxBindingsPerBindGroup: 14,
  maxSampledTexturesPerShaderStage: 3,
  maxSamplersPerShaderStage: 3,
  maxStorageTexturesPerShaderStage: 4,
  maxStorageBuffersPerShaderStage: 2,
  maxUniformBuffersPerShaderStage: 1,
  maxComputeWorkgroupSizeX: 16,
  maxComputeWorkgroupSizeY: 16,
  maxComputeInvocationsPerWorkgroup: 256,
};

function extractTsLimits() {
  const src = fs.readFileSync(TS_POLICY, 'utf8');
  const block = src.match(/MINIMUM_COMPUTE_LIMITS\s*=\s*\{([^}]+)\}/s);
  if (!block) throw new Error('MINIMUM_COMPUTE_LIMITS not found in TS policy');
  const out = {};
  for (const [key, val] of Object.entries(EXPECTED)) {
    const m = block[1].match(new RegExp(`${key}:\\s*(\\d+)`));
    if (!m) throw new Error(`Missing ${key} in TS MINIMUM_COMPUTE_LIMITS`);
    out[key] = parseInt(m[1], 10);
  }
  return out;
}

function extractCppBindingsLimit() {
  const src = fs.readFileSync(CPP_DEVICE, 'utf8');
  const m = src.match(/requiredLimits\.maxBindingsPerBindGroup\s*=\s*(\d+)/);
  if (!m) throw new Error('requiredLimits.maxBindingsPerBindGroup not found in device.cpp');
  return parseInt(m[1], 10);
}

const ts = extractTsLimits();
const cppBindings = extractCppBindingsLimit();
let failed = false;

for (const [key, expected] of Object.entries(EXPECTED)) {
  if (ts[key] !== expected) {
    console.error(`TS ${key}: expected ${expected}, got ${ts[key]}`);
    failed = true;
  }
}

if (cppBindings !== EXPECTED.maxBindingsPerBindGroup) {
  console.error(`C++ maxBindingsPerBindGroup: expected ${EXPECTED.maxBindingsPerBindGroup}, got ${cppBindings}`);
  failed = true;
}

if (failed) {
  process.exit(1);
}

console.log('✅ Device policy sync OK (TS MINIMUM_COMPUTE_LIMITS ↔ device.cpp)');
