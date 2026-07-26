import { rewriteWgslStorageFormats } from './wgslFormatRewrite';

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
});
