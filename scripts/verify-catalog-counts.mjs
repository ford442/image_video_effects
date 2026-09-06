#!/usr/bin/env node
/**
 * verify-catalog-counts.mjs — README / manifest / shader-lists / definitions agree.
 *
 * Run after: node scripts/generate_shader_lists.js && npm run build:manifest
 */

import fs from 'node:fs';
import path from 'node:path';
import {
  ALIASES_PUBLIC_PATH,
  ALIASES_SRC_PATH,
  DEFINITIONS_DIR,
  LISTS_DIR,
  MANIFEST_PATH,
  README_PATH,
  REPO_ROOT,
  collectMultipassSecondaryIds,
  countDefinitionIds,
  countListIds,
  getPassOnlyDefIds,
  hasCatalogCountMarkers,
  loadJson,
} from './catalog-count-utils.mjs';

const errors = [];

function extractReadmeTotal(readme) {
  const match = readme.match(/catalog of \*\*([0-9,]+)\*\* compute shaders/i);
  return match ? Number(match[1].replace(/,/g, '')) : null;
}

function validateAliasMap(listIds) {
  if (!fs.existsSync(ALIASES_PUBLIC_PATH)) {
    errors.push(`missing ${path.relative(REPO_ROOT, ALIASES_PUBLIC_PATH)} — run generate_shader_lists.js`);
    return;
  }
  if (!fs.existsSync(ALIASES_SRC_PATH)) {
    errors.push(`missing ${path.relative(REPO_ROOT, ALIASES_SRC_PATH)} — run generate_shader_lists.js`);
    return;
  }

  const publicDoc = loadJson(ALIASES_PUBLIC_PATH);
  const srcDoc = loadJson(ALIASES_SRC_PATH);
  const publicAliases = publicDoc.aliases ?? {};
  const srcAliases = srcDoc.aliases ?? {};

  if (JSON.stringify(publicAliases) !== JSON.stringify(srcAliases)) {
    errors.push('public/shader-id-aliases.json and src/utils/shader-id-aliases.json are out of sync');
  }

  const underscoreCatalogIds = [...listIds].filter(id => id.includes('_')).sort();
  const aliasCanonicals = Object.values(publicAliases).sort();
  const skipped = publicDoc._meta?.skipped_collisions ?? [];

  const expectedAliasCount = underscoreCatalogIds.length - skipped.length;
  if (Object.keys(publicAliases).length !== expectedAliasCount) {
    errors.push(
      `alias count ${Object.keys(publicAliases).length} !== expected ` +
      `${expectedAliasCount} (${underscoreCatalogIds.length} underscore ids, ${skipped.length} collisions)`,
    );
  }

  for (const canonical of underscoreCatalogIds) {
    const expectedAlias = canonical.replace(/_/g, '-');
    const collision = skipped.find(s => s.canonical === canonical);
    if (collision) {
      if (publicAliases[expectedAlias]) {
        errors.push(`collision skip violated: alias exists for ${canonical} but hyphen id is taken`);
      }
      continue;
    }
    if (publicAliases[expectedAlias] !== canonical) {
      errors.push(`missing or wrong alias for ${canonical}: expected "${expectedAlias}" -> "${canonical}"`);
    }
  }

  for (const canonical of aliasCanonicals) {
    if (!listIds.has(canonical)) {
      errors.push(`alias canonical id not in catalog: ${canonical}`);
    }
  }
}

const { ids: listIds, total: listTotal } = countListIds(LISTS_DIR);
const { ids: defIds, unique: defUnique } = countDefinitionIds(DEFINITIONS_DIR);
const secondaryIds = collectMultipassSecondaryIds(DEFINITIONS_DIR);
const passOnlyDefIds = getPassOnlyDefIds(DEFINITIONS_DIR, listIds);
const defsNotInLists = [...defIds].filter(id => !listIds.has(id)).sort();

if (!fs.existsSync(MANIFEST_PATH)) {
  errors.push(`missing ${path.relative(REPO_ROOT, MANIFEST_PATH)} — run npm run build:manifest`);
} else {
  const manifest = loadJson(MANIFEST_PATH);
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

  const expectedCatalogFromDefs = defUnique - passOnlyDefIds.length;
  if (manifestTotal !== expectedCatalogFromDefs) {
    errors.push(
      `manifest total ${manifestTotal} !== definitions unique ${defUnique} minus pass-only defs ${passOnlyDefIds.length} (= ${expectedCatalogFromDefs})`,
    );
  }

  if (defsNotInLists.length !== passOnlyDefIds.length) {
    errors.push(
      `definitions not in lists (${defsNotInLists.length}) !== pass-only secondary defs (${passOnlyDefIds.length})`,
    );
  }
  for (const id of passOnlyDefIds) {
    if (!secondaryIds.has(id)) {
      errors.push(`pass-only definition id not in secondary set: ${id}`);
    }
  }

  const readme = fs.readFileSync(README_PATH, 'utf8');
  if (!hasCatalogCountMarkers(readme)) {
    errors.push('README missing catalog-counts markers — run npm run build:manifest');
  }

  const readmeTotal = extractReadmeTotal(readme);
  if (readmeTotal === null) {
    errors.push('README missing catalog total (expected "**N** compute shaders")');
  } else if (readmeTotal !== manifestTotal) {
    errors.push(`README advertises ${readmeTotal} shaders but manifest has ${manifestTotal}`);
  }

  validateAliasMap(listIds);

  if (passOnlyDefIds.length > 0) {
    console.log(
      `Note: ${passOnlyDefIds.length} pass-only definition id(s) excluded from catalog lists ` +
      `(expected for multipass chains).`,
    );
  }

  console.log('Catalog counts:');
  console.log(`  manifest total: ${manifestTotal}`);
  console.log(`  shader-lists:   ${listTotal}`);
  console.log(`  definitions:    ${defUnique} unique (${passOnlyDefIds.length} pass-only, not in lists)`);
  console.log(`  README total:   ${readmeTotal ?? '(not parsed)'}`);
  const wgslCount = fs.readdirSync(path.join(REPO_ROOT, 'public', 'shaders'))
    .filter(f => f.endsWith('.wgsl') && !f.startsWith('_')).length;
  console.log(`  wgsl files:     ${wgslCount} (includes pass entries; not gated)`);
}

if (errors.length > 0) {
  console.error('verify:catalog-counts failed:');
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log('verify:catalog-counts passed');
