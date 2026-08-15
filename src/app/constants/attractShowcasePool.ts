import { ShaderEntry } from '../../renderer/types';

/** Curated generative shaders for attract-mode rotation (≥20). */
export const ATTRACT_SHOWCASE_IDS: string[] = [
  'gen-showcase-nebula-core',
  'gen-showcase-kinetic-bloom',
  'gen-showcase-crystalline-pulse',
  'stellar-plasma',
  'quantum-foam-lattice',
  'audio_geometric_pulse',
  'crystalline-veins',
  'chromatic-ghost-tunnel',
  'cosmic-web',
  'gen_kimi_crystal',
  'gen_fluffy_raincloud',
  'gen_grokcf_interference',
  'bioluminescent-bloom',
  'cosmic-jellyfish',
  'liquid_magnetic_ferro',
  'lava-lamp-blobs',
  'kimi_quantum_field',
  'kimi_fractal_dreams',
  'supernova-core',
  'molten-gold',
  'gen-ethereal-cyber-chrono-nebula-phoenix',
  'chrono-voronoi-mycelium',
  'spec-quaternion-julia',
  'bio_lenia_continuous',
];

/**
 * Multipass Physics Lab demos injected into attract rotation.
 * Longer dwell — sims need time to settle and feel alive.
 */
export const ATTRACT_PHYSICS_LAB_IDS: string[] = [
  'ripple-tank',
  'photonic-caustics-graph',
  'fabric-of-reality',
  'chromatographic-fluid',
  'gray-scott-tank',
  'optical-flow-dream',
];

/** Default attract dwell (seconds) for generative single-pass demos. */
export const ATTRACT_DEFAULT_DWELL_SEC = 12;

/** Longer dwell for Tier C multipass physics demos. */
export const ATTRACT_PHYSICS_DWELL_SEC = 22;

export interface RatedShaderRef {
  id: string;
  stars: number;
  ratingCount: number;
}

function hasFullZoomMapping(entry: ShaderEntry): boolean {
  const params = entry.params ?? [];
  if (params.length < 4) return false;
  const mappings = ['zoom_params.x', 'zoom_params.y', 'zoom_params.z', 'zoom_params.w'];
  return mappings.every((m, i) => params[i]?.mapping === m);
}

function isShowcaseTagged(entry: ShaderEntry): boolean {
  return entry.tags?.includes('showcase') === true;
}

/** Per-shader attract dwell — physics lab stacks get longer time on screen. */
export function getAttractDwellSeconds(shaderId: string, baseDelay = ATTRACT_DEFAULT_DWELL_SEC): number {
  if (ATTRACT_PHYSICS_LAB_IDS.includes(shaderId)) {
    return Math.max(baseDelay, ATTRACT_PHYSICS_DWELL_SEC);
  }
  return baseDelay;
}

/**
 * Build attract-mode rotation pool: explicit list first, then Physics Lab
 * multipass demos, then showcase-tagged, then high-rated generative shaders.
 */
export function getAttractPool(
  availableModes: ShaderEntry[],
  ratedShaders: RatedShaderRef[] = [],
): ShaderEntry[] {
  const eligible = availableModes.filter((s) => s.id !== 'none');
  const generative = eligible.filter((s) => s.category === 'generative');
  const byId = new Map(eligible.map((s) => [s.id, s]));
  const pool: ShaderEntry[] = [];
  const seen = new Set<string>();

  const add = (entry: ShaderEntry | undefined) => {
    if (!entry || seen.has(entry.id)) return;
    seen.add(entry.id);
    pool.push(entry);
  };

  for (const id of ATTRACT_SHOWCASE_IDS) {
    add(byId.get(id));
  }

  // Physics Lab flagships — early in the pool so attract hits them
  for (const id of ATTRACT_PHYSICS_LAB_IDS) {
    add(byId.get(id));
  }

  for (const entry of generative) {
    if (isShowcaseTagged(entry)) add(entry);
  }

  // Showcase-tagged simulation graphs (fabric, etc.)
  for (const entry of eligible) {
    if (entry.category === 'simulation' && isShowcaseTagged(entry)) add(entry);
  }

  const ratingMap = new Map(ratedShaders.map((r) => [r.id, r]));
  const ratedGenerative = generative
    .filter((s) => (ratingMap.get(s.id)?.stars ?? 0) >= 4)
    .sort((a, b) => (ratingMap.get(b.id)?.stars ?? 0) - (ratingMap.get(a.id)?.stars ?? 0));
  for (const entry of ratedGenerative) {
    add(entry);
  }

  for (const entry of generative) {
    if (hasFullZoomMapping(entry)) add(entry);
  }

  for (const entry of generative) {
    add(entry);
  }

  return pool;
}
