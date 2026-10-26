/**
 * slotOutput.ts
 *
 * Per-slot compositor output (#1512 Part B): how a slot's picture joins the
 * frame. Pure data, no GPU: the renderer, the render-worker protocol, project
 * files, chain URLs and the layer strip all share these types.
 *
 * - `replace` (default) is today's behaviour: the slot's output is the picture
 *   (for parallel slots the last one wins).
 * - `blend` composites the output over what the group has so far, with a blend
 *   mode, an opacity and an optional mask, in linear light.
 * - `mask` renders the slot but never draws it: its luma × alpha is a matte
 *   other slots can pick as their mask (`slotN`).
 *
 * Only parallel slots composite (docs/PARALLEL_SLOTS.md, "Layer compositor");
 * a chained slot always replaces. See src/renderer/webgpu/compositor.ts.
 */

export const SLOT_OUTPUT_MODES = ['replace', 'blend', 'mask'] as const;
export type SlotOutputMode = (typeof SLOT_OUTPUT_MODES)[number];

/** Order is the GPU contract: the index is the `blend` code in compositor.wgsl. */
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

/** `slotN` is slot N's matte: its alpha, or luma × alpha when slot N is a `mask` slot. */
export type MaskSource = 'none' | 'luma' | 'depth' | `slot${number}`;

export interface SlotOutput {
  mode: SlotOutputMode;
  blend: BlendMode;
  /** 0–1. Automatable (MIDI / OSC / audio) like a slot param. */
  opacity: number;
  mask: MaskSource;
  maskInvert: boolean;
  /** 0–1: blur radius of the mask (0 = no feather pass). */
  feather: number;
  /** 0–1: luma-key / depth-key threshold. */
  keyThreshold: number;
}

export const DEFAULT_SLOT_OUTPUT: Readonly<SlotOutput> = Object.freeze({
  mode: 'replace',
  blend: 'normal',
  opacity: 1,
  mask: 'none',
  maskInvert: false,
  feather: 0,
  keyThreshold: 0.5,
});

/** Labels for the layer strip. */
export const BLEND_MODE_LABELS: Record<BlendMode, string> = {
  normal: 'Normal',
  add: 'Add',
  screen: 'Screen',
  multiply: 'Multiply',
  overlay: 'Overlay',
  'soft-light': 'Soft light',
  difference: 'Difference',
  'luma-key': 'Luma key',
  'depth-key': 'Depth key',
};

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

export function isBlendMode(value: unknown): value is BlendMode {
  return typeof value === 'string' && (BLEND_MODES as readonly string[]).includes(value);
}

export function isSlotOutputMode(value: unknown): value is SlotOutputMode {
  return typeof value === 'string' && (SLOT_OUTPUT_MODES as readonly string[]).includes(value);
}

/** The slot index a `slotN` mask points at, or null for the other sources. */
export function maskSourceSlot(mask: MaskSource): number | null {
  const m = /^slot(\d+)$/.exec(mask);
  return m ? Number(m[1]) : null;
}

export function isMaskSource(value: unknown, slotCount = Number.POSITIVE_INFINITY): value is MaskSource {
  if (value === 'none' || value === 'luma' || value === 'depth') return true;
  if (typeof value !== 'string') return false;
  const slot = maskSourceSlot(value as MaskSource);
  return slot !== null && slot < slotCount;
}

/** Fill defaults, clamp the numbers and drop invalid enums. Never throws. */
export function normalizeSlotOutput(input: Partial<SlotOutput> | null | undefined): SlotOutput {
  const src = input ?? {};
  const num = (v: unknown, fallback: number) =>
    typeof v === 'number' && Number.isFinite(v) ? clamp01(v) : fallback;
  return {
    mode: isSlotOutputMode(src.mode) ? src.mode : DEFAULT_SLOT_OUTPUT.mode,
    blend: isBlendMode(src.blend) ? src.blend : DEFAULT_SLOT_OUTPUT.blend,
    opacity: num(src.opacity, DEFAULT_SLOT_OUTPUT.opacity),
    mask: isMaskSource(src.mask) ? src.mask : DEFAULT_SLOT_OUTPUT.mask,
    maskInvert: src.maskInvert === true,
    feather: num(src.feather, DEFAULT_SLOT_OUTPUT.feather),
    keyThreshold: num(src.keyThreshold, DEFAULT_SLOT_OUTPUT.keyThreshold),
  };
}

/** Merge a patch onto an existing output (both normalized). */
export function patchSlotOutput(current: SlotOutput | undefined, patch: Partial<SlotOutput>): SlotOutput {
  return normalizeSlotOutput({ ...normalizeSlotOutput(current), ...patch });
}

export function isDefaultSlotOutput(output: SlotOutput | undefined): boolean {
  if (!output) return true;
  const o = normalizeSlotOutput(output);
  return (Object.keys(DEFAULT_SLOT_OUTPUT) as Array<keyof SlotOutput>).every(
    (key) => o[key] === DEFAULT_SLOT_OUTPUT[key],
  );
}

export function slotOutputsEqual(a: SlotOutput | undefined, b: SlotOutput | undefined): boolean {
  const x = normalizeSlotOutput(a);
  const y = normalizeSlotOutput(b);
  return (Object.keys(DEFAULT_SLOT_OUTPUT) as Array<keyof SlotOutput>).every((key) => x[key] === y[key]);
}

// ── Chain-URL compact params (layerChainShare.ts) ─────────────────────────────
//
//   b=<blend mode> | b=mask   output mode blend (or mask); absent = replace
//   o=<opacity>               0–1, at most 3 decimals; absent = 1
//   m=<mask>                  luma | depth | slotN, `~` prefix = inverted; absent = none
//   f=<feather>               0–1; absent = 0
//   k=<key threshold>         0–1; absent = 0.5
//
// Only non-default fields are written, so a replace slot adds nothing to the URL.

export const SLOT_OUTPUT_COMPACT_KEYS = ['b', 'o', 'm', 'f', 'k'] as const;
export type SlotOutputCompactKey = (typeof SLOT_OUTPUT_COMPACT_KEYS)[number];

const round3 = (v: number) => String(Math.round(v * 1000) / 1000);

export function encodeSlotOutputCompact(output: SlotOutput | undefined): Partial<Record<SlotOutputCompactKey, string>> {
  const o = normalizeSlotOutput(output);
  const out: Partial<Record<SlotOutputCompactKey, string>> = {};
  if (o.mode === 'mask') out.b = 'mask';
  else if (o.mode === 'blend') out.b = o.blend;
  if (o.opacity !== DEFAULT_SLOT_OUTPUT.opacity) out.o = round3(o.opacity);
  if (o.mask !== 'none') out.m = `${o.maskInvert ? '~' : ''}${o.mask}`;
  if (o.feather !== DEFAULT_SLOT_OUTPUT.feather) out.f = round3(o.feather);
  if (o.keyThreshold !== DEFAULT_SLOT_OUTPUT.keyThreshold) out.k = round3(o.keyThreshold);
  return out;
}

/**
 * Parse compact keys back into an output. Unknown or malformed values fall back
 * to the defaults; returns undefined when no output key is present at all.
 */
export function decodeSlotOutputCompact(
  values: Partial<Record<string, string>>,
  slotCount = Number.POSITIVE_INFINITY,
): SlotOutput | undefined {
  if (!SLOT_OUTPUT_COMPACT_KEYS.some((key) => values[key] !== undefined)) return undefined;
  const patch: Partial<SlotOutput> = {};
  const b = values.b;
  if (b === 'mask') patch.mode = 'mask';
  else if (isBlendMode(b)) {
    patch.mode = 'blend';
    patch.blend = b;
  }
  const num = (raw: string | undefined) => {
    if (raw === undefined || raw.trim() === '') return undefined;
    const v = Number(raw);
    return Number.isFinite(v) ? v : undefined;
  };
  patch.opacity = num(values.o);
  patch.feather = num(values.f);
  patch.keyThreshold = num(values.k);
  const m = values.m;
  if (m) {
    const invert = m.startsWith('~');
    const source = invert ? m.slice(1) : m;
    if (isMaskSource(source, slotCount) && source !== 'none') {
      patch.mask = source;
      patch.maskInvert = invert;
    }
  }
  return normalizeSlotOutput(patch);
}
