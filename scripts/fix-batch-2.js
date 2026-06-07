#!/usr/bin/env node
/**
 * Batch WGSL Shader Fixer - Round 2
 * Fixes remaining shaders with specific patterns
 */

const fs = require('fs');
const { execSync } = require('child_process');

const WORKSPACE = '/root/.openclaw/workspace/effects_repo';

const SHADERS_TO_FIX = [
  'public/shaders/aurora-rift-gemini.wgsl',
  'public/shaders/datamosh.wgsl',
  'public/shaders/fire_smoke_volumetric.wgsl',
  'public/shaders/gen_kimi_crystal.wgsl',
  'public/shaders/gen_kimi_nebula.wgsl',
  'public/shaders/entropy-grid.wgsl',
  'public/shaders/gen-liquid-crystal-hive-mind.wgsl',
  'public/shaders/gen-stellar-web-loom.wgsl',
  'public/shaders/frosted-glass-lens.wgsl',
  'public/shaders/sim-decay-system.wgsl',
  'public/shaders/sim-slime-mold-growth.wgsl',
  'public/shaders/split-flap-display.wgsl',
];

function getNagaError(shaderPath) {
  try {
    execSync(`cd ${WORKSPACE} && naga "${shaderPath}"`, { stdio: 'pipe' });
    return null;
  } catch (error) {
    return error.stderr?.toString() || error.message || '';
  }
}

function fixTextureSampleInCompute(content) {
  // Replace textureSample with textureSampleLevel in compute shaders
  let fixed = content;
  
  // Pattern: textureSample(texture, sampler, uv)
  // But not textureSampleLevel
  fixed = fixed.replace(
    /textureSample\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*([^,)]+)\s*\)/g,
    'textureSampleLevel($1, $2, $3, 0.0)'
  );
  
  return fixed;
}

function fixMissingAudioReactivity(content) {
  // Add audioReactivity definition if missing
  if (content.includes('audioReactivity') && !content.includes('let audioReactivity')) {
    return content.replace(
      /(let time = u\.config\.x[^;]*;)/,
      `$1\n    let audioReactivity = u.zoom_config.x;`
    );
  }
  return content;
}

function fixMissingAudioOverall(content) {
  // Add audioOverall definition if missing
  if (content.includes('audioOverall') && !content.includes('let audioOverall')) {
    return content.replace(
      /(let time = u\.config\.x[^;]*;)/,
      `$1\n    let audioOverall = u.zoom_config.x;`
    );
  }
  return content;
}

function attemptFix(shaderPath) {
  const fullPath = `${WORKSPACE}/${shaderPath}`;
  let content = fs.readFileSync(fullPath, 'utf8');
  const error = getNagaError(shaderPath);
  
  if (!error) return { alreadyValid: true };
  
  let fixes = [];
  
  // Fix 1: textureSample in compute shaders
  if (error.includes('stage') && error.includes('forbidden')) {
    const before = content;
    content = fixTextureSampleInCompute(content);
    if (content !== before) fixes.push('textureSample→textureSampleLevel');
  }
  
  // Fix 2: Missing audioReactivity
  if (error.includes('audioReactivity') && error.includes('no definition')) {
    const before = content;
    content = fixMissingAudioReactivity(content);
    if (content !== before) fixes.push('added audioReactivity');
  }
  
  // Fix 3: Missing audioOverall
  if (error.includes('audioOverall') && error.includes('no definition')) {
    const before = content;
    content = fixMissingAudioOverall(content);
    if (content !== before) fixes.push('added audioOverall');
  }
  
  if (fixes.length === 0) {
    return { fixed: false, error: error.substring(0, 80) };
  }
  
  // Backup and write
  fs.writeFileSync(fullPath + '.backup', fs.readFileSync(fullPath, 'utf8'));
  fs.writeFileSync(fullPath, content);
  
  // Verify
  const newError = getNagaError(shaderPath);
  if (!newError) {
    fs.unlinkSync(fullPath + '.backup');
    return { fixed: true, fixes };
  } else {
    fs.writeFileSync(fullPath, fs.readFileSync(fullPath + '.backup', 'utf8'));
    return { fixed: false, error: newError.substring(0, 80) };
  }
}

function main() {
  console.log('🔧 Batch Shader Fixer - Round 2\n');
  
  let fixed = 0;
  let failed = 0;
  
  for (const shader of SHADERS_TO_FIX) {
    const result = attemptFix(shader);
    
    if (result.alreadyValid) {
      console.log(`✅ Already valid: ${shader}`);
      fixed++;
    } else if (result.fixed) {
      console.log(`✅ Fixed: ${shader} (${result.fixes.join(', ')})`);
      fixed++;
    } else {
      console.log(`❌ Failed: ${shader}`);
      console.log(`   ${result.error}`);
      failed++;
    }
  }
  
  console.log(`\n${'═'.repeat(60)}`);
  console.log(`\n📊 Results: ${fixed} fixed, ${failed} failed`);
}

main();
