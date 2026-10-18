import { loadDisplayP3, saveDisplayP3, describeDisplayP3Status, isDisplayP3UrlForced } from './displayP3';

describe('displayP3 persistence', () => {
  beforeEach(() => localStorage.clear());

  it('defaults to off', () => {
    expect(loadDisplayP3()).toBe(false);
  });

  it('round-trips', () => {
    saveDisplayP3(true);
    expect(loadDisplayP3()).toBe(true);
    saveDisplayP3(false);
    expect(loadDisplayP3()).toBe(false);
  });

  it('survives throwing storage', () => {
    const get = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('blocked'); });
    const set = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('blocked'); });
    expect(loadDisplayP3()).toBe(false);
    expect(() => saveDisplayP3(true)).not.toThrow();
    get.mockRestore();
    set.mockRestore();
  });
});



describe('displayP3 status + URL override', () => {
  it('detects the URL override', () => {
    expect(isDisplayP3UrlForced('?display_p3=1')).toBe(true);
    expect(isDisplayP3UrlForced('?display_p3=0')).toBe(false);
    expect(isDisplayP3UrlForced('')).toBe(false);
  });

  it('is silent when not requested', () => {
    expect(describeDisplayP3Status(false, undefined)).toBe('');
  });

  it('explains an sRGB fallback', () => {
    expect(describeDisplayP3Status(true, { canvasColorSpace: 'srgb', canvasColorFallback: 'unsupported-p3' }))
      .toBe('Using sRGB: this browser/display rejected Display P3');
  });

  it('reports the accepted space and tone mapping', () => {
    expect(describeDisplayP3Status(true, { canvasColorSpace: 'display-p3', canvasToneMapping: 'extended' }))
      .toBe('Applied: display-p3 / extended');
    expect(describeDisplayP3Status(true, {
      canvasColorSpace: 'display-p3', canvasToneMapping: 'standard', canvasColorFallback: 'not-hdr-display',
    })).toBe('Applied: display-p3 / standard (not an HDR display, extended tone mapping skipped)');
  });
});
