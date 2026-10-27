/**
 * naga-reflect check: a shader must never sample the r32float depth binding
 * (bind_group0.json kind `sampled-r32`) through a filtering sampler (kind
 * `filtering-sampler`, i.e. u_sampler). Depth is bound `unfilterable-float` on
 * every device, so that pairing is a pipeline-creation error under the TS
 * renderer even when it happened to compile elsewhere.
 *
 * Bindings are resolved by number through naga reflection, so a shader that
 * renames binding 0 or 4 is still caught. Used by scripts/verify-naga-wasm.mjs.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

export function loadBindGroup0Contract(file = path.join(ROOT, 'src/contracts/bind_group0.json')) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

const SAMPLE_CALL = /\btextureSample(?:Level|Bias|Grad|BaseClampToEdge)?\s*\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)/g;

/** Replace comments with spaces so line numbers stay put. */
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length));
}

/**
 * @param {string} source expanded WGSL
 * @param {{ ok?: boolean, bindings?: Array<{group:number,binding:number,name:string,resource:string}> }} reflection
 * @returns {Array<{ line: number, texture: string, sampler: string }>}
 */
export function findDepthFilteringPairs(source, reflection, contract = loadBindGroup0Contract()) {
  if (!reflection?.ok || !Array.isArray(reflection.bindings)) return [];
  const group = contract.group ?? 0;
  const bindingsOfKind = (kind) => new Set(contract.bindings.filter((b) => b.kind === kind).map((b) => b.binding));
  const depthBindings = bindingsOfKind('sampled-r32');
  const filteringBindings = bindingsOfKind('filtering-sampler');
  const depthNames = new Set();
  const filteringNames = new Set();
  for (const b of reflection.bindings) {
    if (b.group !== group) continue;
    if (depthBindings.has(b.binding) && b.resource === 'texture') depthNames.add(b.name);
    if (filteringBindings.has(b.binding) && b.resource === 'sampler') filteringNames.add(b.name);
  }
  if (depthNames.size === 0 || filteringNames.size === 0) return [];

  const code = stripComments(source);
  const hits = [];
  for (const m of code.matchAll(SAMPLE_CALL)) {
    const [, texture, sampler] = m;
    if (!depthNames.has(texture) || !filteringNames.has(sampler)) continue;
    const line = code.slice(0, m.index).split('\n').length;
    hits.push({ line, texture, sampler });
  }
  return hits;
}
