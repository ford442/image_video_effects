// ═══════════════════════════════════════════════════════════════════════════════
//  vjToSharedChain.ts
//  Pure, defensive adapter bridging the AI VJ live stack (shader ids +
//  catalog-param-keyed values) to the shareable-chain wire format.
//
//  This does NOT introduce a second serialization format — it delegates to the
//  existing `buildSharedChain` in layerChainShare.ts, so `SHARED_CHAIN_VERSION`
//  and the wire format are untouched.
// ═══════════════════════════════════════════════════════════════════════════════

import { CatalogShader } from './shaderCatalog';
import { SlotParams } from '../renderer/types';
import { mapOrderedParamsToSlotParams } from '../utils/shaderParamMapping';
import {
  SharedChain,
  SlotParamDefaultsLookup,
  DEFAULT_SLOT_PARAMS,
  MAX_SHARED_SLOTS,
  buildSharedChain,
} from './layerChainShare';

/**
 * Translate an AI VJ live stack into a `SharedChain`.
 *
 * Behaviour (mirrors existing conventions in the codebase):
 *  - Truncates to `MAX_SHARED_SLOTS` (6) shaders if longer, warning once.
 *  - Drops shader ids not present in `knownModeIds`, warning per drop — same
 *    "skip unknown shader id" convention as `applySharedChain` in App.tsx.
 *  - Per kept shader, maps `params[i]` (keyed by `CatalogParam.id`) onto
 *    `zoomParam1-4` positionally via the shared `mapOrderedParamsToSlotParams`
 *    helper (the same logic App.tsx uses for live param updates).
 *  - Delegates compaction + encoding to `buildSharedChain`.
 *
 * @param shaderIds      Active stack ids, e.g. from `aiVj.getActiveShaderIds()`.
 * @param params         Catalog-param-keyed values, same length as `shaderIds`
 *                       (e.g. from `aiVj.getCurrentParams()`).
 * @param catalog        Shader catalog, used to resolve each shader's ordered
 *                       param ids for the positional mapping.
 * @param knownModeIds   Set of loadable shader ids; unknown ids are dropped.
 * @param defaultsLookup Optional per-shader defaults for default-value
 *                       compaction (shorter URLs). When omitted, the generic
 *                       `DEFAULT_SLOT_PARAMS` are used — this is what the app's
 *                       decode path (`expandSharedChain` without a lookup) also
 *                       uses, guaranteeing a faithful round-trip. Only pass a
 *                       lookup if the decode side uses the same one.
 */
export function mapVJStackToSharedChain(
  shaderIds: string[],
  params: Record<string, number>[],
  catalog: CatalogShader[],
  knownModeIds: Set<string>,
  defaultsLookup?: SlotParamDefaultsLookup,
): SharedChain {
  // 1. Truncate to the wire-format's max slot count.
  let ids = shaderIds;
  let stackParams = params;
  if (ids.length > MAX_SHARED_SLOTS) {
    console.warn(
      `[vjToSharedChain] VJ stack has ${ids.length} shaders; truncating to MAX_SHARED_SLOTS (${MAX_SHARED_SLOTS})`,
    );
    ids = ids.slice(0, MAX_SHARED_SLOTS);
    stackParams = stackParams.slice(0, MAX_SHARED_SLOTS);
  }

  const catalogById = new Map(catalog.map(s => [s.id, s]));

  const modes: Array<string | null> = [];
  const slotParams: SlotParams[] = [];

  ids.forEach((shaderId, i) => {
    // 2. Drop unknown ids (matches applySharedChain's skip+warn convention).
    if (!knownModeIds.has(shaderId)) {
      console.warn(`[vjToSharedChain] skipping unknown shader id "${shaderId}"`);
      return;
    }

    // 3. Positional catalog-param → SlotParams mapping (shared helper).
    const orderedParamIds = (catalogById.get(shaderId)?.params ?? []).map(p => p.id);
    const partial = mapOrderedParamsToSlotParams(stackParams[i] ?? {}, orderedParamIds);

    // Expand to a full SlotParams so buildSharedChain can compact against
    // defaults. Generic defaults are used here as the base; any per-shader
    // defaults provided via `defaultsLookup` are applied by buildSharedChain
    // during compaction.
    modes.push(shaderId);
    slotParams.push({ ...DEFAULT_SLOT_PARAMS, ...partial });
  });

  // 4. Delegate to the existing builder — no wire-format change.
  return buildSharedChain(modes, slotParams, defaultsLookup ? { defaultsLookup } : undefined);
}

/**
 * Build a per-shader `SlotParamDefaultsLookup` from the catalog: a shader's
 * 1st-4th `CatalogParam.default` map to `zoomParam1-4`.
 *
 * NOTE: only pass the result to `mapVJStackToSharedChain` if the decode side
 * expands with the same lookup. The app's load-time decode path
 * (`applySharedChain` → `expandSharedChain` without a lookup) does NOT, so the
 * app integration intentionally omits this for round-trip fidelity. Exposed
 * mainly for compaction tests and future symmetric decode paths.
 */
export function buildCatalogDefaultsLookup(catalog: CatalogShader[]): SlotParamDefaultsLookup {
  const byId = new Map(catalog.map(s => [s.id, s]));
  return (shaderId: string) => {
    const shader = byId.get(shaderId);
    if (!shader) return undefined;
    const defaults: Partial<SlotParams> = {};
    shader.params.forEach((p, i) => {
      if (i === 0) defaults.zoomParam1 = p.default;
      else if (i === 1) defaults.zoomParam2 = p.default;
      else if (i === 2) defaults.zoomParam3 = p.default;
      else if (i === 3) defaults.zoomParam4 = p.default;
    });
    return defaults;
  };
}
