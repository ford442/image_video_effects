/**
 * layerState.ts
 *
 * Per-slot compositing state (#1512 Part B): how a slot's output joins the
 * image below it. Pure data + helpers, shared by the renderer (compositor.ts),
 * the render-worker protocol, persistence (layerChainShare.ts, project files)
 * and the layer strip UI. No GPU code here.
 *
 *   output 'replace'  today's behaviour: the slot's output replaces what is
 *                     below it (opacity, mask and blend are ignored)
 *   output 'blend'    blend mode × opacity × mask over the image below
 *   output 'mask'     contributes no colour; its luma is a matte other slots
 *                     can pick as their mask ("slot N")
 *
 * See docs/COMPOSITOR.md.
 */

export const BLEND_MODES = [
  'normal',
  'add',
  'screen',
  'multiply',
  'overlay',
  'soft-light',
  'difference',
  'luma-key',
  'depth-key',
] as const;

export type BlendMode = (typeof BLEND_MODES)[number];

export type LayerOutput = 'replace' | 'blend' | 'mask';

export type MaskSourceKind = 'none' | 'luma' | 'depth' | 'slot';

export interface LayerMask {
  source: MaskSourceKind;
  /** Physical slot whose matte is used (source 'slot' only). */
  slot?: number;
  /** Use 1 − mask. */
  invert?: boolean;
  /** Feather amount 0..1 (0 = hard edge); see FEATHER_MAX_RADIUS_PX. */
  feather?: number;
}

export interface SlotLayer {
  output: LayerOutput;
  blend: BlendMode;
  /** 0..1; automatable through the slot param 'opacity' (MIDI / OSC / audio). */
  opacity: number;
  mask: LayerMask;
  /** Key threshold 0..1 for luma-key / depth-key; absent → the mode's default. */
  key?: number;
}

/** Physical slots a mask can reference (mirrors PHYSICAL_SLOT_LIMIT without importing the orchestrator). */
export const LAYER_SLOT_COUNT = 6;

/** Feather 1.0 blurs the mask over this many pixels at a 1024-pixel-high working size (scaled with it). */
export const FEATHER_MAX_RADIUS_PX = 24;

export const DEFAULT_KEY_THRESHOLD: Record<'luma-key' | 'depth-key', number> = {
  // Luma key removes near-black (the classic "black is transparent" overlay key).
  'luma-key': 0.08,
  // Depth key shows the layer where the DPT depth map is nearer than the midpoint.
  'depth-key': 0.5,
};

export const NO_MASK: LayerMask = { source: 'none' };

export const DEFAULT_SLOT_LAYER: SlotLayer = {
  output: 'replace',
  blend: 'normal',
  opacity: 1,
  mask: NO_MASK,
};

export function defaultSlotLayer(): SlotLayer {
  return { ...DEFAULT_SLOT_LAYER, mask: { ...NO_MASK } };
}

export function isBlendMode(value: unknown): value is BlendMode {
  return typeof value === 'string' && (BLEND_MODES as readonly string[]).includes(value);
}

export function isLayerOutput(value: unknown): value is LayerOutput {
  return value === 'replace' || value === 'blend' || value === 'mask';
}

function clamp01(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : fallback;
}

export function normalizeLayerMask(raw: unknown): LayerMask {
  if (!raw || typeof raw !== 'object') return { ...NO_MASK };
  const m = raw as Partial<LayerMask>;
  const source: MaskSourceKind =
    m.source === 'luma' || m.source === 'depth' || m.source === 'slot' ? m.source : 'none';
  if (source === 'none') return { ...NO_MASK };
  const out: LayerMask = { source };
  if (source === 'slot') {
    const slot = typeof m.slot === 'number' && Number.isInteger(m.slot) ? m.slot : -1;
    if (slot < 0 || slot >= LAYER_SLOT_COUNT) return { ...NO_MASK };
    out.slot = slot;
  }
  if (m.invert === true) out.invert = true;
  const feather = clamp01(m.feather, 0);
  if (feather > 0) out.feather = feather;
  return out;
}

/** Fill defaults and clamp a (possibly untrusted) layer description. Never throws. */
export function normalizeSlotLayer(raw: unknown): SlotLayer {
  if (!raw || typeof raw !== 'object') return defaultSlotLayer();
  const l = raw as Partial<SlotLayer>;
  const layer: SlotLayer = {
    output: isLayerOutput(l.output) ? l.output : 'replace',
    blend: isBlendMode(l.blend) ? l.blend : 'normal',
    opacity: clamp01(l.opacity, 1),
    mask: normalizeLayerMask(l.mask),
  };
  if (typeof l.key === 'number' && Number.isFinite(l.key)) layer.key = clamp01(l.key, 0);
  return layer;
}

/** The key threshold the compositor uses for this layer. */
export function layerKeyThreshold(layer: SlotLayer): number {
  if (layer.key !== undefined) return layer.key;
  return layer.blend === 'luma-key' || layer.blend === 'depth-key' ? DEFAULT_KEY_THRESHOLD[layer.blend] : 0.5;
}

/**
 * True when the layer renders exactly like today's replace path, so the frame
 * plan can skip the compositor: replace, or a normal blend at full opacity
 * with no mask.
 */
export function isPassThroughLayer(layer: SlotLayer | undefined): boolean {
  if (!layer || layer.output === 'replace') return true;
  if (layer.output === 'mask') return false;
  return layer.blend === 'normal' && layer.opacity >= 1 && layer.mask.source === 'none';
}

export function slotLayersEqual(a: SlotLayer, b: SlotLayer): boolean {
  return a.output === b.output
    && a.blend === b.blend
    && a.opacity === b.opacity
    && a.key === b.key
    && a.mask.source === b.mask.source
    && a.mask.slot === b.mask.slot
    && !!a.mask.invert === !!b.mask.invert
    && (a.mask.feather ?? 0) === (b.mask.feather ?? 0);
}

// ── Compact wire form (chain URLs, project files) ────────────────────────────
//
//   b  'mask' for a matte slot, else the blend mode name; absent → replace
//   o  opacity 0..1; absent → 1
//   m  mask ref: [!]<src>[~<feather>] with src l (luma), d (depth), s0..s5 (slot);
//      '!' inverts, e.g. "!d~0.25"; absent → no mask
//   k  key threshold; absent → the mode's default

export interface CompactSlotLayer {
  b?: string;
  o?: number;
  m?: string;
  k?: number;
}

const MASK_REF_RE = /^(!)?(l|d|s([0-5]))(?:~(\d*\.?\d+))?$/;

export function encodeMaskRef(mask: LayerMask): string | undefined {
  if (mask.source === 'none') return undefined;
  if (mask.source === 'slot' && (mask.slot === undefined || mask.slot < 0 || mask.slot >= LAYER_SLOT_COUNT)) {
    return undefined;
  }
  const src = mask.source === 'luma' ? 'l' : mask.source === 'depth' ? 'd' : `s${mask.slot}`;
  const feather = mask.feather && mask.feather > 0 ? `~${roundForWire(mask.feather)}` : '';
  return `${mask.invert ? '!' : ''}${src}${feather}`;
}

/** Null when `ref` is not a valid mask reference. */
export function decodeMaskRef(ref: string): LayerMask | null {
  const m = MASK_REF_RE.exec(ref.trim());
  if (!m) return null;
  const mask: LayerMask =
    m[2] === 'l' ? { source: 'luma' }
    : m[2] === 'd' ? { source: 'depth' }
    : { source: 'slot', slot: Number(m[3]) };
  if (m[1]) mask.invert = true;
  if (m[4] !== undefined) {
    const feather = Math.min(1, Math.max(0, Number(m[4])));
    if (feather > 0) mask.feather = feather;
  }
  return mask;
}

function roundForWire(value: number): number {
  return Math.round(value * 1000) / 1000;
}

/** Compact form of a layer; empty object for the default (replace) layer. */
export function compactSlotLayer(layer: SlotLayer): CompactSlotLayer {
  if (layer.output === 'replace') return {};
  // A matte contributes no colour, so opacity / mask / key mean nothing on it.
  if (layer.output === 'mask') return { b: 'mask' };
  const out: CompactSlotLayer = { b: layer.blend };
  if (layer.opacity < 1) out.o = roundForWire(layer.opacity);
  const m = encodeMaskRef(layer.mask);
  if (m) out.m = m;
  if (layer.key !== undefined) out.k = roundForWire(layer.key);
  return out;
}

/**
 * Expand the compact fields. Unknown or malformed values fall back to the
 * defaults (a link made by a newer build degrades instead of failing).
 */
export function expandCompactSlotLayer(compact: CompactSlotLayer | undefined): SlotLayer {
  const layer = defaultSlotLayer();
  if (!compact) return layer;
  if (compact.b === 'mask') layer.output = 'mask';
  else if (isBlendMode(compact.b)) {
    layer.output = 'blend';
    layer.blend = compact.b;
  }
  if (layer.output !== 'blend') return layer;
  layer.opacity = clamp01(compact.o, 1);
  if (typeof compact.m === 'string') layer.mask = decodeMaskRef(compact.m) ?? { ...NO_MASK };
  if (typeof compact.k === 'number' && Number.isFinite(compact.k)) layer.key = clamp01(compact.k, 0);
  return layer;
}

/** Validation errors for compact fields (project files are strict, links are lenient). */
export function compactSlotLayerErrors(raw: Record<string, unknown>, path: string): string[] {
  const errors: string[] = [];
  if (raw.b !== undefined && raw.b !== 'mask' && !isBlendMode(raw.b)) {
    errors.push(`${path}.b must be "mask" or one of ${BLEND_MODES.join(', ')}`);
  }
  if (raw.o !== undefined && (typeof raw.o !== 'number' || !Number.isFinite(raw.o) || raw.o < 0 || raw.o > 1)) {
    errors.push(`${path}.o must be a number from 0 to 1`);
  }
  if (raw.m !== undefined && (typeof raw.m !== 'string' || decodeMaskRef(raw.m) === null)) {
    errors.push(`${path}.m must be a mask reference like "l", "d", "s2", "!d~0.25"`);
  }
  if (raw.k !== undefined && (typeof raw.k !== 'number' || !Number.isFinite(raw.k) || raw.k < 0 || raw.k > 1)) {
    errors.push(`${path}.k must be a number from 0 to 1`);
  }
  return errors;
}

// ── UI helpers ───────────────────────────────────────────────────────────────

/** One dropdown value per (output, blend) pair the layer strip offers. */
export type LayerChoice = 'replace' | 'mask' | BlendMode;

export function layerChoice(layer: SlotLayer): LayerChoice {
  return layer.output === 'blend' ? layer.blend : layer.output;
}

export function applyLayerChoice(layer: SlotLayer, choice: LayerChoice): SlotLayer {
  if (choice === 'replace' || choice === 'mask') return { ...layer, output: choice };
  return { ...layer, output: 'blend', blend: choice };
}

export const LAYER_CHOICE_LABELS: Record<LayerChoice, string> = {
  replace: 'Replace',
  normal: 'Normal',
  add: 'Add',
  screen: 'Screen',
  multiply: 'Multiply',
  overlay: 'Overlay',
  'soft-light': 'Soft light',
  difference: 'Difference',
  'luma-key': 'Luma key',
  'depth-key': 'Depth key',
  mask: 'Matte (mask source)',
};
