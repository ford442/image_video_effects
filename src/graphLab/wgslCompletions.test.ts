import { BUNDLED_WGSL_LIBRARIES } from '../wasm/bridge/wgslLibraries';
import { buildCompletions, completionsFromLibrary } from './wgslCompletions';
import { parseParamHeader } from './wgslParams';

const prelude = BUNDLED_WGSL_LIBRARIES['_prelude.wgsl']!;

describe('completions generated from the prelude source', () => {
  const specs = completionsFromLibrary('_prelude.wgsl', prelude);
  const byLabel = new Map(specs.map((s) => [s.label, s]));

  it('offers every binding the prelude declares, with its group/binding', () => {
    const declared = [...prelude.matchAll(/@binding\((\d+)\)\s*var(?:<[^>]*>)?\s+(\w+)/g)].map((m) => m[2]);
    expect(declared).toHaveLength(13);
    for (const name of declared) expect(byLabel.get(name!)?.type).toBe('variable');
    expect(byLabel.get('readTexture')).toMatchObject({ detail: 'texture_2d<f32>', info: expect.stringContaining('@binding(1)') });
  });

  it('offers u.<field> and u.zoom_params.{x,y,z,w} with the contract notes', () => {
    for (const lane of ['x', 'y', 'z', 'w']) expect(byLabel.has(`u.zoom_params.${lane}`)).toBe(true);
    expect(byLabel.get('u.config.x')?.info).toMatch(/time in seconds/);
    expect(byLabel.get('u.zoom_config.y')?.info).toMatch(/mouse uv/);
    expect(byLabel.has('u.ripples')).toBe(true);
  });

  it('follows the prelude: a renamed binding renames the completion', () => {
    const edited = completionsFromLibrary('_prelude.wgsl', prelude.replace('readTexture', 'inputTexture'));
    expect(edited.some((s) => s.label === 'inputTexture')).toBe(true);
    expect(edited.some((s) => s.label === 'readTexture')).toBe(false);
  });

  it('adds library fns and the draft params', () => {
    const libs = new Map([['_hash.wgsl', 'fn hash21(p: vec2<f32>) -> f32 {\n  return 0.0;\n}']]);
    const { params } = parseParamHeader('// @param speed 0 4 1');
    const all = new Map(buildCompletions(libs, params).map((s) => [s.label, s]));
    expect(all.get('hash21')).toMatchObject({ type: 'function', detail: '(p: vec2<f32>) -> f32', apply: 'hash21(' });
    expect(all.get('u.zoom_params.x')).toMatchObject({ detail: 'p1 · speed' });
    expect(all.has('textureSampleLevel')).toBe(true);
  });
});
