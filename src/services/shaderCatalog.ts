// ═══════════════════════════════════════════════════════════════════════════════
//  shaderCatalog.ts
//  Canonical shader metadata service — single source of truth for the app.
// ═══════════════════════════════════════════════════════════════════════════════

export interface CatalogParam {
  id: string;
  name: string;
  default: number;
  min: number;
  max: number;
  step?: number;
  mapping?: string;
  description?: string;
}

export interface CatalogShader {
  id: string;
  name: string;
  category: string;
  tags: string[];
  description: string;
  params: CatalogParam[];
  searchText: string;
}

// ─── Module-level cache ───
let catalogCache: CatalogShader[] | null = null;

const CATEGORY_FILES = [
  'advanced-hybrid.json',
  'artistic.json',
  'distortion.json',
  'generative.json',
  'geometric.json',
  'image.json',
  'interactive-mouse.json',
  'interactive.json',
  'lighting-effects.json',
  'liquid-effects.json',
  'liquid.json',
  'post-processing.json',
  'retro-glitch.json',
  'simulation.json',
  'visual-effects.json',
];

interface ExtractedParam {
  id: string;
  name: string;
  default: number;
  min: number;
  max: number;
  step?: number;
  mapping?: string;
  description?: string;
}

interface ExtractedEntry {
  category: string;
  params: ExtractedParam[];
}

/**
 * Build the canonical shader catalog by merging category JSONs with
 * richer param metadata from shader_params_extracted.json.
 * Results are cached for the lifetime of the module.
 */
export async function buildCatalog(): Promise<CatalogShader[]> {
  if (catalogCache) {
    return catalogCache;
  }

  // Fetch all category JSONs in parallel
  const categoryResponses = await Promise.all(
    CATEGORY_FILES.map(f => fetch(`./shader-lists/${f}`).catch(() => null))
  );

  const categoryArrays = await Promise.all(
    categoryResponses.map(async (res, idx) => {
      if (!res || !res.ok) {
        console.warn(`[shaderCatalog] Failed to load ${CATEGORY_FILES[idx]}`);
        return [];
      }
      try {
        return await res.json();
      } catch {
        console.warn(`[shaderCatalog] Invalid JSON in ${CATEGORY_FILES[idx]}`);
        return [];
      }
    })
  );

  // Fetch extracted param metadata
  let extractedMap: Record<string, ExtractedEntry> = {};
  try {
    const extractedRes = await fetch('./reports/shader_params_extracted.json');
    if (extractedRes.ok) {
      extractedMap = await extractedRes.json();
    } else {
      console.warn('[shaderCatalog] Failed to load shader_params_extracted.json');
    }
  } catch {
    console.warn('[shaderCatalog] Error loading shader_params_extracted.json');
  }

  const byId = new Map<string, CatalogShader>();

  for (const arr of categoryArrays) {
    if (!Array.isArray(arr)) continue;
    for (const def of arr) {
      if (!def || !def.id) continue;

      const baseParams: CatalogParam[] = (def.params || []).map((p: any) => ({
        id: p.id || '',
        name: p.name || '',
        default: p.default ?? 0.5,
        min: p.min ?? 0,
        max: p.max ?? 1,
        step: p.step,
        mapping: p.mapping,
        description: p.description,
      }));

      const extracted = extractedMap[def.id];
      let mergedParams = baseParams;

      if (extracted && Array.isArray(extracted.params)) {
        const extractedById = new Map<string, ExtractedParam>();
        for (const ep of extracted.params) {
          extractedById.set(ep.id, ep);
        }

        mergedParams = baseParams.map(bp => {
          const ep = extractedById.get(bp.id);
          if (ep) {
            return {
              ...bp,
              step: ep.step ?? bp.step,
              mapping: ep.mapping ?? bp.mapping,
              description: ep.description ?? bp.description,
            };
          }
          return bp;
        });

        // Append any params present in extracted but missing from base
        const baseIds = new Set(baseParams.map(p => p.id));
        for (const ep of extracted.params) {
          if (!baseIds.has(ep.id)) {
            mergedParams.push({
              id: ep.id,
              name: ep.name,
              default: ep.default,
              min: ep.min,
              max: ep.max,
              step: ep.step,
              mapping: ep.mapping,
              description: ep.description,
            });
          }
        }
      }

      const tags: string[] = Array.isArray(def.tags) ? def.tags : [];
      const description: string = def.description || '';

      const searchText = [
        def.id,
        def.name || def.id,
        ...tags,
        description,
      ]
        .join(' ')
        .toLowerCase();

      byId.set(def.id, {
        id: def.id,
        name: def.name || def.id,
        category: def.category || 'image',
        tags,
        description,
        params: mergedParams,
        searchText,
      });
    }
  }

  const deduped = Array.from(byId.values());

  console.log(`[shaderCatalog] Built catalog: ${deduped.length} shaders`);
  catalogCache = deduped;
  return deduped;
}

/**
 * Token-based AND search over a pre-built catalog.
 * Returns the full catalog if query is empty/blank.
 */
export function searchCatalog(
  catalog: CatalogShader[],
  query: string
): CatalogShader[] {
  const trimmed = query.trim();
  if (!trimmed) {
    return catalog;
  }

  const tokens = trimmed.toLowerCase().split(/\s+/).filter(Boolean);
  if (tokens.length === 0) {
    return catalog;
  }

  return catalog.filter(shader =>
    tokens.every(token => shader.searchText.includes(token))
  );
}
