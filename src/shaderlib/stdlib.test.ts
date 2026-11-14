// @vitest-environment node
/**
 * Shader standard library (public/shaders/_std) contract + golden tests.
 *
 * GPU-less: every module (with its dependencies, and the prelude where it
 * asks for it) and the golden harness are validated by the real committed
 * naga (public/wasm/naga_wasm.wasm). The golden VALUES are executed on
 * SwiftShader by scripts/shaderlib-golden.ts; here the integer-hash goldens are
 * re-derived from an exact TypeScript PCG so a GPU capture cannot bless a
 * wrong hash.
 */
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import type { NagaValidator } from '../utils/nagaWasm';
import {
  buildGoldenHarness,
  composeStdModules,
  GoldenCase,
  goldenWidth,
  parseStdModule,
  STD_DIR,
  STD_MODULE_NAMES,
  StdModule,
  stdDependencyOrder,
  stdFileName,
} from './stdlib';

const ROOT = path.resolve(__dirname, '../..');
const read = (p: string) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const PRELUDE = read('public/shaders/_prelude.wgsl');
const golden = JSON.parse(read('src/contracts/shaderlib_golden.json')) as {
  cases: (GoldenCase & { analytic: boolean })[];
};

const modules = new Map<string, StdModule>();
for (const n of STD_MODULE_NAMES) modules.set(n, parseStdModule(read(`${STD_DIR}/${stdFileName(n)}`)));
const mod = (n: string): StdModule => {
  const m = modules.get(n);
  if (!m) throw new Error(`missing module ${n}`);
  return m;
};

let naga: NagaValidator;
beforeAll(async () => {
  const loader = (await import(pathToFileURL(path.join(ROOT, 'public/wasm/naga_wasm.js')).href)) as {
    createNagaValidator(o: { bytes: BufferSource }): Promise<NagaValidator>;
  };
  naga = await loader.createNagaValidator({ bytes: fs.readFileSync(path.join(ROOT, 'public/wasm/naga_wasm.wasm')) });
});

describe('_std module contract', () => {
  it('the directory holds exactly the declared modules', () => {
    const files = fs.readdirSync(path.join(ROOT, STD_DIR)).filter((f) => f.endsWith('.wgsl')).sort();
    expect(files).toEqual(STD_MODULE_NAMES.map(stdFileName).sort());
  });

  it.each(STD_MODULE_NAMES)('%s: header names the file and its dependencies exist', (n) => {
    const m = mod(n);
    expect(m.name).toBe(n);
    expect(m.version).toBeGreaterThanOrEqual(1);
    for (const r of m.requires) expect(STD_MODULE_NAMES).toContain(r);
    expect(m.decls.length).toBeGreaterThan(0);
  });

  it.each(STD_MODULE_NAMES)('%s: every declaration is documented, every fn states its cost', (n) => {
    for (const d of mod(n).decls) {
      expect(d.summary, `${n}.${d.name} has no /// summary`).not.toBe('');
      if (d.kind === 'fn') expect(d.cost, `${n}.${d.name} has no @cost`).toBeTruthy();
    }
  });

  it('no name is declared by two modules (the linker emits by name)', () => {
    const seen = new Map<string, string>();
    for (const m of modules.values()) {
      for (const d of m.decls) {
        expect(seen.get(d.name), `${d.name} in both ${seen.get(d.name)} and ${m.name}`).toBeUndefined();
        seen.set(d.name, m.name);
      }
    }
  });

  it('declares the hash family the issue lists', () => {
    const names = mod('hash').decls.map((d) => d.name);
    for (const h of ['hash11', 'hash12', 'hash13', 'hash21', 'hash22', 'hash23', 'hash31', 'hash32', 'hash33', 'hash41']) {
      expect(names).toContain(h);
    }
  });

  it('hashes are integer-only: no sin()/fract(sin) anywhere in _std', () => {
    const code = (m: StdModule) => m.source.replace(/\/\/.*$/gm, '');
    expect(code(mod('hash'))).not.toMatch(/\bsin\s*\(/);
    for (const m of modules.values()) expect(code(m)).not.toMatch(/fract\s*\(\s*sin/);
  });

  it('only modules that say @requires prelude touch bindings or uniforms', () => {
    for (const m of modules.values()) {
      const touches = /\b(plasmaBuffer|extraBuffer|readTexture|u\.config|u\.zoom_)/.test(m.source.replace(/\/\/.*$/gm, ''));
      expect(touches, m.name).toBe(m.requiresPrelude);
    }
  });

  it('resolves dependencies first, each once', () => {
    expect(stdDependencyOrder(modules, ['noise'])).toEqual(['math', 'hash', 'noise']);
    expect(stdDependencyOrder(modules, ['color', 'noise', 'math'])).toEqual(['math', 'color', 'hash', 'noise']);
    expect(() => stdDependencyOrder(modules, ['nope'])).toThrow(/unknown std module/);
  });
});

describe('_std validates under naga', () => {
  it.each(STD_MODULE_NAMES)('%s (with its dependencies)', (n) => {
    const src = (mod(n).requiresPrelude ? PRELUDE + '\n' : '') + composeStdModules(modules, [n]);
    const r = naga.validate(src);
    expect(r.ok, r.message).toBe(true);
  });

  it('all modules together (no collisions with each other or the prelude)', () => {
    const r = naga.validate(PRELUDE + '\n' + composeStdModules(modules, [...STD_MODULE_NAMES]));
    expect(r.ok, r.message).toBe(true);
  });

  it('the golden harness compiles', () => {
    const { wgsl } = buildGoldenHarness(modules, golden.cases);
    const r = naga.validate(wgsl);
    expect(r.ok, r.message).toBe(true);
  });
});

// ── Exact TypeScript reference for the PCG family (u32 wraparound) ──────────
const pcg = (v: number): number => {
  const s = (Math.imul(v >>> 0, 747796405) + 2891336453) >>> 0;
  const w = Math.imul(((s >>> ((s >>> 28) + 4)) ^ s) >>> 0, 277803737) >>> 0;
  return ((w >>> 22) ^ w) >>> 0;
};
const lcg = (v: number) => (Math.imul(v >>> 0, 1664525) + 1013904223) >>> 0;
const pcg2d = (a: number, b: number): [number, number] => {
  let x = lcg(a);
  let y = lcg(b);
  for (let r = 0; r < 2; r++) {
    x = (x + Math.imul(y, 1664525)) >>> 0;
    y = (y + Math.imul(x, 1664525)) >>> 0;
    x = (x ^ (x >>> 16)) >>> 0;
    y = (y ^ (y >>> 16)) >>> 0;
  }
  return [x, y];
};
const pcg3d = (a: number, b: number, c: number): [number, number, number] => {
  let [x, y, z] = [lcg(a), lcg(b), lcg(c)];
  const mix = () => {
    x = (x + Math.imul(y, z)) >>> 0;
    y = (y + Math.imul(z, x)) >>> 0;
    z = (z + Math.imul(x, y)) >>> 0;
  };
  mix();
  [x, y, z] = [(x ^ (x >>> 16)) >>> 0, (y ^ (y >>> 16)) >>> 0, (z ^ (z >>> 16)) >>> 0];
  mix();
  return [x, y, z];
};
const pcg4d = (a: number, b: number, c: number, d: number): [number, number, number, number] => {
  let [x, y, z, w] = [lcg(a), lcg(b), lcg(c), lcg(d)];
  const mix = () => {
    x = (x + Math.imul(y, w)) >>> 0;
    y = (y + Math.imul(z, x)) >>> 0;
    z = (z + Math.imul(x, y)) >>> 0;
    w = (w + Math.imul(y, z)) >>> 0;
  };
  mix();
  [x, y, z, w] = [x, y, z, w].map((v) => (v ^ (v >>> 16)) >>> 0) as [number, number, number, number];
  mix();
  return [x, y, z, w];
};
const unit = (u: number) => (u >>> 8) / 16777216;
const bits = (f: number) => new Uint32Array(new Float32Array([f]).buffer)[0] ?? 0;
const i32 = (i: number) => i >>> 0;

const REFERENCE: Record<string, () => number[]> = {
  'hash.pcg.0': () => [pcg(0)],
  'hash.pcg.1': () => [pcg(1)],
  'hash.pcg.max': () => [pcg(0xffffffff)],
  'hash.pcg2d.x': () => [pcg2d(1, 2)[0]],
  'hash.pcg2d.y': () => [pcg2d(1, 2)[1]],
  'hash.pcg3d.x': () => [pcg3d(1, 2, 3)[0]],
  'hash.pcg3d.z': () => [pcg3d(1, 2, 3)[2]],
  'hash.pcg4d.w': () => [pcg4d(1, 2, 3, 4)[3]],
  'hash.hash11': () => [unit(pcg(bits(0.5)))],
  'hash.hash12': () => pcg2d(bits(0.5), 0x9e3779b9).map(unit),
  'hash.hash13': () => pcg3d(bits(0.5), 0x9e3779b9, 0x85ebca6b).map(unit),
  'hash.hash21': () => [unit(pcg2d(bits(0.5), bits(1.25))[0])],
  'hash.hash22': () => pcg2d(bits(0.5), bits(1.25)).map(unit),
  'hash.hash23': () => pcg3d(bits(0.5), bits(1.25), 0x9e3779b9).map(unit),
  'hash.hash31': () => [unit(pcg3d(bits(1), bits(2), bits(3))[0])],
  'hash.hash32': () => pcg3d(bits(1), bits(2), bits(3)).slice(0, 2).map(unit),
  'hash.hash33': () => pcg3d(bits(1), bits(2), bits(3)).map(unit),
  'hash.hash41': () => [unit(pcg4d(bits(1), bits(2), bits(3), bits(4))[0])],
  'hash.hashCell21.negative': () => [unit(pcg2d(i32(-3), i32(7))[0])],
  'hash.hashCell33': () => pcg3d(i32(-1), 0, 5).map(unit),
  // value noise at a lattice point is exactly the cell hash
  'noise.valueNoise.lattice': () => [unit(pcg2d(i32(-3), i32(7))[0])],
};

describe('golden cases', () => {
  it('are well-formed and uniquely named', () => {
    const ids = golden.cases.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const c of golden.cases) {
      expect(c.expected, c.id).toHaveLength(goldenWidth(c.type));
      for (const m of c.modules) expect(STD_MODULE_NAMES, c.id).toContain(m);
    }
  });

  it.each(Object.keys(REFERENCE))('%s matches the exact TypeScript PCG', (id) => {
    const c = golden.cases.find((g) => g.id === id);
    expect(c, `golden case ${id} missing`).toBeDefined();
    const want = REFERENCE[id]?.() ?? [];
    // hash floats are k / 2^24, exactly representable: compare in f32 space
    expect(c?.expected.map((v) => (c.type === 'u32' ? v : Math.fround(v)))).toEqual(want);
  });

  it('every hash case has an independent reference', () => {
    for (const c of golden.cases.filter((g) => g.id.startsWith('hash.'))) expect(REFERENCE[c.id], c.id).toBeDefined();
  });
});

describe('ACES: one implementation, clamped input', () => {
  // The fit every catalog shader pastes, without the clamp.
  const catalogAces = (x: number) => (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);

  it('documents the bug being fixed: the unclamped fit maps -0.18 to ≈0.68', () => {
    expect(catalogAces(-0.18)).toBeCloseTo(0.675, 2);
  });

  it('_std aces clamps input and the golden pins aces(-0.18) == 0 on the GPU', () => {
    expect(mod('tonemap').source).toMatch(/fn aces\(x_in: vec3<f32>\) -> vec3<f32> \{\s*let x = max\(x_in, vec3<f32>\(0\.0\)\);/);
    const neg = golden.cases.find((c) => c.id === 'tonemap.aces.negative');
    expect(neg).toMatchObject({ analytic: true, expected: [0, 0, 0], tol: 0 });
    const mid = golden.cases.find((c) => c.id === 'tonemap.aces.mid');
    expect(mid?.expected[0]).toBeCloseTo(catalogAces(0.18), 6);
  });

  it('_std defines aces exactly once', () => {
    const defs = [...modules.values()].flatMap((m) => m.decls.filter((d) => d.name === 'aces'));
    expect(defs).toHaveLength(1);
  });
});

describe('docs/SHADER_STDLIB.md', () => {
  it('is generated from the current module headers (npm run shaderlib:docs)', async () => {
    const { renderStdlibDocs } = await import('./stdlibDocs');
    expect(read('docs/SHADER_STDLIB.md')).toBe(renderStdlibDocs(STD_MODULE_NAMES.map(mod)));
  });
});
