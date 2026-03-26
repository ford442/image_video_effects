#!/usr/bin/env node
/**
 * Enhanced WGSL Fixer - Handles reserved keywords and more complex issues
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const WORKSPACE = '/root/.openclaw/workspace/effects_repo';

// WGSL reserved keywords that can't be used as identifiers
const RESERVED_KEYWORDS = [
  'mod',      // module
  'ref',      // reference
  'target',   // target
  'type',     // type
  'final',    // final
  'move',     // move
  'self',     // self
  'const',    // const (when used incorrectly)
];

function getNagaError(shaderPath) {
  try {
    execSync(`cd ${WORKSPACE} && naga "${shaderPath}"`, { stdio: 'pipe' });
    return null;
  } catch (error) {
    return error.stderr?.toString() || error.message || '';
  }
}

function fixReservedKeywords(content) {
  let fixed = content;
  let changes = [];
  
  // Fix variable declarations using reserved keywords
  for (const keyword of RESERVED_KEYWORDS) {
    // Pattern: var keyword = or let keyword =
    const varPattern = new RegExp(`\\bvar\\s+(${keyword})\\s*[=:]`, 'g');
    const letPattern = new RegExp(`\\blet\\s+(${keyword})\\s*[=:]`, 'g');
    
    if (varPattern.test(content) || letPattern.test(content)) {
      // Replace var keyword with var keyword_
      fixed = fixed.replace(varPattern, `var ${keyword}_$1 =`);
      fixed = fixed.replace(letPattern, `let ${keyword}_$1 =`);
      changes.push(`${keyword} -> ${keyword}_`);
    }
    
    // Reset regex lastIndex
    varPattern.lastIndex = 0;
    letPattern.lastIndex = 0;
  }
  
  return { content: fixed, changes };
}

function fixMissingDefinitions(content, error) {
  let fixed = content;
  let changes = [];
  
  // Fix common missing audioReactivity definition
  if (error.includes('audioReactivity') && error.includes('no definition')) {
    // Add audioReactivity calculation after time extraction
    if (!content.includes('let audioReactivity')) {
      fixed = fixed.replace(
        /(let time = u\.config\.x[^;]*;)/,
        `$1\n    let audioReactivity = u.zoom_config.x;`
      );
      changes.push('added audioReactivity definition');
    }
  }
  
  // Fix missing audioOverall
  if (error.includes('audioOverall') && error.includes('no definition')) {
    if (!content.includes('let audioOverall')) {
      fixed = fixed.replace(
        /(let time = u\.config\.x[^;]*;)/,
        `$1\n    let audioOverall = u.zoom_config.x;`
      );
      changes.push('added audioOverall definition');
    }
  }
  
  return { content: fixed, changes };
}

function fixPI(content, error) {
  let fixed = content;
  let changes = [];
  
  if (error.includes('PI') && error.includes('no definition')) {
    if (!content.includes('let PI') && !content.includes('const PI')) {
      // Add PI definition near the top, after imports
      fixed = fixed.replace(
        /(@compute|fn main)/,
        `const PI = 3.14159265359;\n\n$1`
      );
      changes.push('added PI constant');
    }
  }
  
  return { content: fixed, changes };
}

function attemptFix(shaderPath) {
  const fullPath = `${WORKSPACE}/${shaderPath}`;
  let content = fs.readFileSync(fullPath, 'utf8');
  const error = getNagaError(shaderPath);
  
  if (!error) {
    return { alreadyValid: true };
  }
  
  let allChanges = [];
  
  // Try reserved keyword fixes
  const keywordResult = fixReservedKeywords(content);
  if (keywordResult.changes.length > 0) {
    content = keywordResult.content;
    allChanges.push(...keywordResult.changes);
  }
  
  // Try missing definition fixes
  const defResult = fixMissingDefinitions(content, error);
  if (defResult.changes.length > 0) {
    content = defResult.content;
    allChanges.push(...defResult.changes);
  }
  
  // Try PI constant fix
  const piResult = fixPI(content, error);
  if (piResult.changes.length > 0) {
    content = piResult.content;
    allChanges.push(...piResult.changes);
  }
  
  if (allChanges.length === 0) {
    return { fixed: false, error: error.substring(0, 100) };
  }
  
  // Backup and write
  fs.writeFileSync(fullPath + '.backup', fs.readFileSync(fullPath, 'utf8'));
  fs.writeFileSync(fullPath, content);
  
  // Verify
  const newError = getNagaError(shaderPath);
  if (!newError) {
    fs.unlinkSync(fullPath + '.backup');
    return { fixed: true, changes: allChanges };
  } else {
    fs.writeFileSync(fullPath, fs.readFileSync(fullPath + '.backup', 'utf8'));
    return { fixed: false, error: newError.substring(0, 100) };
  }
}

function main() {
  console.log('🔧 Enhanced WGSL Fixer\n');
  
  const invalidShaders = require('/root/.openclaw/workspace/effects_repo/naga-validation-report.json')
    .shaders.filter(s => !s.valid)
    .map(s => s.file);
  
  console.log(`Processing ${invalidShaders.length} invalid shaders...\n`);
  
  let fixed = 0;
  let failed = 0;
  
  for (const shader of invalidShaders) {
    const result = attemptFix(shader);
    
    if (result.alreadyValid) {
      console.log(`✅ Already valid: ${shader}`);
      fixed++;
    } else if (result.fixed) {
      console.log(`✅ Fixed: ${shader} (${result.changes.join(', ')})`);
      fixed++;
    } else {
      console.log(`❌ Failed: ${shader}`);
      failed++;
    }
  }
  
  console.log(`\n${'═'.repeat(60)}`);
  console.log(`\n📊 Results:`);
  console.log(`   ✅ Fixed: ${fixed}`);
  console.log(`   ❌ Failed: ${failed}`);
}

main();
