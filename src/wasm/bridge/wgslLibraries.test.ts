import * as fs from 'fs';
import * as path from 'path';
import { expandWgslIncludes } from './wgslInclude';
import { BUNDLED_WGSL_LIBRARIES, withBundledLibraries } from './wgslLibraries';

const PRELUDE = fs.readFileSync(path.join(__dirname, '../../../public/shaders/_prelude.wgsl'), 'utf8');

describe('bundled WGSL libraries', () => {
  it('carries the committed _prelude.wgsl byte for byte', () => {
    expect(BUNDLED_WGSL_LIBRARIES['_prelude.wgsl']).toBe(PRELUDE);
  });

  it('bundles only the prelude', () => {
    expect(Object.keys(BUNDLED_WGSL_LIBRARIES)).toEqual(['_prelude.wgsl']);
  });

  it('serves the prelude without calling the fallback', async () => {
    const fallback = jest.fn(async () => 'from network');
    await expect(withBundledLibraries(fallback)('_prelude.wgsl')).resolves.toBe(PRELUDE);
    expect(fallback).not.toHaveBeenCalled();
  });

  it('defers every other library to the fallback', async () => {
    const fallback = jest.fn(async (name: string) => (name === '_hash.wgsl' ? 'fn hash() {}' : null));
    const resolve = withBundledLibraries(fallback);
    await expect(resolve('_hash.wgsl')).resolves.toBe('fn hash() {}');
    await expect(resolve('_missing.wgsl')).resolves.toBeNull();
    await expect(resolve('constructor')).resolves.toBeNull();
    expect(fallback).toHaveBeenCalledTimes(3);
  });

  it('expands a prelude include with no network at all', async () => {
    const offline = jest.fn(async () => null);
    const out = await expandWgslIncludes(
      '#include "_prelude.wgsl"\n@compute @workgroup_size(16, 16, 1) fn main() {}',
      withBundledLibraries(offline),
      'zz.wgsl',
    );
    expect(out).toContain('@group(0) @binding(3) var<uniform> u: Uniforms;');
    expect(out).toContain('@compute @workgroup_size(16, 16, 1) fn main() {}');
    expect(offline).not.toHaveBeenCalled();
  });
});
