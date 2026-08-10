#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const listsDir = path.join(repoRoot, 'public', 'shader-lists');
const manifestPath = path.join(repoRoot, 'public', 'shader-manifest-unified.json');
const errors = [];

function isAbsoluteShaderUrl(url) {
  return typeof url === 'string' && /^https?:\/\//.test(url);
}

function checkShaderEntries(label, entries) {
  if (!Array.isArray(entries)) return;
  for (const entry of entries) {
    if (isAbsoluteShaderUrl(entry?.url)) {
      errors.push(`${label}: "${entry.id}" has absolute url ${entry.url}`);
    }
  }
}

function checkCommittedLists() {
  if (!fs.existsSync(listsDir)) {
    errors.push('public/shader-lists/ is missing');
    return;
  }

  for (const file of fs.readdirSync(listsDir)) {
    if (!file.endsWith('.json')) continue;
    const raw = fs.readFileSync(path.join(listsDir, file), 'utf8');
    try {
      checkShaderEntries(`public/shader-lists/${file}`, JSON.parse(raw));
    } catch (err) {
      errors.push(`public/shader-lists/${file}: invalid JSON (${err.message})`);
    }
  }

  if (fs.existsSync(manifestPath)) {
    try {
      const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
      checkShaderEntries('public/shader-manifest-unified.json', manifest.shaders);
    } catch (err) {
      errors.push(`public/shader-manifest-unified.json: invalid JSON (${err.message})`);
    }
  }
}

// Ensure local prestart/prebuild hooks regenerate relative URLs (no accidental env leak).
const cleanEnv = {
  ...process.env,
  SHADER_LIST_BASE_URL: '',
  REACT_APP_SHADER_BASE_URL: '',
  SHADER_BASE_URL: '',
};

execSync('node scripts/generate_shader_lists.js', {
  cwd: repoRoot,
  env: cleanEnv,
  stdio: 'inherit',
});

checkCommittedLists();

const generativePath = path.join(listsDir, 'generative.json');
if (!fs.existsSync(generativePath)) {
  errors.push('public/shader-lists/generative.json is missing after generation');
} else {
  const generative = JSON.parse(fs.readFileSync(generativePath, 'utf8'));
  if (!Array.isArray(generative) || generative.length === 0) {
    errors.push('public/shader-lists/generative.json is empty');
  } else if (isAbsoluteShaderUrl(generative[0].url)) {
    errors.push(
      `first generative shader url must be relative; got ${generative[0].url}`
    );
  }
}

if (errors.length > 0) {
  console.error('Shader list URL policy failed:');
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log('Shader list URL policy passed:');
console.log('  committed lists + manifest use relative shader paths');
console.log('  generate_shader_lists.js (no base-url) keeps generative URLs relative');
