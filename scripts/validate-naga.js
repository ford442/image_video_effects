#!/usr/bin/env node
/**
 * Naga-based WGSL Validator
 * Uses the naga CLI (Rust wgpu shader compiler) for proper WGSL validation
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const SHADER_DIR = process.argv[2] || './public/shaders';
const OUTPUT_JSON = process.argv.includes('--json');

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

function validateWithNaga(filePath) {
  try {
    // Run naga validation (no output file = just validate)
    execSync(`naga "${filePath}"`, { 
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
    return { valid: true, errors: [] };
  } catch (error) {
    const stderr = error.stderr?.toString() || error.message || '';
    const lines = stderr.split('\n').filter(l => l.trim());
    
    const errors = [];
    for (const line of lines) {
      // Parse naga error format: "error: message at line X"
      const match = line.match(/error:\s*(.+?)(?:\s+at\s+line\s+(\d+))?/i);
      if (match) {
        errors.push({
          message: match[1],
          line: match[2] ? parseInt(match[2]) : null
        });
      } else if (line.includes('error') || line.includes('Error')) {
        errors.push({ message: line, line: null });
      }
    }
    
    return { valid: false, errors };
  }
}

function main() {
  console.log('\n🔷 Naga WGSL Validator\n');
  
  // Check naga is available
  try {
    execSync('which naga', { stdio: 'ignore' });
  } catch {
    console.error('❌ naga not found. Install with: cargo install naga-cli');
    process.exit(1);
  }
  
  console.log(`📁 Scanning: ${SHADER_DIR}\n`);
  
  const shaders = findWgslFiles(SHADER_DIR);
  console.log(`Found ${shaders.length} WGSL files\n`);
  
  const results = [];
  let validCount = 0;
  let invalidCount = 0;
  
  for (const shader of shaders) {
    const relativePath = path.relative('.', shader);
    const result = validateWithNaga(shader);
    
    results.push({
      file: relativePath,
      valid: result.valid,
      errors: result.errors
    });
    
    if (result.valid) {
      validCount++;
      process.stdout.write(`✅ ${relativePath}\n`);
    } else {
      invalidCount++;
      console.log(`\n❌ ${relativePath}`);
      for (const err of result.errors.slice(0, 3)) {
        const lineInfo = err.line ? ` (line ${err.line})` : '';
        console.log(`   └─ ${err.message}${lineInfo}`);
      }
      if (result.errors.length > 3) {
        console.log(`   └─ ... and ${result.errors.length - 3} more errors`);
      }
    }
  }
  
  // Summary
  console.log(`\n${'═'.repeat(60)}`);
  console.log('\n📊 Summary:');
  console.log(`   Total shaders: ${shaders.length}`);
  console.log(`   ✅ Valid: ${validCount}`);
  console.log(`   ❌ Invalid: ${invalidCount}`);
  
  if (invalidCount === 0) {
    console.log('\n🎉 All shaders passed naga validation!\n');
  }
  
  // JSON output
  if (OUTPUT_JSON) {
    const jsonPath = './reports/naga-validation-report.json';
    fs.writeFileSync(jsonPath, JSON.stringify({
      timestamp: new Date().toISOString(),
      total: shaders.length,
      valid: validCount,
      invalid: invalidCount,
      shaders: results
    }, null, 2));
    console.log(`\n📝 JSON report saved to: ${jsonPath}`);
  }
  
  process.exit(invalidCount > 0 ? 1 : 0);
}

main();
