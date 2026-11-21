import { describe, expect, it } from 'vitest';
import { splitLargeGroups } from './ShaderMegaMenu';

const mk = (n: number) =>
  Array.from({ length: n }, (_, i) => ({
    id: `s${i}`, name: String.fromCharCode(65 + Math.floor(i / 10)) + i, coordinate: null, category: 'generative',
  }));

describe('splitLargeGroups', () => {
  it('leaves small groups alone', () => {
    const g = [{ key: 'artistic', label: 'Artistic', items: mk(5) }];
    expect(splitLargeGroups(g, 40)).toEqual(g);
  });
  it('splits big groups into balanced columns keeping every item', () => {
    const out = splitLargeGroups([{ key: 'generative', label: 'Generative', items: mk(100) }], 40);
    expect(out).toHaveLength(3);
    expect(out.flatMap(g => g.items)).toHaveLength(100);
    expect(new Set(out.map(g => g.key)).size).toBe(3);
    expect(out[0]?.label).toBe('Generative A–D');
  });
});
