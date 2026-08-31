import {
  rewriteWgslStorageFormats,
  rewriteWgslStorageFormatsChecked,
} from './wgslFormatRewrite';

const SAMPLE = `
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
`;

describe('rewriteWgslStorageFormats', () => {
  it('leaves ultra tier WGSL unchanged', () => {
    expect(rewriteWgslStorageFormats(SAMPLE, 'rgba32float')).toBe(SAMPLE);
  });

  it('rewrites rgba storage bindings 2/7/8 to rgba16float', () => {
    const out = rewriteWgslStorageFormats(SAMPLE, 'rgba16float');
    expect(out).toContain('texture_storage_2d<rgba16float, write>');
    expect(out).not.toContain('rgba32float');
    expect(out).toContain('texture_storage_2d<r32float, write>');
  });

  it('rewrites authored rgba16float storage up to ultra rgba32float', () => {
    const fp16 = SAMPLE.replaceAll('rgba32float', 'rgba16float');
    const out = rewriteWgslStorageFormats(fp16, 'rgba32float');
    expect(out).toContain('texture_storage_2d<rgba32float, write>');
    expect(out).not.toContain('rgba16float');
    expect(out).toContain('texture_storage_2d<r32float, write>');
  });
});

describe('rewriteWgslStorageFormatsChecked (fail-soft)', () => {
  it('reports nothing to do on the ultra tier', () => {
    const res = rewriteWgslStorageFormatsChecked(SAMPLE, 'rgba32float');
    expect(res.wgsl).toBe(SAMPLE);
    expect(res.rewritten).toBe(0);
    expect(res.missed).toEqual([]);
  });

  it('counts rewritten declarations and reports no misses for canonical sources', () => {
    const res = rewriteWgslStorageFormatsChecked(SAMPLE, 'rgba16float');
    expect(res.rewritten).toBe(3);
    expect(res.missed).toEqual([]);
    expect(res.wgsl).toContain('texture_storage_2d<rgba16float, write>');
  });

  it('reports a declaration the rewrite could not reach', () => {
    // read_write access is outside the rewrite pattern — the pipeline would then
    // disagree with the rgba16float texture the host allocated.
    const odd = SAMPLE + '\n@group(0) @binding(9) var oddTex: texture_storage_2d<rgba32float, read_write>;\n';
    const res = rewriteWgslStorageFormatsChecked(odd, 'rgba16float');
    expect(res.missed).toHaveLength(1);
    expect(res.missed[0]).toContain('rgba32float');
    expect(res.missed[0]).toContain('read_write');
  });

  it('does not flag non-rgba storage (depth stays r32float)', () => {
    const res = rewriteWgslStorageFormatsChecked(SAMPLE, 'rgba16float');
    expect(res.missed.some((m) => m.includes('r32float'))).toBe(false);
    expect(res.wgsl).toContain('texture_storage_2d<r32float, write>');
  });
});
