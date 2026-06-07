#!/usr/bin/env node
/**
 * Comprehensive WGSL Fixer using Naga validation
 * Fixes common WGSL issues detected by naga
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const DRY_RUN = process.argv.includes('--dry-run');
const FIX_ALL = process.argv.includes('--fix-all');
const SHADER_DIR = process.argv.slice(2).find(a => !a.startsWith('--')) || './public/shaders';

const FIXES = [
  {
    name: 'textureSample without LOD in compute',
    test: (content, error) => error.includes('textureSample') && error.includes('stage'),
    pattern: /textureSample\s*\(\s*(\w+)\s*,\s*(\w+)\s*,\s*([^,)]+)\s*\)/g,
    replacement: 'textureSampleLevel($1, $2, $3, 0.0)',
  },
  {
    name: 'signed/unsigned int comparison (arrayLength)',
    test: (content, error) => error.includes('Less') && error.includes('Sint') && error.includes('Uint'),
    transform: (content) => {
      // Fix comparisons between i32 and u32 from arrayLength
      // Pattern: idx < arrayLength(...) where idx is i32
      return content.replace(
        /if\s*\(\s*(\w+)\s*<\s*arrayLength\(/g,
        'if (u32($1) < arrayLength('
      );
    }
  },
  {
    name: 'floor on integer vector',
    test: (content, error) => error.includes('floor') && error.includes('u32'),
    transform: (content) => {
      // Fix floor() on integer division - cast to f32 first
      // Pattern: floor(global_id.xy / something)
      return content.replace(
        /floor\s*\(\s*global_id\.xy\s*/g,
        'floor(vec2<f32>(global_id.xy) '
      );
    }
  }
];

function findWgslFiles(dir) {
  const files = [];
  function walk(currentDir) {
    const entries = fs.readdirSync(currentDir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) walk(fullPath);
      else if (entry.name.endsWith('.wgsl')) files.push(fullPath);
    }
  }
  walk(dir);
  return files;
}

function getNagaError(filePath) {
  try {
    execSync(`naga "${filePath}"`, { stdio: 'pipe' });
    return null;
  } catch (error) {
    return error.stderr?.toString() || error.message || '';
  }
}

function tryFix(content, error) {
  let fixed = content;
  const applied = [];
  
  for (const fix of FIXES) {
    if (fix.test(content, error)) {
      if (fix.transform) {
        const before = fixed;
        fixed = fix.transform(fixed);
        if (fixed !== before) applied.push(fix.name);
      } else if (fix.pattern) {
        const before = fixed;
        fixed = fixed.replace(fix.pattern, fix.replacement);
        if (fixed !== before) applied.push(fix.name);
      }
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
  console.log('\n🔧 Naga-Based WGSL Fixer\n');
  
  if (DRY_RUN) console.log('🏃 DRY RUN - no changes will be made\n');
  
  try {
    execSync('which naga', { stdio: 'ignore' });
  } catch {
    console.error('❌ naga not found. Install with: cargo install naga-cli');
    process.exit(1);
  }
  
  const shaders = findWgslFiles(SHADER_DIR);
  console.log(`Found ${shaders.length} WGSL files\n`);
  
  let checked = 0;
  let invalid = 0;
  let fixed = 0;
  let failed = 0;
  const results = [];
  
  for (const shader of shaders) {
    const content = fs.readFileSync(shader, 'utf8');
    const relativePath = path.relative('.', shader);
    
    const error = getNagaError(shader);
    if (!error) continue;
    
    checked++;
    invalid++;
    
    const { content: fixedContent, applied } = tryFix(content, error);
    
    if (applied.length === 0 && !FIX_ALL) {
      results.push({ file: relativePath, error: error.substring(0, 200), fixed: false });
      continue;
    }
    
    console.log(`\n📄 ${relativePath}`);
    if (applied.length > 0) {
      console.log(`   Applied: ${applied.join(', ')}`);
    }
    
    if (!DRY_RUN) {
      fs.writeFileSync(shader + '.backup', content);
      fs.writeFileSync(shader, fixedContent);
      
      if (validateWithNaga(shader)) {
        console.log('   ✅ Fixed and validated');
        fixed++;
        fs.unlinkSync(shader + '.backup');
        results.push({ file: relativePath, fixed: true });
      } else {
        const remainingError = getNagaError(shader);
        console.log('   ⚠️  Partial fix, manual review needed');
        console.log(`   Error: ${remainingError.substring(0, 100)}...`);
        failed++;
        results.push({ file: relativePath, error: remainingError.substring(0, 200), fixed: false });
        // Keep backup for manual review
      }
    }
  }
  
  console.log(`\n${'═'.repeat(60)}`);
  console.log('\n📊 Summary:');
  console.log(`   Invalid shaders checked: ${checked}`);
  if (!DRY_RUN) {
    console.log(`   ✅ Fixed: ${fixed}`);
    console.log(`   ⚠️  Needs manual fix: ${failed}`);
  }
  
  fs.writeFileSync('./naga-fix-report.json', JSON.stringify(results, null, 2));
  console.log('\n📝 Report saved to: naga-fix-report.json');
}

main();
