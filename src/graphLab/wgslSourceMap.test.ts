import { BUNDLED_WGSL_LIBRARIES, withBundledLibraries } from '../wasm/bridge/wgslLibraries';
import { expandDraft, originOf } from './wgslSourceMap';

const LIBS: Record<string, string> = {
  '_a.wgsl': 'fn a() -> f32 { return 1.0; }\nfn a2() -> f32 { return 2.0; }',
  '_b.wgsl': '#include "_c.wgsl"\nfn b() -> f32 { return c(); }',
  '_c.wgsl': 'fn c() -> f32 { return 3.0; }',
};
const resolve = withBundledLibraries(async (name) => LIBS[name] ?? null);

describe('expandDraft', () => {
  it('maps every expanded line back to the user line, libraries to their #include line', async () => {
    const src = ['// head', '#include "_prelude.wgsl"', 'let x = 1;', '#include "_b.wgsl"', '/* #include "_a.wgsl" */', 'fn main() {}'].join('\n');
    const r = await expandDraft(src, resolve);
    if (!r.ok) throw new Error(r.message);
    const out = r.expanded.text.split('\n');
    expect(r.expanded.lineMap).toHaveLength(out.length);
    // Every user line appears where the map says it does.
    src.split('\n').forEach((text, i) => {
      if (text.startsWith('#include')) return;
      const k = r.expanded.lineMap.findIndex((o) => o.kind === 'user' && o.line === i + 1);
      expect(out[k]).toBe(text);
    });
    const preludeLines = BUNDLED_WGSL_LIBRARIES['_prelude.wgsl']!.split('\n').length;
    const firstPrelude = r.expanded.lineMap.findIndex((o) => o.kind === 'library');
    expect(r.expanded.lineMap.slice(firstPrelude, firstPrelude + preludeLines + 1).every((o) => o.kind === 'library' && o.includeLine === 2)).toBe(true);
    // A line of the nested _c.wgsl is blamed on the user's `#include "_b.wgsl"`.
    const cLine = out.indexOf(LIBS['_c.wgsl']!) + 1;
    expect(originOf(r.expanded, cLine)).toMatchObject({ kind: 'library', name: '_b.wgsl', includeLine: 4 });
    expect(originOf(r.expanded, out.indexOf('fn main() {}') + 1)).toEqual({ kind: 'user', line: 6 });
    expect([...r.expanded.libraries.keys()].sort()).toEqual(['_b.wgsl', '_c.wgsl', '_prelude.wgsl']);
  });

  it('is the identity map without includes', async () => {
    const r = await expandDraft('a\nb', resolve);
    expect(r.ok && r.expanded.lineMap).toEqual([{ kind: 'user', line: 1 }, { kind: 'user', line: 2 }]);
  });

  it('puts an include error on the directive line', async () => {
    const r = await expandDraft('// x\n\n#include "_missing.wgsl"', resolve);
    expect(r).toMatchObject({ ok: false, line: 3 });
    const twice = await expandDraft('#include "_a.wgsl"\n#include "_a.wgsl"', resolve);
    expect(twice).toMatchObject({ ok: false, line: 2 });
  });

  it('maps naga line 0 to user line 1', async () => {
    const r = await expandDraft('a', resolve);
    expect(r.ok && originOf(r.expanded, 0)).toEqual({ kind: 'user', line: 1 });
  });
});
