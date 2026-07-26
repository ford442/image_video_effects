import { getAttractPool, ATTRACT_SHOWCASE_IDS } from './attractShowcasePool';
import { ShaderEntry } from '../../renderer/types';

describe('attractShowcasePool', () => {
  const generative: ShaderEntry[] = ATTRACT_SHOWCASE_IDS.map((id) => ({
    id,
    name: id,
    url: `shaders/${id}.wgsl`,
    category: 'generative',
    params: [
      { id: 'p1', name: 'P1', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.x', audio: 'bass' },
      { id: 'p2', name: 'P2', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.y', audio: 'mid' },
      { id: 'p3', name: 'P3', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.z', audio: 'treble' },
      { id: 'p4', name: 'P4', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.w', audio: 'overall' },
    ],
  }));

  it('returns at least 20 shaders from explicit pool', () => {
    const pool = getAttractPool(generative);
    expect(pool.length).toBeGreaterThanOrEqual(20);
  });

  it('prioritizes explicit showcase ids', () => {
    const pool = getAttractPool(generative);
    expect(pool[0]?.id).toBe('gen-showcase-nebula-core');
  });
});
