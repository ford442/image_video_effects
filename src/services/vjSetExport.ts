/**
 * vjSetExport.ts
 *
 * Portable JSON export/import for VJ sets (chain + metadata).
 * Complements localStorage `myVjSets` and URL `?chain=` sharing.
 */

import { ControlBinding } from './controlBindings';
import { SharedChain, decodeChain, encodeChain, SHARED_CHAIN_VERSION } from './layerChainShare';
import type { MyVjSet } from './myVjSets';

export const VJ_SET_EXPORT_VERSION = 1;

export interface VjSetExportPayload {
  exportVersion: number;
  name: string;
  vibePrompt?: string;
  savedAt: number;
  chain: SharedChain;
  chainString: string;
  bindings?: ControlBinding[];
}

export function buildVjSetExport(
  name: string,
  chain: SharedChain,
  options?: { vibePrompt?: string; bindings?: ControlBinding[] },
): VjSetExportPayload {
  const chainString = encodeChain(chain);
  return {
    exportVersion: VJ_SET_EXPORT_VERSION,
    name: name.trim(),
    vibePrompt: options?.vibePrompt,
    savedAt: Date.now(),
    chain,
    chainString,
    bindings: options?.bindings,
  };
}

export function serializeVjSetExport(payload: VjSetExportPayload): string {
  return JSON.stringify(payload, null, 2);
}

export function parseVjSetExport(raw: string): VjSetExportPayload | null {
  if (!raw.trim()) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<VjSetExportPayload>;
    if (!parsed || typeof parsed !== 'object') return null;

    let chain: SharedChain | null = null;
    if (parsed.chain && typeof parsed.chain === 'object') {
      chain = parsed.chain as SharedChain;
    } else if (typeof parsed.chainString === 'string') {
      chain = decodeChain(parsed.chainString);
    }
    if (!chain || chain.v !== SHARED_CHAIN_VERSION) return null;
    if (!Array.isArray(chain.slots)) return null;

    const name = typeof parsed.name === 'string' ? parsed.name.trim() : '';
    if (!name) return null;

    return {
      exportVersion: typeof parsed.exportVersion === 'number' ? parsed.exportVersion : VJ_SET_EXPORT_VERSION,
      name,
      vibePrompt: typeof parsed.vibePrompt === 'string' ? parsed.vibePrompt : undefined,
      savedAt: typeof parsed.savedAt === 'number' ? parsed.savedAt : Date.now(),
      chain,
      chainString: typeof parsed.chainString === 'string' ? parsed.chainString : encodeChain(chain),
      bindings: Array.isArray(parsed.bindings) ? parsed.bindings : undefined,
    };
  } catch {
    return null;
  }
}

/** Convert imported payload into a MyVjSet-shaped entry (caller assigns id). */
export function vjSetExportToMyVjSet(payload: VjSetExportPayload): Omit<MyVjSet, 'id'> {
  return {
    name: payload.name,
    vibePrompt: payload.vibePrompt ?? '',
    chainString: payload.chainString,
    savedAt: payload.savedAt,
  };
}
