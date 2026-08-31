/**
 * Shared catalog count helpers — mirror generate_shader_lists.js secondary-id logic.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const REPO_ROOT = path.resolve(__dirname, '..');
export const LISTS_DIR = path.join(REPO_ROOT, 'public', 'shader-lists');
export const MANIFEST_PATH = path.join(REPO_ROOT, 'public', 'shader-manifest-unified.json');
export const DEFINITIONS_DIR = path.join(REPO_ROOT, 'shader_definitions');
export const README_PATH = path.join(REPO_ROOT, 'README.md');
export const ALIASES_PUBLIC_PATH = path.join(REPO_ROOT, 'public', 'shader-id-aliases.json');
export const ALIASES_SRC_PATH = path.join(REPO_ROOT, 'src', 'utils', 'shader-id-aliases.json');

export const CATALOG_COUNT_MARKERS = [
  'catalog-counts:intro',
  'catalog-counts:features',
  'catalog-counts:table',
  'catalog-counts:structure',
  'catalog-counts:legacy-ids',
];

export function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

export function readDefinition(filePath) {
  const data = loadJson(filePath);
  return Array.isArray(data) ? data[0] : data;
}

/**
 * First pass: ids referenced only as multipass secondaries (same as generate_shader_lists.js).
 */
export function collectMultipassSecondaryIds(definitionsDir = DEFINITIONS_DIR) {
  const allDefs = [];
  const secondaryIds = new Set();

  if (!fs.existsSync(definitionsDir)) return secondaryIds;

  for (const dir of fs.readdirSync(definitionsDir)) {
    const dirPath = path.join(definitionsDir, dir);
    if (!fs.statSync(dirPath).isDirectory()) continue;
    for (const file of fs.readdirSync(dirPath).filter(f => f.endsWith('.json'))) {
      const filePath = path.join(dirPath, file);
      try {
        const shaderDef = readDefinition(filePath);
        if (shaderDef?.id) allDefs.push(shaderDef);
      } catch {
        // skip invalid
      }
    }
  }

  for (const shaderDef of allDefs) {
    const primaryId = shaderDef.id;
    const multipass = shaderDef.multipass || {};
    if (multipass.nextShader) secondaryIds.add(String(multipass.nextShader));
    for (const pass of multipass.passes || []) {
      if (pass?.file) {
        const stem = String(pass.file).replace(/\.wgsl$/i, '');
        if (stem && stem !== primaryId) secondaryIds.add(stem);
      }
    }
    for (const node of multipass.graph?.nodes || []) {
      if (node?.entry && node.entry !== primaryId) secondaryIds.add(String(node.entry));
    }
  }

  return secondaryIds;
}

export function countListIds(listsDir = LISTS_DIR) {
  const byCategory = {};
  const ids = new Set();
  for (const file of fs.readdirSync(listsDir).filter(f => f.endsWith('.json')).sort()) {
    const entries = loadJson(path.join(listsDir, file));
    const category = path.basename(file, '.json');
    byCategory[category] = entries.length;
    for (const entry of entries) {
      if (entry?.id) ids.add(entry.id);
    }
  }
  return { byCategory, ids, total: ids.size };
}

export function countDefinitionIds(definitionsDir = DEFINITIONS_DIR) {
  const ids = new Set();
  let files = 0;
  for (const category of fs.readdirSync(definitionsDir)) {
    const dir = path.join(definitionsDir, category);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.json'))) {
      files += 1;
      const entry = readDefinition(path.join(dir, file));
      if (entry?.id) ids.add(entry.id);
    }
  }
  return { ids, files, unique: ids.size };
}

/** Definition ids excluded from catalog lists (pass-chain secondaries). */
export function getPassOnlyDefIds(definitionsDir = DEFINITIONS_DIR, listIds) {
  const { ids: defIds } = countDefinitionIds(definitionsDir);
  const secondaryIds = collectMultipassSecondaryIds(definitionsDir);
  return [...defIds].filter(id => !listIds.has(id) && secondaryIds.has(id)).sort();
}

export function formatCount(n) {
  return n.toLocaleString('en-US');
}

export function hasCatalogCountMarkers(readme) {
  return CATALOG_COUNT_MARKERS.every(name => {
    return readme.includes(`<!-- ${name}:begin -->`) && readme.includes(`<!-- ${name}:end -->`);
  });
}

export function replaceMarkedSection(readme, markerName, content) {
  const begin = `<!-- ${markerName}:begin -->`;
  const end = `<!-- ${markerName}:end -->`;
  const re = new RegExp(`${begin}[\\s\\S]*?${end}`, 'm');
  if (!re.test(readme)) {
    throw new Error(`README missing markers ${begin} … ${end}`);
  }
  return readme.replace(re, `${begin}\n${content}\n${end}`);
}
