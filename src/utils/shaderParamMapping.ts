// ═══════════════════════════════════════════════════════════════════════════════
//  shaderParamMapping.ts
//  Shared, React-free translation of a shader's param-id-keyed values into the
//  positional zoomParam1-4 fields of SlotParams.
//
//  Both App.tsx's `mapShaderParamUpdates` and the VJ→shared-chain adapter
//  (`vjToSharedChain.ts`) use this single implementation, so the catalog-param →
//  SlotParams mapping is defined in exactly one place.
// ═══════════════════════════════════════════════════════════════════════════════

import { SlotParams } from '../renderer/types';

/**
 * Map a shader's param-id-keyed updates onto the positional `zoomParam1-4`
 * fields of `SlotParams`, using the shader's ordered list of param ids.
 *
 * A shader's 1st/2nd/3rd/4th param maps to `zoomParam1`/`2`/`3`/`4`
 * respectively. `SlotParams` has no 5th+ zoom slot, so any param beyond the
 * first four is intentionally ignored. Keys not present in `orderedParamIds`
 * are skipped.
 *
 * @param paramUpdates    Record keyed by shader-specific param id → value.
 * @param orderedParamIds The shader's param ids, in declaration order.
 */
export function mapOrderedParamsToSlotParams(
  paramUpdates: Record<string, number>,
  orderedParamIds: string[],
): Partial<SlotParams> {
  const updates: Partial<SlotParams> = {};
  for (const [key, value] of Object.entries(paramUpdates)) {
    const paramIndex = orderedParamIds.indexOf(key);
    if (paramIndex === 0) updates.zoomParam1 = value;
    else if (paramIndex === 1) updates.zoomParam2 = value;
    else if (paramIndex === 2) updates.zoomParam3 = value;
    else if (paramIndex === 3) updates.zoomParam4 = value;
  }
  return updates;
}
