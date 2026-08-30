#!/usr/bin/env node
/**
 * verify-catalog-counts.mjs — README / manifest / shader-lists / definitions agree.
 *
 * Run after: node scripts/generate_shader_lists.js && npm run build:manifest
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const listsDir = path.join(repoRoot, 'public', 'shader-lists');
const manifestPath = path.join(repoRoot, 'public', 'shader-manifest-unified.json');
const definitionsDir = path.join(repoRoot, 'shader_definitions');
const readmePath = path.join(repoRoot, 'README.md');
const aliasesPath = path.join(repoRoot, 'public', 'shader-id-aliases.json');

const errors = [];

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function countListIds() {
  const byCategory = {};
  const ids = new Set();
  for (const file of fs.readdirSync(listsDir).filter(f => f.endsWith('.json')).sort()) {
    const entries = loadJson(path.join(listsDir, file));
    byCategory[path.basename(file, '.json')] = entries.length;
    for (const entry of entries) {
      if (entry?.id) ids.add(entry.id);
    }
  }
  return { byCategory, ids, total: ids.size };
}

function countDefinitionIds() {
  const ids = new Set();
  let files = 0;
  for (const category of fs.readdirSync(definitionsDir)) {
    const dir = path.join(definitionsDir, category);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const file of fs.readdirSync(dir)) {
      if (!file.endsWith('.json')) continue;
      files += 1;
      const data = loadJson(path.join(dir, file));
      const entry = Array.isArray(data) ? data[0] : data;
      if (entry?.id) ids.add(entry.id);
    }
  }
  return { ids, files, unique: ids.size };
}

function extractReadmeTotal(readme) {
  const match = readme.match(/catalog of \*\*([0-9,]+)\*\* compute shaders/i);
  return match ? Number(match[1].replace(/,/g, '')) : null;
}

const { byCategory, ids: listIds, total: listTotal } = countListIds();
const { ids: defIds, unique: defUnique } = countDefinitionIds();

if (!fs.existsSync(manifestPath)) {
  errors.push(`missing ${path.relative(repoRoot, manifestPath)} — run npm run build:manifest`);
} else {
  const manifest = loadJson(manifestPath);
  const manifestTotal = manifest?._meta?.total_count ?? manifest.shaders?.length ?? 0;
  const manifestIds = new Set((manifest.shaders || []).map(s => s.id).filter(Boolean));

  if (manifestTotal !== listTotal) {
    errors.push(`manifest total ${manifestTotal} !== shader-lists unique ids ${listTotal}`);
  }
  if (manifestIds.size !== listTotal) {
    errors.push(`manifest shader ids ${manifestIds.size} !== shader-lists unique ids ${listTotal}`);
  }
  for (const id of listIds) {
    if (!manifestIds.has(id)) errors.push(`shader-lists id missing from manifest: ${id}`);
  }

  const readme = fs.readFileSync(readmePath, 'utf8');
  const readmeTotal = extractReadmeTotal(readme);
  if (readmeTotal === null) {
    errors.push('README missing catalog total (expected "**N** compute shaders")');
  } else if (readmeTotal !== manifestTotal) {
    errors.push(`README advertises ${readmeTotal} shaders but manifest has ${manifestTotal}`);
  }

  const secondaryOnly = [...defIds].filter(id => !listIds.has(id)).sort();
  if (secondaryOnly.length > 0) {
    console.log(
      `Note: ${secondaryOnly.length} definition id(s) are graph/pass entries not in catalog lists ` +
      `(expected for multipass parents).`,
    );
  }

  if (fs.existsSync(aliasesPath)) {
    const aliasDoc = loadJson(aliasesPath);
    const aliasMap = aliasDoc.aliases ?? aliasDoc;
    const aliasIds = Object.values(aliasMap).filter(v => typeof v === 'string');
    for (const canonical of aliasIds) {
      if (!listIds.has(canonical)) {
        errors.push(`alias canonical id not in catalog: ${canonical}`);
      }
    }
  }

  console.log('Catalog counts:');
  console.log(`  manifest total: ${manifestTotal}`);
  console.log(`  shader-lists:   ${listTotal}`);
  console.log(`  definitions:    ${defUnique} unique (${defUnique - listTotal} not in lists)`);
  console.log(`  README total:   ${readmeTotal ?? '(not parsed)'}`);
  const wgslCount = fs.readdirSync(path.join(repoRoot, 'public', 'shaders'))
    .filter(f => f.endsWith('.wgsl') && !f.startsWith('_')).length;
  console.log(`  wgsl files:     ${wgslCount} (includes pass entries; not gated)`);
}

if (errors.length > 0) {
  console.error('verify:catalog-counts failed:');
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log('verify:catalog-counts passed');
