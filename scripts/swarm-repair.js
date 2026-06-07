#!/usr/bin/env node
/**
 * Shader Repair Swarm Orchestrator
 * Spawns subagents to fix invalid WGSL shaders in parallel
 */

const fs = require('fs');
const { execSync } = require('child_process');

// Configuration
const SWARM_SIZE = 4; // Number of parallel agents
const SHADERS_FILE = '/tmp/invalid_shaders.txt';
const WORKSPACE = '/root/.openclaw/workspace/effects_repo';

function readShaderList() {
  return fs.readFileSync(SHADERS_FILE, 'utf8')
    .split('\n')
    .filter(f => f.trim());
}

function chunkArray(array, chunks) {
  const result = [];
  const chunkSize = Math.ceil(array.length / chunks);
  for (let i = 0; i < array.length; i += chunkSize) {
    result.push(array.slice(i, i + chunkSize));
  }
  return result;
}

function getNagaError(shaderPath) {
  try {
    execSync(`cd ${WORKSPACE} && naga "${shaderPath}"`, { stdio: 'pipe' });
    return null;
  } catch (error) {
    return error.stderr?.toString() || error.message || '';
  }
}

function attemptFix(shaderPath, error) {
  const fullPath = `${WORKSPACE}/${shaderPath}`;
  let content = fs.readFileSync(fullPath, 'utf8');
  let fixed = false;
  let appliedFixes = [];
  
  // Fix 1: textureSample -> textureSampleLevel in compute shaders
  if (error.includes('stage') && error.includes('forbidden') && content.includes('textureSample(')) {
    const before = content;
    content = content.replace(
      /textureSample\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*([^,)]+)\s*\)/g,
      'textureSampleLevel($1, $2, $3, 0.0)'
    );
    if (content !== before) {
      appliedFixes.push('textureSample->textureSampleLevel');
      fixed = true;
    }
  }
  
  // Fix 2: signed/unsigned comparison with arrayLength
  if (error.includes('Sint') && error.includes('Uint') && error.includes('Less')) {
    const before = content;
    // Match patterns like: idx < arrayLength(
    content = content.replace(
      /if\s*\(\s*(\w+)\s*<\s*arrayLength\(/g,
      'if (u32($1) < arrayLength('
    );
    // Also handle <= comparisons
    content = content.replace(
      /if\s*\(\s*(\w+)\s*<=\s*arrayLength\(/g,
      'if (u32($1) <= arrayLength('
    );
    if (content !== before) {
      appliedFixes.push('i32-u32 comparison cast');
      fixed = true;
    }
  }
  
  // Fix 3: floor() on integer vectors
  if (error.includes('floor') && error.includes('u32')) {
    const before = content;
    // Pattern: floor(global_id.xy / ...)
    content = content.replace(
      /floor\s*\(\s*global_id\.xy\s*\/\s*(\w+)/g,
      'floor(vec2<f32>(global_id.xy) / $1'
    );
    // Pattern: floor(some_vec2<u32>)
    content = content.replace(
      /floor\s*\(\s*([^)]+)\s*\)/g,
      (match, p1) => {
        if (p1.includes('global_id') || p1.includes('u32')) {
          return `floor(vec2<f32>(${p1}))`;
        }
        return match;
      }
    );
    if (content !== before) {
      appliedFixes.push('floor() integer cast');
      fixed = true;
    }
  }
  
  // Fix 4: textureSample with offset in compute
  if (error.includes('stage') && content.includes('textureSample(') && content.includes('vec2<i32>')) {
    const before = content;
    content = content.replace(
      /textureSample\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*([^,)]+)\s*,\s*vec2<i32>\s*\(([^)]+)\)\s*\)/g,
      'textureSampleLevel($1, $2, $3 + vec2<f32>(vec2<i32>($4)) / vec2<f32>(textureDimensions($1)), 0.0)'
    );
    if (content !== before) {
      appliedFixes.push('textureSample offset->textureSampleLevel');
      fixed = true;
    }
  }
  
  if (fixed) {
    // Backup original
    fs.writeFileSync(fullPath + '.backup', fs.readFileSync(fullPath, 'utf8'));
    fs.writeFileSync(fullPath, content);
    
    // Verify fix
    const newError = getNagaError(shaderPath);
    if (!newError) {
      fs.unlinkSync(fullPath + '.backup');
      return { success: true, fixes: appliedFixes };
    } else {
      // Restore backup
      fs.writeFileSync(fullPath, fs.readFileSync(fullPath + '.backup', 'utf8'));
      return { success: false, error: newError.substring(0, 200) };
    }
  }
  
  return { success: false, error: error.substring(0, 200) };
}

// Main
const invalidShaders = readShaderList();
console.log(`🔧 Shader Repair Swarm
`);
console.log(`Invalid shaders: ${invalidShaders.length}`);
console.log(`Working directory: ${WORKSPACE}\n`);

// Process each shader
let fixed = 0;
let failed = 0;
let skipped = 0;

for (const shader of invalidShaders) {
  const error = getNagaError(shader);
  if (!error) {
    console.log(`✅ Already valid: ${shader}`);
    continue;
  }
  
  const result = attemptFix(shader, error);
  
  if (result.success) {
    console.log(`✅ Fixed: ${shader} (${result.fixes.join(', ')})`);
    fixed++;
  } else {
    console.log(`❌ Failed: ${shader}`);
    console.log(`   Error: ${result.error?.substring(0, 80)}...`);
    failed++;
  }
}

console.log(`\n${'═'.repeat(60)}`);
console.log(`\n📊 Results:`);
console.log(`   ✅ Fixed: ${fixed}`);
console.log(`   ❌ Failed: ${failed}`);
console.log(`   Success rate: ${Math.round(fixed / (fixed + failed) * 100)}%`);

// Update validation report
execSync(`cd ${WORKSPACE} && node scripts/validate-naga.js --json`, { stdio: 'inherit' });
