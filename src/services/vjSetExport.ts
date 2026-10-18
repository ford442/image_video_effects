/**
 * vjSetExport.ts
 *
 * Portable JSON export/import for VJ sets (chain + metadata).
 * Complements localStorage `myVjSets` and URL `?chain=` sharing.
 */

import { ControlBinding, sanitizeBindings } from './controlBindings';
import { SharedChain, decodeChain, encodeChain, SHARED_CHAIN_VERSION } from './layerChainShare';
import type { MyVjSet } from './myVjSets';

export const VJ_SET_EXPORT_VERSION = 1;

/**
 * Recorded performance (set recorder). Additive optional field on the v1 file —
 * older parsers drop it, so exportVersion stays 1. Events are what was on
 * screen: slot shader swaps + slider values, sampled at `hz` and diffed.
 */
export type VjTimelineEvent =
  | { t: number; slot: number; kind: 'shader'; value: string }
  | { t: number; slot: number; kind: 'param'; key: TimelineParamKey; value: number };

export type TimelineParamKey = 'zoomParam1' | 'zoomParam2' | 'zoomParam3' | 'zoomParam4';

export interface VjTimeline {
  hz: number;
  durationMs: number;
  events: VjTimelineEvent[];
}

export const MAX_TIMELINE_EVENTS = 200_000;
const MAX_TIMELINE_SLOT = 5;
const MAX_SHADER_ID_LENGTH = 128;
const TIMELINE_PARAM_KEYS = new Set<string>(['zoomParam1', 'zoomParam2', 'zoomParam3', 'zoomParam4']);

/** Drop malformed events, enforce monotonic time, cap size. Null if unusable. */
export function sanitizeTimeline(raw: unknown): VjTimeline | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Partial<VjTimeline>;
  if (!Array.isArray(r.events)) return null;
  const hz = typeof r.hz === 'number' && r.hz > 0 && r.hz <= 120 ? r.hz : 20;
  const events: VjTimelineEvent[] = [];
  let lastT = 0;
  for (const e of r.events as unknown[]) {
    if (events.length >= MAX_TIMELINE_EVENTS) break;
    if (!e || typeof e !== 'object') continue;
    const ev = e as Record<string, unknown>;
    const t = Number(ev.t);
    const slot = Number(ev.slot);
    if (!Number.isFinite(t) || t < lastT) continue;
    if (!Number.isInteger(slot) || slot < 0 || slot > MAX_TIMELINE_SLOT) continue;
    if (ev.kind === 'shader' && typeof ev.value === 'string' && ev.value.length > 0 && ev.value.length <= MAX_SHADER_ID_LENGTH) {
      events.push({ t, slot, kind: 'shader', value: ev.value });
    } else if (ev.kind === 'param' && typeof ev.key === 'string' && TIMELINE_PARAM_KEYS.has(ev.key)
      && typeof ev.value === 'number' && Number.isFinite(ev.value)) {
      events.push({ t, slot, kind: 'param', key: ev.key as TimelineParamKey, value: ev.value });
    } else {
      continue;
    }
    lastT = t;
  }
  if (events.length === 0) return null;
  const durationMs = typeof r.durationMs === 'number' && Number.isFinite(r.durationMs)
    ? Math.max(r.durationMs, lastT)
    : lastT;
  return { hz, durationMs, events };
}

export interface VjSetExportPayload {
  exportVersion: number;
  name: string;
  vibePrompt?: string;
  savedAt: number;
  chain: SharedChain;
  chainString: string;
  bindings?: ControlBinding[];
  timeline?: VjTimeline;
}

export function buildVjSetExport(
  name: string,
  chain: SharedChain,
  options?: { vibePrompt?: string; bindings?: ControlBinding[]; timeline?: VjTimeline },
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
    ...(options?.timeline ? { timeline: options.timeline } : {}),
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
      bindings: Array.isArray(parsed.bindings)
        ? sanitizeBindings(parsed.bindings)
        : undefined,
      ...(() => {
        const timeline = sanitizeTimeline(parsed.timeline);
        return timeline ? { timeline } : {};
      })(),
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
