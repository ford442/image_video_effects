import { readFileSync } from 'fs';
import { resolve } from 'path';
import { chooseF16Variant, requiresF16, toF16Variant } from './wgslF16';
import { loadRealNaga } from '../test-utils/nagaWasmNode';

const HALF_LIBRARY = readFileSync(resolve(__dirname, '../../public/shaders/_half.wgsl'), 'utf8');

const OPTED_IN = `// @requires f16
// A half-precision effect.
${HALF_LIBRARY}
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let n = fbm4_h(vec2<f32>(gid.xy) / 16.0);
  let c = saturate_h(hf3(n, 0.5, 0.25), 1.2);
  textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(vec3<f32>(c), 1.0));
}
`;

describe('shader-f16 variant path (#1512)', () => {
  it('detects the // @requires f16 header line', () => {
    expect(requiresF16(OPTED_IN)).toBe(true);
    expect(requiresF16('//   @requires   f16\nfn main() {}')).toBe(true);
    expect(requiresF16('// requires f16 maybe')).toBe(false);
    expect(requiresF16('let x = 1; // @requires f32')).toBe(false);
  });

  it('retargets only the half aliases and prepends enable f16', () => {
    const half = toF16Variant(OPTED_IN);
    expect(half.startsWith('enable f16;\n')).toBe(true);
    expect(half).toContain('alias hf = f16;');
    expect(half).toContain('alias hf2 = vec2<f16>;');
    expect(half).toContain('alias hf3 = vec3<f16>;');
    expect(half).toContain('alias hf4 = vec4<f16>;');
    // Everything outside the alias declarations is untouched.
    expect(half.replace(/^enable f16;\n/, '').replace(/alias (hf[234]?) = (vec[234]<)?f16>?;/g, 'X'))
      .toBe(OPTED_IN.replace(/alias (hf[234]?) = (vec[234]<)?f32>?;/g, 'X'));
    // Idempotent: a second pass neither adds a directive nor changes anything.
    expect(toF16Variant(half)).toBe(half);
  });

  it('accepts the vecNf shorthand in alias declarations', () => {
    expect(toF16Variant('// @requires f16\nalias hf3 = vec3f;\n')).toContain('alias hf3 = vec3<f16>;');
  });

  it('leaves shaders that did not opt in byte-identical', () => {
    const plain = 'alias hf = f32;\nfn main() {}\n';
    expect(toF16Variant(plain)).toBe(plain);
    expect(chooseF16Variant(plain, true)).toEqual({ source: plain, variant: 'not-requested' });
  });

  it('falls back to the f32 source without shader-f16', () => {
    expect(chooseF16Variant(OPTED_IN, false)).toEqual({ source: OPTED_IN, variant: 'f32' });
    expect(chooseF16Variant(OPTED_IN, true).variant).toBe('f16');
  });

  it('ships f32-valid: the library and an opted-in shader pass naga as written', async () => {
    const naga = await loadRealNaga();
    expect(naga.validate(HALF_LIBRARY)).toMatchObject({ ok: true });
    expect(naga.validate(OPTED_IN)).toMatchObject({ ok: true });
  });
});
