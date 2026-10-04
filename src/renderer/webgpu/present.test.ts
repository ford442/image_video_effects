import {
  needsBlitBindGroupRefresh,
  needsScaledInputCopy,
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

  it('resamples the input whenever readTex is smaller than the canvas, not only below scale 1', () => {
    const full = { resolutionScale: 1, canvasW: 2048, canvasH: 2048, scaledW: 2048, scaledH: 2048 };
    expect(needsScaledInputCopy(full)).toBe(false);
    // Non-discrete adapters cap the working size at 1024 while the canvas stays 2048.
    expect(needsScaledInputCopy({ ...full, scaledW: 1024, scaledH: 1024 })).toBe(true);
    expect(needsScaledInputCopy({ ...full, resolutionScale: 0.5, scaledW: 1024, scaledH: 1024 })).toBe(true);
    // Workgroup round-up can make readTex larger than the canvas: a plain copy still fits.
    expect(needsScaledInputCopy({ ...full, canvasW: 1000, canvasH: 1000, scaledW: 1008, scaledH: 1008 })).toBe(false);
  });
});
