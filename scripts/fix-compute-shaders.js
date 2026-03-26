#!/usr/bin/env node
/**
 * WGSL Compute Shader Fixer
 * Fixes common issues when shaders are used as compute shaders:
 * 1. textureSample -> textureSampleLevel with explicit LOD
 * 2. Other fragment-only operations
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const DRY_RUN = process.argv.includes('--dry-run');
const SHADER_DIR = process.argv.slice(2).find(a => !a.startsWith('--')) || './public/shaders';

// Patterns that need fixing for compute shaders
const FIXES = [
  {
    name: 'textureSample without LOD',
    // Match textureSample(texture, sampler, coords) but not textureSampleLevel
    pattern: /textureSample\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*([^,)]+)\s*\)/g,
    replacement: 'textureSampleLevel($1, $2, $3, 0.0)',
    reason: 'Compute shaders require explicit LOD (use textureSampleLevel)'
  }
];

function findWgslFiles(dir) {
  const files = [];
  function walk(currentDir) {
    const entries = fs.readdirSync(currentDir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
      } else if (entry.name.endsWith('.wgsl')) {
        files.push(fullPath);
      }
    }
  }
  walk(dir);
  return files;
}

function needsComputeFixes(content) {
  // Check if it's a compute shader
  if (!content.includes('@compute') && !content.includes('@workgroup_size')) {
    return false;
  }
  
  // Check for problematic patterns
  return FIXES.some(fix => fix.pattern.test(content));
}

function applyFixes(content) {
  let fixed = content;
  const applied = [];
  
  for (const fix of FIXES) {
    const before = fixed;
    fixed = fixed.replace(fix.pattern, fix.replacement);
    if (fixed !== before) {
      applied.push(fix.name);
    }
  }
  
  return { content: fixed, applied };
}

function validateWithNaga(filePath) {
  try {
    execSync(`naga "${filePath}"`, { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

function main() {
  console.log('\n🔧 WGSL Compute Shader Fixer\n');
  
  if (DRY_RUN) {
    console.log('🏃 DRY RUN - no changes will be made\n');
  }
  
  // Check naga is available
  try {
    execSync('which naga', { stdio: 'ignore' });
  } catch {
    console.error('❌ naga not found. Install with: cargo install naga-cli');
    process.exit(1);
  }
  
  const shaders = findWgslFiles(SHADER_DIR);
  console.log(`Found ${shaders.length} WGSL files\n`);
  
  let checked = 0;
  let needsFix = 0;
  let fixed = 0;
  let failed = 0;
  
  for (const shader of shaders) {
    const content = fs.readFileSync(shader, 'utf8');
    
    if (!needsComputeFixes(content)) {
      continue;
    }
    
    checked++;
    const relativePath = path.relative('.', shader);
    
    const { content: fixedContent, applied } = applyFixes(content);
    
    if (applied.length === 0) {
      continue;
    }
    
    needsFix++;
    console.log(`\n📄 ${relativePath}`);
    console.log(`   Issues found: ${applied.join(', ')}`);
    
    if (!DRY_RUN) {
      // Backup original
      fs.writeFileSync(shader + '.backup', content);
      
      // Write fixed version
      fs.writeFileSync(shader, fixedContent);
      
      // Validate with naga
      if (validateWithNaga(shader)) {
        console.log('   ✅ Fixed and validated');
        fixed++;
        // Remove backup if successful
        fs.unlinkSync(shader + '.backup');
      } else {
        console.log('   ❌ Fix failed validation, restoring backup');
        fs.writeFileSync(shader, content);
        failed++;
      }
    }
  }
  
  console.log(`\n${'═'.repeat(60)}`);
  console.log('\n📊 Summary:');
  console.log(`   Compute shaders checked: ${checked}`);
  console.log(`   Needing fixes: ${needsFix}`);
  
  if (!DRY_RUN) {
    console.log(`   ✅ Successfully fixed: ${fixed}`);
    console.log(`   ❌ Failed to fix: ${failed}`);
    if (failed > 0) {
      console.log('\n   Backup files (.backup) kept for failed fixes');
    }
  } else {
    console.log(`   Would fix: ${needsFix}`);
    console.log('\n   Run without --dry-run to apply fixes');
  }
  
  console.log();
}

main();
