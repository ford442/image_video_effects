import { rewriteWgslStorageFormats } from './wgslFormat';

const SAMPLE = `
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
`;

describe('wasm rewriteWgslStorageFormats', () => {
  it('leaves canonical rgba32float when colorFormat is 0', () => {
    expect(rewriteWgslStorageFormats(SAMPLE, 0)).toBe(SAMPLE);
  });

  it('rewrites rgba32float storage to rgba16float when colorFormat is 1', () => {
    const out = rewriteWgslStorageFormats(SAMPLE, 1);
    expect(out).toContain('texture_storage_2d<rgba16float, write>');
    expect(out).not.toContain('rgba32float');
    expect(out).toContain('r32float');
  });

  it('rewrites authored rgba16float up to rgba32float when colorFormat is 0', () => {
    const fp16 = SAMPLE.replaceAll('rgba32float', 'rgba16float');
    const out = rewriteWgslStorageFormats(fp16, 0);
    expect(out).toContain('texture_storage_2d<rgba32float, write>');
    expect(out).not.toContain('rgba16float');
  });
});
