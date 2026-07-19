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

const EXPECTED_LIMITS = {
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
  for (const [key, val] of Object.entries(EXPECTED_LIMITS)) {
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
    const m = block.match(
      new RegExp(`CheckLimit\\("${key}",\\s*limits\\.${key},\\s*(\\d+)`),
    );
    if (!m) throw new Error(`CheckLimit("${key}", ...) not found in adapter block`);
    out[key] = parseInt(m[1], 10);
    if (out[key] !== expected) {
      throw new Error(`CheckLimit ${key} need=${m[1]} does not match expected ${expected}`);
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
  if (cppCheck[key] !== expected) {
    console.error(`C++ CheckLimit ${key}: expected ${expected}, got ${cppCheck[key]}`);
    failed = true;
  }
}

if (failed) {
  process.exit(1);
}

console.log('✅ Device policy sync OK (TS MINIMUM_COMPUTE_LIMITS ↔ device.cpp CheckLimit + requiredLimits)');
