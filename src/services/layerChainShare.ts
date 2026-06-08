/**
 * layerChainShare.ts
 *
 * Versioned, URL-safe serialization of a multi-slot shader chain so it can be
 * shared as a compact link or stored in a curated preset pack.
 */

import { SlotParams, SlotMode } from '../renderer/types';

export const SHARED_CHAIN_VERSION = 1;
export const MAX_SHARED_SLOTS = 6;

/** Generic per-slot defaults — matches App.tsx's `defaultSlotParams`. */
export const DEFAULT_SLOT_PARAMS: SlotParams = {
    zoomParam1: 0.99,
    zoomParam2: 1.01,
    zoomParam3: 0.5,
    zoomParam4: 0.5,
    lightStrength: 1.0,
    ambient: 0.2,
    normalStrength: 0.1,
    fogFalloff: 4.0,
    depthThreshold: 0.5,
};

export interface SharedChainSlot {
    /** Shader id, or null for an empty/disabled slot. */
    shaderId: string | null;
    /** Only the params that differ from the default — re-expanded on decode. */
    params?: Partial<SlotParams>;
    enabled?: boolean;
    mode?: SlotMode;
}

export interface SharedChain {
    /** Schema version — bump whenever the wire format changes. */
    v: number;
    slots: SharedChainSlot[];
}

/** Looks up a per-shader default for compaction/expansion. Falls back to the generic defaults. */
export type SlotParamDefaultsLookup = (shaderId: string) => Partial<SlotParams> | undefined;

function getDefaultsFor(shaderId: string | null, lookup?: SlotParamDefaultsLookup): SlotParams {
    const fromCatalog = shaderId ? lookup?.(shaderId) : undefined;
    return fromCatalog ? { ...DEFAULT_SLOT_PARAMS, ...fromCatalog } : DEFAULT_SLOT_PARAMS;
}

function compactParams(params: SlotParams, defaults: SlotParams): Partial<SlotParams> | undefined {
    const compact: Partial<SlotParams> = {};
    let hasAny = false;
    for (const key of Object.keys(params) as Array<keyof SlotParams>) {
        if (params[key] !== defaults[key]) {
            compact[key] = params[key];
            hasAny = true;
        }
    }
    return hasAny ? compact : undefined;
}

function expandParams(partial: Partial<SlotParams> | undefined, defaults: SlotParams): SlotParams {
    return { ...defaults, ...(partial ?? {}) };
}

/** Builds a SharedChain from the live App state, dropping default-valued params. */
export function buildSharedChain(
    modes: Array<string | null>,
    slotParams: SlotParams[],
    options?: {
        enabled?: boolean[];
        slotModes?: SlotMode[];
        defaultsLookup?: SlotParamDefaultsLookup;
    }
): SharedChain {
    const count = Math.min(modes.length, MAX_SHARED_SLOTS);
    const slots: SharedChainSlot[] = [];

    for (let i = 0; i < count; i++) {
        const rawId = modes[i];
        const shaderId = !rawId || rawId === 'none' ? null : rawId;
        const defaults = getDefaultsFor(shaderId, options?.defaultsLookup);
        const params = shaderId && slotParams[i] ? compactParams(slotParams[i], defaults) : undefined;

        const slot: SharedChainSlot = { shaderId };
        if (params) slot.params = params;
        if (options?.enabled && options.enabled[i] === false) slot.enabled = false;
        if (options?.slotModes && options.slotModes[i] && options.slotModes[i] !== 'chained') {
            slot.mode = options.slotModes[i];
        }
        slots.push(slot);
    }

    return { v: SHARED_CHAIN_VERSION, slots };
}

/** Re-expands a decoded SharedChain back into App-shaped state arrays. */
export function expandSharedChain(
    chain: SharedChain,
    defaultsLookup?: SlotParamDefaultsLookup
): { modes: Array<string | null>; slotParams: SlotParams[]; enabled: boolean[]; slotModes: SlotMode[] } {
    const modes: Array<string | null> = [];
    const slotParams: SlotParams[] = [];
    const enabled: boolean[] = [];
    const slotModes: SlotMode[] = [];

    for (const slot of chain.slots.slice(0, MAX_SHARED_SLOTS)) {
        const defaults = getDefaultsFor(slot.shaderId, defaultsLookup);
        modes.push(slot.shaderId ?? null);
        slotParams.push(expandParams(slot.params, defaults));
        enabled.push(slot.enabled !== false);
        slotModes.push(slot.mode === 'parallel' ? 'parallel' : 'chained');
    }

    return { modes, slotParams, enabled, slotModes };
}

// ─── Wire encoding (base64url of minified JSON) ───────────────────────────────

// btoa/atob only handle Latin1, so route the JSON through encodeURIComponent's
// percent-escapes to safely carry arbitrary unicode (shader names, emoji, etc).
function utf8ToBinary(str: string): string {
    return unescape(encodeURIComponent(str));
}

function binaryToUtf8(binary: string): string {
    return decodeURIComponent(escape(binary));
}

function base64UrlEncode(json: string): string {
    return btoa(utf8ToBinary(json)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(str: string): string | null {
    try {
        const padded = str.replace(/-/g, '+').replace(/_/g, '/');
        const pad = padded.length % 4 === 0 ? '' : '='.repeat(4 - (padded.length % 4));
        return binaryToUtf8(atob(padded + pad));
    } catch {
        return null;
    }
}

/** Encodes a chain into a compact, URL-safe string. Clamps to MAX_SHARED_SLOTS. */
export function encodeChain(chain: SharedChain): string {
    const clamped: SharedChain = {
        v: chain.v,
        slots: chain.slots.slice(0, MAX_SHARED_SLOTS),
    };
    return base64UrlEncode(JSON.stringify(clamped));
}

function isSlotMode(value: unknown): value is SlotMode {
    return value === 'chained' || value === 'parallel';
}

function isSharedChainSlot(value: unknown): value is SharedChainSlot {
    if (!value || typeof value !== 'object') return false;
    const slot = value as Record<string, unknown>;
    if (slot.shaderId !== null && typeof slot.shaderId !== 'string') return false;
    if (slot.params !== undefined && (typeof slot.params !== 'object' || slot.params === null)) return false;
    if (slot.enabled !== undefined && typeof slot.enabled !== 'boolean') return false;
    if (slot.mode !== undefined && !isSlotMode(slot.mode)) return false;
    return true;
}

/** Migrates an older-version payload to the current schema. Returns null if unrecognized. */
function migrate(raw: any): SharedChain | null {
    if (!raw || typeof raw !== 'object' || typeof raw.v !== 'number' || !Array.isArray(raw.slots)) {
        return null;
    }

    // v1 is the current format — add future migration steps above this line,
    // each one normalizing `raw` toward the latest shape before falling through.
    if (raw.v !== SHARED_CHAIN_VERSION) {
        return null;
    }

    const slots = raw.slots.filter(isSharedChainSlot) as SharedChainSlot[];
    if (slots.length !== raw.slots.length) {
        console.warn('[layerChainShare] dropped malformed slot entries during decode');
    }

    return { v: SHARED_CHAIN_VERSION, slots: slots.slice(0, MAX_SHARED_SLOTS) };
}

/** Decodes a shared-chain string. Never throws — returns null and logs a warning on bad input. */
export function decodeChain(str: string): SharedChain | null {
    if (!str) return null;

    const json = base64UrlDecode(str);
    if (json === null) {
        console.warn('[layerChainShare] failed to base64url-decode shared chain string');
        return null;
    }

    let raw: any;
    try {
        raw = JSON.parse(json);
    } catch {
        console.warn('[layerChainShare] failed to parse shared chain JSON');
        return null;
    }

    const migrated = migrate(raw);
    if (!migrated) {
        console.warn('[layerChainShare] shared chain payload has an unrecognized shape or version');
        return null;
    }

    return migrated;
}
