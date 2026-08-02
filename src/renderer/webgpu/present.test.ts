import {
  needsBlitBindGroupRefresh,
  selectPresentPipeline,
} from './present';

describe('present helpers', () => {
  it('keeps a blit bind group only while texture identity and dimensions match', () => {
    expect(needsBlitBindGroupRefresh({
      hasBindGroup: true,
      readTextureMatches: true,
      scaledWidthMatches: true,
      scaledHeightMatches: true,
    })).toBe(false);

    expect(needsBlitBindGroupRefresh({
      hasBindGroup: true,
      readTextureMatches: false,
      scaledWidthMatches: true,
      scaledHeightMatches: true,
    })).toBe(true);
  });

  it('selects the orientation-preserving pipeline only for generative input', () => {
    const standard = { id: 'standard' };
    const generative = { id: 'generative' };

    expect(selectPresentPipeline('image', standard, generative)).toBe(standard);
    expect(selectPresentPipeline('generative', standard, generative)).toBe(generative);
  });
});
