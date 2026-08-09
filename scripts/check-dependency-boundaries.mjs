#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
const dependencySections = ['dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies'];
const declarations = new Map();
const errors = [];

for (const section of dependencySections) {
  for (const [name, version] of Object.entries(packageJson[section] || {})) {
    const previous = declarations.get(name);
    if (previous) {
      errors.push(`${name} is declared in both ${previous.section} and ${section}.`);
    } else {
      declarations.set(name, { section, version });
    }
  }
}

for (const [aliasName, declaration] of declarations) {
  if (typeof declaration.version !== 'string' || !declaration.version.startsWith('npm:')) continue;
  const match = declaration.version.slice(4).match(/^(@[^/]+\/[^@]+|[^@]+)@/);
  const targetName = match?.[1];
  if (targetName && targetName !== aliasName && declarations.has(targetName)) {
    errors.push(`${aliasName} aliases ${targetName}, but ${targetName} is also declared directly.`);
  }
}

const typescriptVersion = declarations.get('typescript')?.version;
const typescriptMajor = Number(typescriptVersion?.match(/(\d+)/)?.[1]);
if (!typescriptVersion || typescriptMajor < 5) {
  errors.push(`TypeScript 5.x is required; package.json declares ${typescriptVersion || 'nothing'}.`);
}

const installedTypescriptPath = path.join(repoRoot, 'node_modules/typescript/package.json');
let installedTypescriptVersion = null;
if (!fs.existsSync(installedTypescriptPath)) {
  errors.push('TypeScript is not installed; run npm ci before verification.');
} else {
  installedTypescriptVersion = JSON.parse(fs.readFileSync(installedTypescriptPath, 'utf8')).version;
  const installedTypescriptMajor = Number(installedTypescriptVersion?.match(/(\d+)/)?.[1]);
  if (installedTypescriptMajor !== typescriptMajor) {
    errors.push(
      `Installed TypeScript ${installedTypescriptVersion} does not match the declared ` +
        `${typescriptMajor}.x major; run npm ci.`
    );
  }
}

const aiBoundaries = new Map([
  ['@xenova/transformers', 'src/services/aiModels/transformersLoader.ts'],
  ['@mlc-ai/web-llm', 'src/services/aiModels/webLlmLoader.ts'],
]);
const sourceExtensions = new Set(['.js', '.jsx', '.ts', '.tsx']);

function walk(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(absolutePath));
    else if (sourceExtensions.has(path.extname(entry.name))) files.push(absolutePath);
  }
  return files;
}

for (const absolutePath of walk(path.join(repoRoot, 'src'))) {
  const relativePath = path.relative(repoRoot, absolutePath).split(path.sep).join('/');
  const source = fs.readFileSync(absolutePath, 'utf8');
  for (const [specifier, loaderPath] of aiBoundaries) {
    const escapedSpecifier = specifier.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const moduleReference = new RegExp(
      `(?:from\\s+|import\\s*\\(\\s*(?:/\\*[\\s\\S]*?\\*/\\s*)?|require\\s*\\(\\s*)` +
        `["']${escapedSpecifier}["']`
    );
    if (moduleReference.test(source) && relativePath !== loaderPath) {
      errors.push(`${relativePath} references ${specifier}; use ${loaderPath} instead.`);
    }
  }
}

for (const [specifier, loaderPath] of aiBoundaries) {
  const source = fs.readFileSync(path.join(repoRoot, loaderPath), 'utf8');
  const escapedSpecifier = specifier.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const dynamicImport = new RegExp(`import\\s*\\(.*["']${escapedSpecifier}["']\\s*\\)`, 's');
  const staticImport = new RegExp(`(?:from\\s*|require\\s*\\(\\s*)["']${escapedSpecifier}["']`);
  if (!dynamicImport.test(source)) {
    errors.push(`${loaderPath} must dynamically import ${specifier}.`);
  }
  if (staticImport.test(source)) {
    errors.push(`${loaderPath} statically imports ${specifier}.`);
  }
}

const shaderListsDir = path.join(repoRoot, 'public/shader-lists');
if (fs.existsSync(shaderListsDir)) {
  for (const file of fs.readdirSync(shaderListsDir)) {
    if (file.endsWith('.json')) {
      const content = fs.readFileSync(path.join(shaderListsDir, file), 'utf8');
      if (content.includes('https://') || content.includes('http://')) {
        errors.push(
          `public/shader-lists/${file} contains absolute shader URLs. ` +
            'Regenerate without --base-url (local default) or set SHADER_LIST_BASE_URL only for deploy builds.'
        );
      }
    }
  }
}

if (errors.length > 0) {
  console.error('Dependency boundary policy failed:');
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log('Dependency boundary policy passed:');
console.log(`  TypeScript: ${installedTypescriptVersion} installed (${typescriptVersion} declared)`);
console.log('  dependency declarations: no duplicate direct or aliased packages');
console.log('  AI packages: referenced only through their dynamic loader modules');
console.log('  base-url hygiene: no absolute test-CDN URLs leaked into committed shader lists');
