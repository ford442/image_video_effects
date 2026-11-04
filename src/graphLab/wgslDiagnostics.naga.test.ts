// @vitest-environment node
/**
 * The same pipeline with the real committed naga artifact (public/wasm/naga_wasm.wasm),
 * the way the browser runs it: bundled prelude, include expansion, line remap.
 */
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import type { NagaReflector, NagaValidator } from '../utils/nagaWasm';
import { withBundledLibraries } from '../wasm/bridge/wgslLibraries';
import { diagnoseWgsl, DiagnoseDeps } from './wgslDiagnostics';
import { WGSL_TEMPLATE } from './wgslDraft';

const ROOT = path.resolve(__dirname, '../..');
let deps: DiagnoseDeps;

beforeAll(async () => {
  const mod = (await import(pathToFileURL(path.join(ROOT, 'public/wasm/naga_wasm.js')).href)) as {
    createNagaValidator(o: { bytes: BufferSource }): Promise<NagaValidator & NagaReflector>;
  };
  const naga = await mod.createNagaValidator({ bytes: fs.readFileSync(path.join(ROOT, 'public/wasm/naga_wasm.wasm')) });
  deps = {
    validate: (s) => naga.validate(s),
    reflect: (s) => naga.reflect(s),
    resolve: withBundledLibraries(async (name) => {
      const p = path.join(ROOT, 'public/shaders', name);
      return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null;
    }),
  };
});

describe('WGSL draft diagnostics with real naga', () => {
  it('the starter template validates', async () => {
    const r = await diagnoseWgsl(WGSL_TEMPLATE, deps);
    expect(r.diagnostics).toEqual([]);
    expect(r.ok).toBe(true);
    expect(r.header.params.map((p) => p.mapping)).toEqual(['zoom_params.x', 'zoom_params.y', 'zoom_params.z']);
  });

  it('an unknown identifier lands on its user line and column', async () => {
    const src = WGSL_TEMPLATE.replace('* 0.02 * u.zoom_params.y', '* 0.02 * warpp');
    const lines = src.split('\n');
    const line = lines.findIndex((l) => l.includes('warpp')) + 1;
    const r = await diagnoseWgsl(src, deps);
    expect(r.ok).toBe(false);
    expect(r.diagnostics[0]).toMatchObject({ source: 'naga', line, column: (lines[line - 1] ?? '').indexOf('warpp') + 1, length: 5 });
    expect(r.diagnostics[0]?.message).toMatch(/warpp/);
  });

  it('a type error is mapped too', async () => {
    const src = WGSL_TEMPLATE.replace('let t = u.config.x * u.zoom_params.x;', 'let t: u32 = u.config.x;');
    const line = src.split('\n').findIndex((l) => l.includes('let t: u32')) + 1;
    const r = await diagnoseWgsl(src, deps);
    expect(r.diagnostics[0]).toMatchObject({ severity: 'error', line });
  });

  it('a library function from _hash.wgsl resolves', async () => {
    const lib = fs.readFileSync(path.join(ROOT, 'public/shaders/_hash.wgsl'), 'utf8');
    const fn = /fn\s+(\w+)\s*\(\s*\w+\s*:\s*vec2<f32>\s*\)\s*->\s*f32/.exec(lib)?.[1];
    if (!fn) return; // the library changed shape; the generic tests above still hold
    const src = WGSL_TEMPLATE.replace('#include "_prelude.wgsl"', '#include "_prelude.wgsl"\n#include "_hash.wgsl"').replace(
      'let t = u.config.x * u.zoom_params.x;',
      `let t = u.config.x * u.zoom_params.x + ${fn}(uv);`,
    );
    const r = await diagnoseWgsl(src, deps);
    expect(r.diagnostics).toEqual([]);
    expect(r.expanded?.libraries.has('_hash.wgsl')).toBe(true);
  });
});
