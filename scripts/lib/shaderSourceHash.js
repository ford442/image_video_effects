'use strict';
/**
 * shaderSourceHash — one content hash per catalog shader.
 *
 * The hash changes whenever anything that affects the rendered picture changes:
 *   - the shader's own WGSL (public/shaders/<id>.wgsl)
 *   - every `#include "_lib.wgsl"` it pulls in (recursively)
 *   - every later pass in its multipass chain (MULTIPASS_REGISTRY nextShader)
 *   - the `params` block of its definition JSON (defaults / ranges / mappings)
 *
 * It deliberately ignores name, description, tags and any other metadata, so
 * editing a description never marks a thumbnail stale.
 *
 * Used by:
 *   scripts/build-shader-source-hashes.js   → public/thumbnails/source-hashes.json (read by the app)
 *   scripts/record-shader-upgrades.js       → reports/shader-upgrade-ledger.json
 *   scripts/thumbs-backfill-source-hashes.js
 *   scripts/generate-shader-thumbnails.js   (--stale, and source_hash stamping)
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..', '..');
const SHADERS_DIR = path.join(ROOT, 'public', 'shaders');
const DEFS_DIR = path.join(ROOT, 'shader_definitions');
const REGISTRY_PATH = path.join(ROOT, 'src', 'renderer', 'multipassRegistry.ts');

const HASH_ALGORITHM = 'sha256/16:wgsl+includes+multipass+params';
const INCLUDE_RE = /^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$/gm;

function walkJson(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walkJson(full, out);
    else if (entry.isFile() && entry.name.endsWith('.json')) out.push(full);
  }
  return out;
}

/** id → { file, def } for every shader definition JSON. */
function loadDefinitions() {
  const byId = new Map();
  for (const file of walkJson(DEFS_DIR)) {
    let def;
    try {
      def = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch {
      continue;
    }
    if (def && typeof def.id === 'string') byId.set(def.id, { file, def });
  }
  return byId;
}

/** Parses the generated MULTIPASS_REGISTRY object out of multipassRegistry.ts. */
function loadMultipassRegistry() {
  if (!fs.existsSync(REGISTRY_PATH)) return {};
  const src = fs.readFileSync(REGISTRY_PATH, 'utf8');
  const m = src.match(/export const MULTIPASS_REGISTRY[^=]*=\s*(\{[\s\S]*?\n\});/);
  if (!m) return {};
  try {
    return JSON.parse(m[1]);
  } catch {
    return {};
  }
}

/** Ordered list of shader ids rendered for `id` (itself + later passes). */
function passChain(id, registry) {
  const chain = [id];
  const seen = new Set(chain);
  let next = registry[id] && registry[id].nextShader;
  while (next && !seen.has(next)) {
    chain.push(next);
    seen.add(next);
    next = registry[next] && registry[next].nextShader;
  }
  return chain;
}

/**
 * Returns [{ file, text }] for a WGSL file plus its includes (depth-first,
 * each file once). Missing includes are recorded so the hash still changes
 * when one appears or disappears.
 */
function collectWgslFiles(fileName, seen = new Set(), out = []) {
  if (seen.has(fileName)) return out;
  seen.add(fileName);
  const full = path.join(SHADERS_DIR, fileName);
  if (!fs.existsSync(full)) {
    out.push({ file: fileName, text: null });
    return out;
  }
  const text = fs.readFileSync(full, 'utf8');
  out.push({ file: fileName, text });
  INCLUDE_RE.lastIndex = 0;
  let m;
  const includes = [];
  while ((m = INCLUDE_RE.exec(text)) !== null) includes.push(m[1]);
  for (const inc of includes) collectWgslFiles(inc, seen, out);
  return out;
}

/**
 * WGSL file name for a shader id. Definitions point at their file via `url`
 * (e.g. id "gen-grid" → shaders/gen_grid.wgsl), so prefer that over `<id>.wgsl`.
 */
function wgslFileFor(id, ctx) {
  const rec = ctx.definitions.get(id);
  const url = rec && typeof rec.def.url === 'string' ? rec.def.url : '';
  const base = url.split(/[?#]/)[0].split('/').pop();
  return base && base.endsWith('.wgsl') ? base : `${id}.wgsl`;
}

/** Repo-relative paths of every file that feeds the hash (for git queries). */
function sourceFilesFor(id, ctx) {
  const files = [];
  const seen = new Set();
  for (const passId of passChain(id, ctx.registry)) {
    for (const f of collectWgslFiles(wgslFileFor(passId, ctx), seen)) {
      if (f.text !== null) files.push(path.relative(ROOT, path.join(SHADERS_DIR, f.file)));
    }
  }
  const def = ctx.definitions.get(id);
  if (def) files.push(path.relative(ROOT, def.file));
  return files;
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(k => `${JSON.stringify(k)}:${stableStringify(value[k])}`).join(',')}}`;
  }
  return JSON.stringify(value === undefined ? null : value);
}

/** Hash for one shader, or null when its main WGSL file does not exist. */
function computeSourceHash(id, ctx) {
  const parts = [];
  const seen = new Set();
  const chain = passChain(id, ctx.registry);
  for (let i = 0; i < chain.length; i++) {
    const files = collectWgslFiles(wgslFileFor(chain[i], ctx), seen);
    if (i === 0 && (files.length === 0 || files[0].text === null)) return null;
    for (const f of files) parts.push(`file:${f.file}\n${f.text === null ? '<missing>' : f.text}`);
  }
  const def = ctx.definitions.get(id);
  parts.push(`params:${stableStringify(def ? def.def.params || [] : [])}`);
  return crypto.createHash('sha256').update(parts.join('\n\u0000\n')).digest('hex').slice(0, 16);
}

function createHashContext() {
  return { definitions: loadDefinitions(), registry: loadMultipassRegistry() };
}

/** { id: hash } for every shader definition that has a WGSL file. */
function computeAllSourceHashes(ctx = createHashContext()) {
  const hashes = {};
  for (const id of [...ctx.definitions.keys()].sort()) {
    const h = computeSourceHash(id, ctx);
    if (h) hashes[id] = h;
  }
  return hashes;
}

/**
 * Thumbnail freshness for one id.
 *   missing  — no manifest entry
 *   unknown  — entry predates source hashing (run thumbs:backfill-hashes once)
 *   stale    — shader changed since the thumbnail was captured
 *   fresh    — thumbnail matches current source
 */
function thumbnailFreshness(id, currentHash, manifest) {
  const entry = manifest[id];
  if (!entry) return 'missing';
  if (!entry.source_hash) return 'unknown';
  return entry.source_hash === currentHash ? 'fresh' : 'stale';
}

module.exports = {
  ROOT,
  SHADERS_DIR,
  DEFS_DIR,
  HASH_ALGORITHM,
  loadDefinitions,
  loadMultipassRegistry,
  passChain,
  wgslFileFor,
  sourceFilesFor,
  computeSourceHash,
  computeAllSourceHashes,
  createHashContext,
  thumbnailFreshness,
  stableStringify,
};
