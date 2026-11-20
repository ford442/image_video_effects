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
 * screen: slot shader swaps, slider values (sampled at `hz` and diffed) and source
 * changes, so a set is self-describing for offline export (#1401). Older parsers keep
 * the shader and zoomParam events and drop the rest.
 */
export type VjTimelineEvent =
  | { t: number; slot: number; kind: 'shader'; value: string }
  | { t: number; slot: number; kind: 'param'; key: TimelineParamKey; value: number }
  /** The input source changed (slot is always 0). */
  | { t: number; slot: number; kind: 'source'; value: TimelineSource };

/** Every SlotParams field. The four zoomParams reach WGSL; the rest are page-side lighting / depth. */
export type TimelineParamKey =
  | 'zoomParam1'
  | 'zoomParam2'
  | 'zoomParam3'
  | 'zoomParam4'
  | 'lightStrength'
  | 'ambient'
  | 'normalStrength'
  | 'fogFalloff'
  | 'depthThreshold';

export const TIMELINE_PARAM_KEYS: readonly TimelineParamKey[] = [
  'zoomParam1', 'zoomParam2', 'zoomParam3', 'zoomParam4',
  'lightStrength', 'ambient', 'normalStrength', 'fogFalloff', 'depthThreshold',
];

/** The params the renderer consumes per slot (zoom_params.xyzw), in order. */
export const GPU_PARAM_KEYS: readonly TimelineParamKey[] = ['zoomParam1', 'zoomParam2', 'zoomParam3', 'zoomParam4'];

export type TimelineSourceType = 'image' | 'video' | 'webcam' | 'generative' | 'live';

/**
 * What the shaders read from at a point of the set. `url` is a reference (http(s) or
 * same-origin path), never media bytes: data:/blob: URLs are dropped. `seekSec` is the
 * video position when the event fired; playback continues at 1× from there.
 */
export interface TimelineSource {
  type: TimelineSourceType;
  url?: string;
  seekSec?: number;
  /** Generative source: the generative shader id. */
  shader?: string;
}

/** How a keyframe is approached from the one before it. */
export type KeyframeEase = 'linear' | 'step' | 'easeIn' | 'easeOut' | 'easeInOut';
export const KEYFRAME_EASES: readonly KeyframeEase[] = ['linear', 'step', 'easeIn', 'easeOut', 'easeInOut'];

/**
 * A hand-placed value for one slot param (#1401). From the first keyframe of a
 * (slot, key) on, its keyframe curve wins over the recorded value; `ease` shapes the
 * segment that ends at this keyframe. Additive like `timeline` itself.
 */
export interface TimelineKeyframe {
  t: number;
  slot: number;
  key: TimelineParamKey;
  value: number;
  ease: KeyframeEase;
}

export interface VjTimeline {
  hz: number;
  durationMs: number;
  events: VjTimelineEvent[];
  keyframes?: TimelineKeyframe[];
}

export const MAX_TIMELINE_EVENTS = 200_000;
export const MAX_TIMELINE_KEYFRAMES = 10_000;
const MAX_TIMELINE_SLOT = 5;
const MAX_SHADER_ID_LENGTH = 128;
const MAX_SOURCE_URL_LENGTH = 2048;
const TIMELINE_PARAM_KEY_SET = new Set<string>(TIMELINE_PARAM_KEYS);
const SOURCE_TYPES = new Set<string>(['image', 'video', 'webcam', 'generative', 'live']);
const EASE_SET = new Set<string>(KEYFRAME_EASES);

export function isTimelineParamKey(key: unknown): key is TimelineParamKey {
  return typeof key === 'string' && TIMELINE_PARAM_KEY_SET.has(key);
}

/** A media reference that may be saved: not inline bytes, not a page-local object URL. */
export function isPortableMediaUrl(url: unknown): url is string {
  if (typeof url !== 'string' || !url || url.length > MAX_SOURCE_URL_LENGTH) return false;
  return !/^\s*(data|blob|javascript|file):/i.test(url);
}

/** Null when unusable; drops fields that must not be saved (data:/blob: URLs). */
export function sanitizeTimelineSource(raw: unknown): TimelineSource | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.type !== 'string' || !SOURCE_TYPES.has(r.type)) return null;
  const source: TimelineSource = { type: r.type as TimelineSourceType };
  if (isPortableMediaUrl(r.url)) source.url = r.url;
  if (typeof r.seekSec === 'number' && Number.isFinite(r.seekSec) && r.seekSec >= 0) source.seekSec = r.seekSec;
  if (typeof r.shader === 'string' && r.shader.length > 0 && r.shader.length <= MAX_SHADER_ID_LENGTH) source.shader = r.shader;
  return source;
}

/** Keyframes sorted by time (stable), malformed ones dropped, capped. */
export function sanitizeKeyframes(raw: unknown): TimelineKeyframe[] {
  if (!Array.isArray(raw)) return [];
  const out: TimelineKeyframe[] = [];
  for (const k of raw as unknown[]) {
    if (out.length >= MAX_TIMELINE_KEYFRAMES) break;
    if (!k || typeof k !== 'object') continue;
    const kf = k as Record<string, unknown>;
    const t = Number(kf.t);
    const slot = Number(kf.slot);
    if (!Number.isFinite(t) || t < 0) continue;
    if (!Number.isInteger(slot) || slot < 0 || slot > MAX_TIMELINE_SLOT) continue;
    if (!isTimelineParamKey(kf.key) || typeof kf.value !== 'number' || !Number.isFinite(kf.value)) continue;
    const ease = typeof kf.ease === 'string' && EASE_SET.has(kf.ease) ? (kf.ease as KeyframeEase) : 'linear';
    out.push({ t, slot, key: kf.key, value: kf.value, ease });
  }
  return out
    .map((k, i) => ({ k, i }))
    .sort((a, b) => a.k.t - b.k.t || a.i - b.i)
    .map(({ k }) => k);
}

/** Drop malformed events, enforce monotonic time, cap size. Null if unusable. */
export function sanitizeTimeline(raw: unknown): VjTimeline | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Partial<VjTimeline>;
  const keyframes = sanitizeKeyframes(r.keyframes);
  if (!Array.isArray(r.events) && keyframes.length === 0) return null;
  const hz = typeof r.hz === 'number' && r.hz > 0 && r.hz <= 120 ? r.hz : 20;
  const events: VjTimelineEvent[] = [];
  let lastT = 0;
  for (const e of (Array.isArray(r.events) ? r.events : []) as unknown[]) {
    if (events.length >= MAX_TIMELINE_EVENTS) break;
    if (!e || typeof e !== 'object') continue;
    const ev = e as Record<string, unknown>;
    const t = Number(ev.t);
    const slot = Number(ev.slot);
    if (!Number.isFinite(t) || t < lastT) continue;
    if (!Number.isInteger(slot) || slot < 0 || slot > MAX_TIMELINE_SLOT) continue;
    if (ev.kind === 'shader' && typeof ev.value === 'string' && ev.value.length > 0 && ev.value.length <= MAX_SHADER_ID_LENGTH) {
      events.push({ t, slot, kind: 'shader', value: ev.value });
    } else if (ev.kind === 'param' && isTimelineParamKey(ev.key)
      && typeof ev.value === 'number' && Number.isFinite(ev.value)) {
      events.push({ t, slot, kind: 'param', key: ev.key, value: ev.value });
    } else if (ev.kind === 'source') {
      const source = sanitizeTimelineSource(ev.value);
      if (!source) continue;
      events.push({ t, slot: 0, kind: 'source', value: source });
    } else {
      continue;
    }
    lastT = t;
  }
  if (events.length === 0 && keyframes.length === 0) return null;
  const lastKey = keyframes.at(-1)?.t ?? 0;
  const end = Math.max(lastT, lastKey);
  const durationMs = typeof r.durationMs === 'number' && Number.isFinite(r.durationMs)
    ? Math.max(r.durationMs, end)
    : end;
  return { hz, durationMs, events, ...(keyframes.length > 0 ? { keyframes } : {}) };
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
