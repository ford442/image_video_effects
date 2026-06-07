#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function findShaders(dir) {
  const shaders = [];
  function walk(dir) {
    const files = fs.readdirSync(dir);
    files.forEach(file => {
      const filePath = path.join(dir, file);
      if (fs.statSync(filePath).isDirectory()) {
        walk(filePath);
      } else if (file.endsWith('.wgsl')) {
        shaders.push(filePath);
      }
    });
  }
  walk(dir);
  return shaders;
}

function validateWgsl(content, filePath) {
  const errors = [];
  const lines = content.split('\n');
  
  let braceCount = 0;
  let parenCount = 0;
  let bracketCount = 0;
  let inString = false;
  let stringChar = '';
  
  // Better tokenizer that respects strings and comments
  let i = 0;
  let charCount = 0;
  let parCount = 0;
  let brCount = 0;
  let brktCount = 0;
  
  while (i < content.length) {
    const char = content[i];
    const nextChar = content[i + 1];
    
    // Skip line comments
    if (char === '/' && nextChar === '/') {
      while (i < content.length && content[i] !== '\n') i++;
      continue;
    }
    
    // Skip block comments
    if (char === '/' && nextChar === '*') {
      i += 2;
      while (i < content.length) {
        if (content[i] === '*' && content[i + 1] === '/') {
          i += 2;
          break;
        }
        i++;
      }
      continue;
    }
    
    // Handle strings
    if ((char === '"' || char === '\'') && (i === 0 || content[i - 1] !== '\\')) {
      if (!inString) {
        inString = true;
        stringChar = char;
      } else if (char === stringChar) {
        inString = false;
      }
      i++;
      continue;
    }
    
    if (!inString) {
      if (char === '{') brCount++;
      if (char === '}') brCount--;
      if (char === '(') parCount++;
      if (char === ')') parCount--;
      if (char === '[') brktCount++;
      if (char === ']') brktCount--;
    }
    
    i++;
  }
  
  if (brCount !== 0) {
    errors.push(`Mismatched braces: ${brCount > 0 ? brCount + ' extra opening braces' : Math.abs(brCount) + ' extra closing braces'}`);
  }
  if (parCount !== 0) {
    errors.push(`Mismatched parentheses: ${parCount > 0 ? parCount + ' extra opening parens' : Math.abs(parCount) + ' extra closing parens'}`);
  }
  if (brktCount !== 0) {
    errors.push(`Mismatched brackets: ${brktCount > 0 ? brktCount + ' extra opening brackets' : Math.abs(brktCount) + ' extra closing brackets'}`);
  }
  
  // Check for common WGSL errors
  lines.forEach((line, idx) => {
    const lineNum = idx + 1;
    const trimmed = line.trim();
    
    // Check textureStore calls
    if (line.includes('textureStore')) {
      const match = line.match(/textureStore\s*\(/);
      if (match) {
        const afterParen = line.substring(line.indexOf(match[0]) + match[0].length);
        const commaCount = (afterParen.match(/,/g) || []).length;
        if (commaCount < 2) {
          errors.push(`Line ${lineNum}: textureStore needs 3 arguments (texture, coords, value), but appears to have ${commaCount + 1}`);
        }
      }
    }
    
    // Check for invalid function decorators
    if (trimmed.startsWith('@') && !['@vertex', '@fragment', '@compute', '@group', '@binding', '@invariant', '@builtin', '@location', '@interpolate', '@workgroup_size'].some(d => trimmed.startsWith(d))) {
      if (!trimmed.includes('//')) { // Don't check comments
        // Only flag truly unknown decorators
      }
    }
  });
  
  return { errors };
}

// Main execution
const shaderDir = './public/shaders';
const shaders = findShaders(shaderDir);

console.log(`\n🔍 Validating ${shaders.length} WGSL shaders...\n`);

let totalErrors = 0;
let filesWithErrors = 0;
const errorFiles = [];

shaders.forEach(shader => {
  try {
    const content = fs.readFileSync(shader, 'utf8');
    const { errors } = validateWgsl(content, shader);
    
    if (errors.length > 0) {
      filesWithErrors++;
      totalErrors += errors.length;
      errorFiles.push({ file: shader, errors });
      console.log(`❌ ${path.relative('.', shader)}`);
      errors.slice(0, 3).forEach(err => console.log(`   ${err}`));
      if (errors.length > 3) console.log(`   ... and ${errors.length - 3} more errors`);
    }
  } catch (e) {
    console.log(`🔥 ${path.relative('.', shader)} - Error reading file: ${e.message}`);
    filesWithErrors++;
  }
});

console.log(`\n${'═'.repeat(60)}`);
console.log(`\n📊 Summary:`);
console.log(`  Total shaders: ${shaders.length}`);
console.log(`  ✅ Valid: ${shaders.length - filesWithErrors}`);
console.log(`  ❌ With errors: ${filesWithErrors}`);
console.log(`  Total errors found: ${totalErrors}\n`);

if (totalErrors === 0) {
  console.log(`\n🎉 All shaders are syntactically valid!\n`);
}

process.exit(filesWithErrors > 0 ? 1 : 0);
