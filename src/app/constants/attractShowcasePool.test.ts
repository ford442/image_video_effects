import {
  getAttractPool,
  getAttractDwellSeconds,
  ATTRACT_SHOWCASE_IDS,
  ATTRACT_PHYSICS_LAB_IDS,
  ATTRACT_PHYSICS_DWELL_SEC,
  ATTRACT_DEFAULT_DWELL_SEC,
} from './attractShowcasePool';
import fs from 'fs';
import path from 'path';
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

  const physics: ShaderEntry[] = ATTRACT_PHYSICS_LAB_IDS.map((id) => ({
    id,
    name: id,
    url: `shaders/${id}.wgsl`,
    category: 'simulation',
    tags: ['showcase'],
    params: [
      { id: 'p1', name: 'P1', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.x' },
      { id: 'p2', name: 'P2', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.y' },
      { id: 'p3', name: 'P3', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.z' },
      { id: 'p4', name: 'P4', default: 0.5, min: 0, max: 1, mapping: 'zoom_params.w' },
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

  it('includes Physics Lab multipass demos in the pool', () => {
    const pool = getAttractPool([...generative, ...physics]);
    for (const id of ATTRACT_PHYSICS_LAB_IDS) {
      expect(pool.some((s) => s.id === id)).toBe(true);
    }
  });

  it('uses longer dwell for physics lab ids', () => {
    expect(getAttractDwellSeconds('ripple-tank')).toBe(ATTRACT_PHYSICS_DWELL_SEC);
    expect(getAttractDwellSeconds('photonic-caustics-graph')).toBe(ATTRACT_PHYSICS_DWELL_SEC);
    expect(getAttractDwellSeconds('fabric-of-reality')).toBe(ATTRACT_PHYSICS_DWELL_SEC);
    expect(getAttractDwellSeconds('chromatographic-fluid')).toBe(ATTRACT_PHYSICS_DWELL_SEC);
    expect(getAttractDwellSeconds('gray-scott-tank')).toBe(ATTRACT_PHYSICS_DWELL_SEC);
    expect(getAttractDwellSeconds('optical-flow-dream')).toBe(ATTRACT_PHYSICS_DWELL_SEC);
    expect(getAttractDwellSeconds('gen-showcase-nebula-core')).toBe(ATTRACT_DEFAULT_DWELL_SEC);
  });

  it('drops ids without a healthy thumbnail when a predicate is given', () => {
    const healthy = new Set(['gen-showcase-nebula-core', 'stellar-plasma']);
    const pool = getAttractPool(generative, [], (id) => healthy.has(id));
    expect(pool.map((s) => s.id).sort()).toEqual(['gen-showcase-nebula-core', 'stellar-plasma']);
  });

  it('keeps the full pool when no id has a thumbnail yet (manifest loading)', () => {
    expect(getAttractPool(generative, [], () => false).length).toBe(generative.length);
  });

  describe('repo thumbnail truth', () => {
    const root = path.join(__dirname, '..', '..', '..');
    const manifest = JSON.parse(fs.readFileSync(path.join(root, 'public/thumbnails/manifest.json'), 'utf8'));
    const deferred = new Set<string>(
      JSON.parse(fs.readFileSync(path.join(root, 'reports/thumbnail_deferrals.json'), 'utf8')).entries.map(
        (e: { id: string }) => e.id,
      ),
    );

    it('no attract id is deferred-as-pending', () => {
      const offenders = [...ATTRACT_SHOWCASE_IDS, ...ATTRACT_PHYSICS_LAB_IDS].filter((id) => deferred.has(id));
      expect(offenders).toEqual([]);
    });

    it('Physics Lab flagships have healthy thumbnails', () => {
      for (const id of ATTRACT_PHYSICS_LAB_IDS) {
        expect(manifest[id]?.thumbnail_url).toBeTruthy();
        expect(fs.existsSync(path.join(root, 'public/thumbnails', `${id}.png`))).toBe(true);
      }
    });
  });
});
