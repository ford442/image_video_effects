#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const srcDir = path.join(repoRoot, 'src');
const stylesDir = path.join(srcDir, 'styles');
const barrelPath = path.join(stylesDir, 'index.css');
const partsDir = path.join(stylesDir, 'parts');

const DEFAULT_CSS_LINE_LIMIT = 800;
const lineLimit = Number(process.env.CSS_LINE_LIMIT || DEFAULT_CSS_LINE_LIMIT);
if (!Number.isInteger(lineLimit) || lineLimit <= 0) {
  console.error('CSS policy failed: CSS_LINE_LIMIT must be a positive integer.');
  process.exit(1);
}

const errors = [];
const relative = absolutePath => path.relative(repoRoot, absolutePath).split(path.sep).join('/');

function walkCss(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walkCss(absolutePath));
    else if (entry.name.endsWith('.css')) files.push(absolutePath);
  }
  return files.sort();
}

function countLines(source) {
  if (source.length === 0) return 0;
  const newlines = source.match(/\n/g)?.length ?? 0;
  return source.endsWith('\n') ? newlines : newlines + 1;
}

// 1. Size budget: no stylesheet under src/ may exceed the line limit.
const allCss = walkCss(srcDir);
let largest = { file: null, lines: 0 };
for (const file of allCss) {
  const lines = countLines(fs.readFileSync(file, 'utf8'));
  if (lines > largest.lines) largest = { file, lines };
  if (lines > lineLimit) {
    errors.push(`${relative(file)} has ${lines} lines (limit ${lineLimit}).`);
  }
}

// 2. Barrel completeness: every part is imported, every import resolves.
const barrelImports = [];
if (!fs.existsSync(barrelPath)) {
  errors.push(`${relative(barrelPath)} is missing.`);
} else {
  const barrel = stripComments(fs.readFileSync(barrelPath, 'utf8'));
  const importPattern = /@import\s+(?:url\(\s*)?["']([^"']+)["']\s*\)?[^;]*;/g;
  for (const match of barrel.matchAll(importPattern)) {
    const target = path.resolve(stylesDir, match[1]);
    barrelImports.push(target);
    if (!fs.existsSync(target)) {
      errors.push(`${relative(barrelPath)} imports ${match[1]}, which does not exist.`);
    }
  }
  const seen = new Set();
  for (const target of barrelImports) {
    if (seen.has(target)) errors.push(`${relative(barrelPath)} imports ${relative(target)} more than once.`);
    seen.add(target);
  }
}

const parts = fs.existsSync(partsDir) ? walkCss(partsDir) : [];
if (parts.length === 0) errors.push(`${relative(partsDir)} contains no stylesheets.`);
const importedSet = new Set(barrelImports);
for (const part of parts) {
  if (!importedSet.has(part)) {
    errors.push(`${relative(part)} is not imported by ${relative(barrelPath)}.`);
  }
}

// 3. Duplicate selectors: the same selector (in the same at-rule context) must
//    not be defined in two different part files.
function stripComments(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, match => match.replace(/[^\n]/g, ' '));
}

function collectSelectors(source) {
  const text = stripComments(source);
  const selectors = [];
  const contextStack = [];
  let buffer = '';
  let line = 1;
  let bufferLine = 1;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === '\n') line++;
    if (ch === '{') {
      const prelude = buffer.trim().replace(/\s+/g, ' ');
      const parent = contextStack[contextStack.length - 1];
      const insideKeyframes = parent?.kind === 'keyframes';
      if (prelude.startsWith('@')) {
        const kind = /^@(-[a-z]+-)?keyframes\b/.test(prelude) ? 'keyframes' : 'at-rule';
        contextStack.push({ kind, prelude });
      } else {
        contextStack.push({ kind: 'rule', prelude });
        if (!insideKeyframes && prelude) {
          const context = contextStack
            .slice(0, -1)
            .filter(entry => entry.kind === 'at-rule')
            .map(entry => entry.prelude)
            .join(' > ');
          for (const selector of prelude.split(',')) {
            const normalized = selector.trim();
            if (normalized) selectors.push({ key: context ? `${context} > ${normalized}` : normalized, line: bufferLine });
          }
        }
      }
      buffer = '';
    } else if (ch === '}') {
      contextStack.pop();
      buffer = '';
    } else if (ch === ';' && contextStack[contextStack.length - 1]?.kind !== 'rule') {
      buffer = '';
    } else {
      if (!buffer.trim() && !/\s/.test(ch)) bufferLine = line;
      buffer += ch;
    }
  }
  return selectors;
}

// Duplicates inherited verbatim from the pre-split src/style.css (old lines 135-148
// and 424-437). The later controls.css block wins the cascade, so the layout.css
// thumb colours are already dead — but removing either is a rule deletion, which
// the relocation-only split forbids. TODO(#1228): delete the shadowed layout.css
// block in a follow-up with its own screenshot review, then drop these entries.
// The list is exact and shrink-only: an entry that no longer matches fails too.
const KNOWN_DUPLICATES = new Map(
  [
    '.sidebar::-webkit-scrollbar',
    '.sidebar::-webkit-scrollbar-track',
    '.sidebar::-webkit-scrollbar-thumb',
    '.sidebar::-webkit-scrollbar-thumb:hover',
  ].map(selector => [selector, ['src/styles/parts/controls.css', 'src/styles/parts/layout.css']])
);

const selectorOwners = new Map();
for (const part of parts) {
  for (const { key, line } of collectSelectors(fs.readFileSync(part, 'utf8'))) {
    const owners = selectorOwners.get(key) ?? new Map();
    if (!owners.has(part)) owners.set(part, line);
    selectorOwners.set(key, owners);
  }
}
let duplicateCount = 0;
let knownDuplicateCount = 0;
for (const [selector, owners] of selectorOwners) {
  if (owners.size < 2) continue;
  const ownerFiles = [...owners.keys()].map(relative).sort();
  const known = KNOWN_DUPLICATES.get(selector);
  if (known && known.join('\n') === ownerFiles.join('\n')) {
    knownDuplicateCount++;
    continue;
  }
  duplicateCount++;
  const where = [...owners].map(([file, line]) => `${relative(file)}:${line}`).join(', ');
  errors.push(`selector "${selector}" is defined in ${owners.size} part files: ${where}.`);
}

for (const [selector, files] of KNOWN_DUPLICATES) {
  const owners = selectorOwners.get(selector);
  const ownerFiles = owners ? [...owners.keys()].map(relative).sort() : [];
  if (ownerFiles.join('\n') !== files.join('\n')) {
    errors.push(
      `known duplicate "${selector}" no longer matches ${files.join(' + ')}; ` +
        'remove it from KNOWN_DUPLICATES in scripts/check-css.mjs.'
    );
  }
}

if (errors.length > 0) {
  console.error('CSS policy failed:');
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log('CSS policy passed:');
console.log(
  `  size budget: ${allCss.length} stylesheets under src/ ≤ ${lineLimit} lines ` +
    `(largest ${relative(largest.file)} at ${largest.lines})`
);
console.log(`  barrel: ${relative(barrelPath)} imports all ${parts.length} parts; all ${barrelImports.length} imports resolve`);
console.log(
  `  duplicate selectors across parts: ${duplicateCount} new, ${knownDuplicateCount} known pre-split ` +
    `(TODO #1228; ${selectorOwners.size} selectors checked)`
);
