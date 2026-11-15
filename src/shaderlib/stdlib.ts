/**
 * Shader standard library (`public/shaders/_std/`) — module metadata.
 *
 * Pure functions over module source text (no fs), shared by the unit tests,
 * the docs generator (scripts/generate-shader-stdlib-docs.ts) and the GPU
 * golden runner (scripts/shaderlib-golden.ts). The function-level linker
 * (`#import fbm from "_std/noise"`) is a later slice; until it lands, a
 * module set is composed by concatenating whole modules in dependency order
 * (`composeStdModules`), which is what the tests validate.
 *
 * Module header contract (see docs/SHADER_STDLIB.md):
 *   //  @std-module <name>       — short name, file is _std_<name>.wgsl
 *   //  @std-version <int>
 *   //  @requires <a>, <b> | (none)   — other module names, or `prelude`
 * Every top-level `fn` / `const` is preceded by `///` doc lines; a fn's doc
 * may carry `@range` and `@cost` tags.
 */

export const STD_DIR = 'public/shaders/_std';
export const STD_MODULE_NAMES = ['math', 'hash', 'noise', 'color', 'tonemap', 'sdf', 'sample', 'audio'] as const;
export type StdModuleName = (typeof STD_MODULE_NAMES)[number];

export const stdFileName = (name: string): string => `_std_${name}.wgsl`;

export interface StdDecl {
  kind: 'fn' | 'const';
  name: string;
  /** `fn name(args) -> ret` or `const NAME: T`, whitespace-normalised. */
  signature: string;
  summary: string;
  range?: string;
  cost?: string;
  line: number;
}

export interface StdModule {
  name: string;
  version: number;
  /** Other std modules this one needs, in declared order. */
  requires: string[];
  /** Needs the 13-binding `_prelude.wgsl` (references bindings / Uniforms). */
  requiresPrelude: boolean;
  title: string;
  decls: StdDecl[];
  source: string;
}

const TAG = (tag: string, src: string): string | undefined =>
  new RegExp(`^//\\s*@${tag}\\s+(.+?)\\s*$`, 'm').exec(src)?.[1];

export function parseStdModule(source: string): StdModule {
  const name = TAG('std-module', source);
  const version = Number(TAG('std-version', source));
  const req = TAG('requires', source);
  if (!name) throw new Error('std module is missing `// @std-module <name>`');
  if (!Number.isInteger(version) || version < 1) throw new Error(`std module ${name}: bad @std-version`);
  if (req === undefined) throw new Error(`std module ${name}: missing @requires`);
  const reqList = req === '(none)' ? [] : req.split(',').map((s) => s.trim()).filter(Boolean);
  const title = /^\/\/\s+_std\/_std_\w+\.wgsl\s+—\s+(.+)$/m.exec(source)?.[1]?.trim() ?? name;

  const lines = source.split('\n');
  const decls: StdDecl[] = [];
  let doc: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] ?? '';
    const d = /^\/\/\/\s?(.*)$/.exec(line);
    if (d) {
      doc.push(d[1] ?? '');
      continue;
    }
    const fn = /^fn\s+(\w+)\s*\(/.exec(line);
    const cn = /^const\s+(\w+)\s*:\s*([^=]+?)\s*=/.exec(line);
    if (fn || cn) {
      let signature: string;
      if (fn) {
        let sig = line;
        for (let j = i + 1; !sig.includes('{') && j < lines.length; j++) sig += ' ' + (lines[j] ?? '');
        signature = sig.slice(0, sig.indexOf('{')).replace(/\s+/g, ' ').trim();
      } else {
        signature = `const ${cn?.[1]}: ${cn?.[2]}`;
      }
      const tag = (t: string) => doc.find((l) => l.startsWith(`@${t} `))?.slice(t.length + 2).trim();
      decls.push({
        kind: fn ? 'fn' : 'const',
        name: (fn ?? cn)?.[1] ?? '',
        signature,
        summary: doc.filter((l) => !l.startsWith('@')).join(' ').trim(),
        range: tag('range'),
        cost: tag('cost'),
        line: i + 1,
      });
    }
    doc = [];
  }
  return {
    name,
    version,
    requires: reqList.filter((r) => r !== 'prelude'),
    requiresPrelude: reqList.includes('prelude'),
    title,
    decls,
    source,
  };
}

/** Modules needed for `wanted` (transitively), dependencies first, each once. */
export function stdDependencyOrder(modules: ReadonlyMap<string, StdModule>, wanted: readonly string[]): string[] {
  const out: string[] = [];
  const visiting = new Set<string>();
  const visit = (n: string, chain: string[]) => {
    if (out.includes(n)) return;
    if (visiting.has(n)) throw new Error(`std module cycle: ${[...chain, n].join(' → ')}`);
    const m = modules.get(n);
    if (!m) throw new Error(`unknown std module "${n}"${chain.length ? ` (required by ${chain.at(-1)})` : ''}`);
    visiting.add(n);
    for (const r of m.requires) visit(r, [...chain, n]);
    visiting.delete(n);
    out.push(n);
  };
  for (const w of wanted) visit(w, []);
  return out;
}

/** Whole-module concatenation in dependency order (pre-linker composition). */
export function composeStdModules(modules: ReadonlyMap<string, StdModule>, wanted: readonly string[]): string {
  return stdDependencyOrder(modules, wanted)
    .map((n) => modules.get(n)?.source ?? '')
    .join('\n');
}

export type GoldenType = 'f32' | 'vec2' | 'vec3' | 'vec4' | 'u32';
export interface GoldenCase {
  id: string;
  modules: string[];
  expr: string;
  type: GoldenType;
  expected: number[];
  /** Absolute tolerance; 0 = exact (u32 cases and exact float results). */
  tol: number;
}

export const goldenWidth = (t: GoldenType): number =>
  t === 'f32' || t === 'u32' ? 1 : Number(t.slice(3));

/**
 * One compute shader evaluating every case into `std_golden_out` (u32 cases are
 * written as raw bits via bitcast so they survive the f32 buffer exactly).
 */
export function buildGoldenHarness(modules: ReadonlyMap<string, StdModule>, cases: readonly GoldenCase[]): {
  wgsl: string;
  offsets: number[];
  floats: number;
} {
  const wanted = [...new Set(cases.flatMap((c) => c.modules))];
  const lib = composeStdModules(modules, wanted);
  const offsets: number[] = [];
  let o = 0;
  const body = cases
    .map((c) => {
      offsets.push(o);
      const w = goldenWidth(c.type);
      const ty = c.type === 'f32' ? 'f32' : c.type === 'u32' ? 'u32' : `${c.type}<f32>`;
      const comps = w === 1 ? ['v'] : ['v.x', 'v.y', 'v.z', 'v.w'].slice(0, w);
      const writes = comps
        .map((e, k) => `std_golden_out[${o + k}u] = ${c.type === 'u32' ? `bitcast<f32>(${e})` : e};`)
        .join(' ');
      o += w;
      return `  { let v: ${ty} = ${c.expr}; ${writes} } // ${c.id}`;
    })
    .join('\n');
  const wgsl = `${lib}
@group(0) @binding(0) var<storage, read_write> std_golden_out: array<f32>;
@compute @workgroup_size(1)
fn std_golden_main() {
${body}
}
`;
  return { wgsl, offsets, floats: Math.max(o, 1) };
}

/** Compare GPU output to the cases; returns human-readable mismatches. */
export function diffGolden(cases: readonly GoldenCase[], offsets: readonly number[], out: Float32Array): string[] {
  const u = new Uint32Array(out.buffer, out.byteOffset, out.length);
  const bad: string[] = [];
  cases.forEach((c, i) => {
    const o = offsets[i] ?? 0;
    const w = goldenWidth(c.type);
    const got = Array.from({ length: w }, (_, k) => (c.type === 'u32' ? (u[o + k] ?? NaN) : (out[o + k] ?? NaN)));
    const ok = got.every((g, k) => {
      const e = c.expected[k];
      return e !== undefined && Number.isFinite(g) && Math.abs(g - (c.type === 'u32' ? e : Math.fround(e))) <= c.tol;
    });
    if (!ok) bad.push(`${c.id}: expected [${c.expected.join(', ')}] got [${got.join(', ')}] (tol ${c.tol})`);
  });
  return bad;
}
