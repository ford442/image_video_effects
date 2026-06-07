#!/usr/bin/env node
/**
 * Batch fix reserved keywords and common errors
 */

const fs = require('fs');
const { execSync } = require('child_process');

const WORKSPACE = '/root/.openclaw/workspace/effects_repo';

// Shader files and their fixes
const FIXES = [
  {
    file: 'public/shaders/gen-art-deco-sky.wgsl',
    changes: [
      { from: 'var ref', to: 'var refPos' },
      { from: '(ref)', to: '(refPos)' },
      { from: ' ref ', to: ' refPos ' },
    ]
  },
  {
    file: 'public/shaders/gen-biomechanical-hive.wgsl',
    changes: [
      { from: 'var ref', to: 'var refPos' },
      { from: '(ref)', to: '(refPos)' },
    ]
  },
  {
    file: 'public/shaders/gen-chronos-labyrinth.wgsl',
    changes: [
      { from: 'var ref', to: 'var refPos' },
      { from: '(ref)', to: '(refPos)' },
    ]
  },
  {
    file: 'public/shaders/gen-fractured-monolith.wgsl',
    changes: [
      { from: 'var ref', to: 'var refPos' },
      { from: '(ref)', to: '(refPos)' },
    ]
  },
  {
    file: 'public/shaders/gen-magnetic-ferrofluid.wgsl',
    changes: [
      { from: 'var ref', to: 'var refPos' },
      { from: '(ref)', to: '(refPos)' },
    ]
  },
  {
    file: 'public/shaders/gen-chromatic-metamorphosis.wgsl',
    changes: [
      { from: 'var target', to: 'var targetPos' },
      { from: '(target)', to: '(targetPos)' },
    ]
  },
  {
    file: 'public/shaders/gen-ethereal-anemone-bloom.wgsl',
    changes: [
      { from: 'var target', to: 'var targetPos' },
      { from: '(target)', to: '(targetPos)' },
    ]
  },
  {
    file: 'public/shaders/gen-prismatic-bismuth-lattice.wgsl',
    changes: [
      { from: 'var target', to: 'var targetPos' },
      { from: '(target)', to: '(targetPos)' },
    ]
  },
  {
    file: 'public/shaders/gen_mandelbulb_3d.wgsl',
    changes: [
      { from: 'var target', to: 'var targetPos' },
      { from: '(target)', to: '(targetPos)' },
    ]
  },
];

function getNagaError(shaderPath) {
  try {
    execSync(`cd ${WORKSPACE} && naga "${shaderPath}"`, { stdio: 'pipe' });
    return null;
  } catch (error) {
    return error.stderr?.toString() || error.message || '';
  }
}

function attemptFix(shaderPath, changes) {
  const fullPath = `${WORKSPACE}/${shaderPath}`;
  let content = fs.readFileSync(fullPath, 'utf8');
  
  for (const change of changes) {
    content = content.replace(new RegExp(change.from.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), change.to);
  }
  
  fs.writeFileSync(fullPath + '.backup', fs.readFileSync(fullPath, 'utf8'));
  fs.writeFileSync(fullPath, content);
  
  const newError = getNagaError(shaderPath);
  if (!newError) {
    fs.unlinkSync(fullPath + '.backup');
    return true;
  } else {
    fs.writeFileSync(fullPath, fs.readFileSync(fullPath + '.backup', 'utf8'));
    return false;
  }
}

console.log('🔧 Batch fixing reserved keywords...\n');

let fixed = 0;
let failed = 0;

for (const fix of FIXES) {
  const result = attemptFix(fix.file, fix.changes);
  if (result) {
    console.log(`✅ Fixed: ${fix.file}`);
    fixed++;
  } else {
    console.log(`❌ Failed: ${fix.file}`);
    failed++;
  }
}

console.log(`\n📊 Results: ${fixed} fixed, ${failed} failed`);
