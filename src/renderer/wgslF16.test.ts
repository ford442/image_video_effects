import { readFileSync } from 'fs';
import { resolve } from 'path';
import { loadRealNaga } from '../test-utils/nagaWasmNode';
import { expandWgslIncludes } from '../wasm/bridge/wgslInclude';
import { BUNDLED_WGSL_LIBRARIES } from '../wasm/bridge/wgslLibraries';
import { applyF16Variant, F16_ALIASES, requiresF16 } from './wgslF16';

const ROOT = resolve(__dirname, '../..');
const read = (rel: string) => readFileSync(resolve(ROOT, rel), 'utf8');

async function expand(source: string): Promise<string> {
  return expandWgslIncludes(source, async (name) => BUNDLED_WGSL_LIBRARIES[name] ?? read(`public/shaders/${name}`), 'fixture.wgsl');
}

describe('shader-f16 variant path (#1512)', () => {
  it('detects the // @requires f16 header line', () => {
    expect(requiresF16('// @requires f16\nfn main() {}')).toBe(true);
    expect(requiresF16('  //@requires f16 (half helpers)\n')).toBe(true);
    expect(requiresF16('// requires f16 later maybe')).toBe(false);
  });

  it('leaves the f32 fallback byte for byte without the feature or the header', async () => {
    const f16 = await expand(read('tests/fixtures/compositor/golden-noise-f16.wgsl'));
    const f32 = await expand(read('tests/fixtures/compositor/golden-noise-f32.wgsl'));
    expect(applyF16Variant(f16, false)).toBe(f16);
    expect(applyF16Variant(f32, true)).toBe(f32);
  });

  it('rewrites every _half.wgsl alias and enables f16 first', async () => {
    const out = applyF16Variant(await expand(read('tests/fixtures/compositor/golden-noise-f16.wgsl')), true);
    expect(out.startsWith('enable f16;\n')).toBe(true);
    for (const [, f16] of F16_ALIASES) expect(out).toContain(f16);
    expect(out).not.toMatch(/^alias h\w+ = (?:vec\d<)?f32>?;$/m);
  });

  it('ships the bundled _half.wgsl the rewrite expects (alias lines intact)', () => {
    const half = BUNDLED_WGSL_LIBRARIES['_half.wgsl'] ?? '';
    expect(half).toBe(read('public/shaders/_half.wgsl'));
    for (const [pattern] of F16_ALIASES) expect(half).toMatch(pattern);
  });

  it('the f32 fallback validates in naga; the f16 variant parses', async () => {
    const naga = await loadRealNaga();
    const source = await expand(read('tests/fixtures/compositor/golden-noise-f16.wgsl'));
    const fallback = naga.validate(source);
    expect(fallback.ok, fallback.ok ? '' : fallback.message).toBe(true);
    // naga-wasm validates without the SHADER_FLOAT16 capability, so f16 types fail its
    // validator; they must still parse. Dawn compiles the variant on shader-f16 devices.
    const variant = naga.validate(applyF16Variant(source, true));
    if (!variant.ok) {
      expect(variant.kind).not.toBe('parse');
      expect(variant.message).toMatch(/'h(?:f|v\d)' is invalid/);
    }
  });
});
