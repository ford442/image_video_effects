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

const artifacts = [
  { path: 'public/wasm/pixelocity_wasm.wasm', type: 'wasm', min: MIN_WASM_SIZE, max: MAX_WASM_SIZE },
  { path: 'public/wasm/pixelocity_wasm.js', type: 'js-module', min: 10 * 1024 }, // 10 KB min
  { path: 'public/wasm/wasm_bridge.js', type: 'js-glue', min: 5 * 1024 }, // 5 KB min
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
 * Fail if canonical wasm_renderer bridge copies drift from src/wasm/ (dev import path).
 */
function checkBridgeSkew() {
  const pairs = [
    ['wasm_renderer/wasm_bridge.js', 'src/wasm/wasm_bridge.js'],
    ['wasm_renderer/wasm_bridge.d.ts', 'src/wasm/wasm_bridge.d.ts'],
  ];

  for (const [canonicalRel, copyRel] of pairs) {
    const canonicalPath = path.resolve(canonicalRel);
    const copyPath = path.resolve(copyRel);

    if (!fs.existsSync(canonicalPath)) {
      errors.push(`❌ ${canonicalRel}: canonical bridge file not found`);
      allValid = false;
      continue;
    }

    if (!fs.existsSync(copyPath)) {
      errors.push(`❌ ${copyRel}: bridge copy missing (expected sync from ${canonicalRel})`);
      allValid = false;
      continue;
    }

    const canonical = fs.readFileSync(canonicalPath);
    const copy = fs.readFileSync(copyPath);

    if (!canonical.equals(copy)) {
      errors.push(
        `❌ Bridge skew detected (${canonicalRel} vs ${copyRel}) — run npm run wasm:build or cp wasm_renderer/wasm_bridge.js src/wasm/`
      );
      allValid = false;
    } else {
      console.log(`Bridge sync: ✅ ${copyRel} matches ${canonicalRel}`);
    }
  }

  console.log('');
}

checkBridgeSkew();

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
