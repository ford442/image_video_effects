/**
 * wgslCompletions.ts
 *
 * Autocomplete for the WGSL editor, generated from library sources rather than a
 * hand-written list: `_prelude.wgsl` (bundled, wgslLibraries.ts) gives the 13
 * bindings, the `Uniforms` fields with their `u.` paths and the meaning of each
 * lane from its contract comment block; any other included library contributes
 * its `fn`s. A regenerated prelude changes the completions with it.
 *
 * The draft's own `// @param` names are offered as `u.zoom_params.x…w`.
 */

import { BUNDLED_WGSL_LIBRARIES } from '../wasm/bridge/wgslLibraries';
import type { DraftParam } from './wgslParams';

export interface CompletionSpec {
  label: string;
  type: 'variable' | 'function' | 'property' | 'keyword' | 'type';
  detail?: string;
  info?: string;
  /** Text to insert when it differs from the label. */
  apply?: string;
}

const BINDING_RE = /@group\((\d+)\)\s*@binding\((\d+)\)\s*var(?:<([^>]*)>)?\s+(\w+)\s*:\s*([^;]+);/g;
const STRUCT_RE = /struct\s+(\w+)\s*\{([^}]*)\}/g;
const FIELD_RE = /^\s*(\w+)\s*:\s*([^/]+?)\s*,?\s*(?:\/\/\s*(.*))?$/;
const FN_RE = /^\s*fn\s+(\w+)\s*\(([^)]*)\)\s*(?:->\s*([^{]+?))?\s*\{/gm;
/** `//   config.x      time in seconds …` lines of the prelude's contract block. */
const LANE_NOTE_RE = /^\/\/\s{2,}([a-z_]+(?:\[i\])?(?:\.[xyzw]+)?)\s+(.+)$/gm;

const LANES = ['x', 'y', 'z', 'w'] as const;

const KEYWORDS = [
  'fn', 'let', 'var', 'const', 'override', 'struct', 'return', 'if', 'else', 'for', 'while', 'loop',
  'break', 'continue', 'switch', 'case', 'default', 'discard', 'true', 'false', 'alias', 'continuing',
];
const TYPES = [
  'f32', 'i32', 'u32', 'bool', 'f16', 'vec2<f32>', 'vec3<f32>', 'vec4<f32>', 'vec2<i32>', 'vec2<u32>',
  'vec2f', 'vec3f', 'vec4f', 'vec2i', 'vec2u', 'mat2x2<f32>', 'mat3x3<f32>', 'mat4x4<f32>',
];
const BUILTINS = [
  'abs', 'acos', 'asin', 'atan', 'atan2', 'ceil', 'clamp', 'cos', 'cross', 'distance', 'dot', 'exp',
  'exp2', 'floor', 'fract', 'length', 'log', 'log2', 'max', 'min', 'mix', 'normalize', 'pow', 'reflect',
  'round', 'select', 'sign', 'sin', 'smoothstep', 'sqrt', 'step', 'tan', 'tanh', 'textureDimensions',
  'textureLoad', 'textureSampleLevel', 'textureStore', 'arrayLength', 'atomicAdd', 'workgroupBarrier',
];
const ATTRIBUTES = [
  '@compute', '@workgroup_size(8, 8, 1)', '@builtin(global_invocation_id)', '@group(0)', '@binding(0)',
];

interface Field {
  name: string;
  type: string;
  comment?: string;
}

function parseStructs(source: string): Map<string, Field[]> {
  const out = new Map<string, Field[]>();
  for (const m of source.matchAll(STRUCT_RE)) {
    const fields: Field[] = [];
    for (const line of (m[2] ?? '').split('\n')) {
      const f = FIELD_RE.exec(line);
      if (f?.[1] && f[2]) fields.push({ name: f[1], type: f[2].trim(), comment: f[3]?.trim() || undefined });
    }
    if (m[1]) out.set(m[1], fields);
  }
  return out;
}

/** `config.x` → its contract note, `zoom_params` → …; `ripples[i].xy` keyed as `ripples.xy`. */
function laneNotes(source: string): Map<string, string> {
  const out = new Map<string, string>();
  for (const m of source.matchAll(LANE_NOTE_RE)) {
    if (m[1] && m[2]) out.set(m[1].replace('[i]', ''), m[2].trim());
  }
  return out;
}

function vecWidth(type: string): number {
  const m = /^vec([234])/.exec(type);
  return m ? Number(m[1]) : 0;
}

/** Completions from one library source (prelude or any `_lib.wgsl`). */
export function completionsFromLibrary(name: string, source: string): CompletionSpec[] {
  const out: CompletionSpec[] = [];
  const structs = parseStructs(source);
  const notes = laneNotes(source);

  for (const m of source.matchAll(BINDING_RE)) {
    const [, group, binding, space, varName, type] = m;
    if (!varName || !type) continue;
    out.push({
      label: varName,
      type: 'variable',
      detail: type.trim(),
      info: `@group(${group}) @binding(${binding})${space ? ` var<${space}>` : ''} — ${name}`,
    });
    const fields = structs.get(type.trim());
    if (!fields) continue;
    for (const f of fields) {
      const path = `${varName}.${f.name}`;
      out.push({ label: path, type: 'property', detail: f.type, info: notes.get(f.name) ?? f.comment });
      const width = vecWidth(f.type);
      for (const lane of LANES.slice(0, width)) {
        const laneNote = notes.get(`${f.name}.${lane}`) ??
          [...notes.entries()].find(([k]) => k.startsWith(`${f.name}.`) && k.slice(f.name.length + 1).includes(lane))?.[1];
        out.push({ label: `${path}.${lane}`, type: 'property', detail: 'f32', info: laneNote ?? f.comment });
      }
    }
  }

  for (const m of source.matchAll(FN_RE)) {
    const [, fnName, args, ret] = m;
    if (!fnName) continue;
    out.push({
      label: fnName,
      type: 'function',
      detail: `(${(args ?? '').replace(/\s+/g, ' ').trim()})${ret ? ` -> ${ret.trim()}` : ''}`,
      info: name,
      apply: `${fnName}(`,
    });
  }
  return out;
}

/** Param names → their `u.zoom_params` lane. */
export function completionsFromParams(params: readonly DraftParam[]): CompletionSpec[] {
  return params.map((p, i) => ({
    label: `u.${p.mapping}`,
    type: 'property',
    detail: `p${i + 1} · ${p.id}`,
    info: `${p.name}: ${p.min}…${p.max} (default ${p.default})`,
  }));
}

const STATIC: CompletionSpec[] = [
  ...KEYWORDS.map((label): CompletionSpec => ({ label, type: 'keyword' })),
  ...TYPES.map((label): CompletionSpec => ({ label, type: 'type' })),
  ...BUILTINS.map((label): CompletionSpec => ({ label, type: 'function', detail: 'WGSL builtin', apply: `${label}(` })),
  ...ATTRIBUTES.map((label): CompletionSpec => ({ label, type: 'keyword', detail: 'attribute' })),
];

/**
 * Everything the editor offers: the bundled prelude, every library the draft's
 * expansion resolved, the draft's params and the WGSL basics. Param entries win
 * over the generic `u.zoom_params.*` ones (same label).
 */
export function buildCompletions(
  libraries: ReadonlyMap<string, string> = new Map(),
  params: readonly DraftParam[] = [],
): CompletionSpec[] {
  const sources = new Map<string, string>(Object.entries(BUNDLED_WGSL_LIBRARIES));
  for (const [name, text] of libraries) sources.set(name, text);
  const byLabel = new Map<string, CompletionSpec>();
  for (const spec of STATIC) byLabel.set(spec.label, spec);
  for (const [name, text] of sources) for (const spec of completionsFromLibrary(name, text)) byLabel.set(spec.label, spec);
  for (const spec of completionsFromParams(params)) byLabel.set(spec.label, spec);
  return [...byLabel.values()];
}
