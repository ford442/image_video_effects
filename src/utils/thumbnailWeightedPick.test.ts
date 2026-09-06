import { pickWeighted, pickWeightedShader, pickWeightedShaderId, THUMBNAIL_PICK_WEIGHT } from './thumbnailWeightedPick';

describe('thumbnailWeightedPick', () => {
  const hasThumb = (id: string) => id === 'a';

  it('pickWeightedShaderId returns null for empty list', () => {
    expect(pickWeightedShaderId([], hasThumb)).toBeNull();
  });

  it('unhealthy ids should not receive the thumbnail weight', () => {
    const hasHealthy = (id: string) => id === 'a';
    const counts = { a: 0, b: 0 };
    for (let i = 0; i < 400; i++) {
      const id = pickWeightedShaderId(['a', 'b'], hasHealthy, 3);
      if (id === 'a') counts.a++;
      else counts.b++;
    }
    expect(counts.a).toBeGreaterThan(counts.b);
  });

  it('pickWeightedShader prefers thumbed ids over time', () => {
    const counts = { a: 0, b: 0 };
    for (let i = 0; i < 400; i++) {
      const id = pickWeightedShaderId(['a', 'b'], hasThumb, 3);
      if (id === 'a') counts.a++;
      else counts.b++;
    }
    expect(counts.a).toBeGreaterThan(counts.b);
  });

  it('pickWeightedShader works on object lists', () => {
    const items = [{ id: 'a' }, { id: 'b' }];
    let aCount = 0;
    for (let i = 0; i < 200; i++) {
      const picked = pickWeightedShader(items, hasThumb);
      if (picked?.id === 'a') aCount++;
    }
    expect(aCount).toBeGreaterThan(100);
  });

  it('pickWeighted falls back to uniform when all weights are zero', () => {
    const item = pickWeighted(['x', 'y'], () => 0);
    expect(item === 'x' || item === 'y').toBe(true);
  });

  it('exports default thumb weight', () => {
    expect(THUMBNAIL_PICK_WEIGHT).toBe(3);
  });
});
