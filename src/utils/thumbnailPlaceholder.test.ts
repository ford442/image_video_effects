import { getCategoryPlaceholderStyle, getCategoryGlyph } from './thumbnailPlaceholder';

describe('thumbnailPlaceholder', () => {
  it('returns category-specific gradient styles', () => {
    const gen = getCategoryPlaceholderStyle('generative');
    const sim = getCategoryPlaceholderStyle('simulation');
    expect(gen.background).toContain('linear-gradient');
    expect(gen.background).not.toBe(sim.background);
  });

  it('falls back to other palette for unknown categories', () => {
    const style = getCategoryPlaceholderStyle('unknown-cat');
    const other = getCategoryPlaceholderStyle('other');
    expect(style.background).toBe(other.background);
  });

  it('getCategoryGlyph returns emoji prefix', () => {
    expect(getCategoryGlyph('generative').length).toBeGreaterThan(0);
  });
});
