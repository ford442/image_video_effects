/**
 * compositor.ts
 *
 * Layer compositor for parallel slot groups (#1512 Part B). A parallel group used
 * to be "last one wins": every slot wrote writeTex and only the last survived. When
 * any slot of the group has a non-`replace` output (slotOutput.ts), the frame plan
 * instead copies each slot's result into one layer of a 2D-array texture, draws the
 * masks the layers ask for into per-slot r8unorm textures (optional feather), and
 * composites the group in **one compute pass** that writes writeTex. Everything
 * stays in the internal color format, so HDR values survive to the present pass.
 *
 * Chained slots are unchanged. A group whose outputs are all `replace` compiles to
 * exactly the pre-compositor ops (no layer copies, no extra pass).
 *
 * Ops (framePlan.ts): `layerCopy` after each composited slot, `composite` after the
 * group, then the usual writeTex → readTex copy and feedback. The GPU side is the
 * `FrameCompositor` interface; `SlotCompositor` (slotCompositor.ts) implements it. If
 * the compositor cannot run (still loading, allocation failed, not attached) both ops
 * are skipped and the group falls back to last-one-wins for that frame.
 *
 * This module is the pure half: planning, uniform packing and the interfaces. It stays
 * in the main bundle; slotCompositor.ts and its WGSL (public/shaders/_compositor/*.wgsl,
 * bundled by scripts/gen-compositor-wgsl.mjs) load as the lazy `compositor` chunk the
 * first time a group composites.
 */

import type { InternalColorFormat } from '../../config/formatPolicy';
import {
  BLEND_MODES,
  maskSourceSlot,
  normalizeSlotOutput,
  type BlendMode,
  type SlotOutput,
} from '../slotOutput';
import type { PassProfiler } from './nodeScale';

/** One layer per physical slot at most (slot_limits.json). */
export const MAX_COMPOSITE_LAYERS = 6;
/** Half-width of the luma-key / depth-key smoothstep ramp around the threshold. */
export const KEY_SOFTNESS = 0.08;
/** Feather 1 → this many working-size texels of blur radius. */
export const MAX_FEATHER_RADIUS_PX = 32;
export const MASK_FORMAT: GPUTextureFormat = 'r8unorm';
const NO_MASK = 0xffffffff;

export type CompositeLayerKind = 'replace' | 'blend' | 'mask';

export interface MaskDraw {
  source: 'luma' | 'depth' | 'slot';
  /** Layer the mask shader reads: the slot's own (luma) or the source slot's (slot). */
  sourceLayer: number;
  /** For `slot`: a mask-mode source is a luma × alpha matte, anything else its alpha. */
  matte: 'alpha' | 'luma';
  invert: boolean;
  /** 0–1; 0 skips the feather passes. */
  feather: number;
}

export interface CompositeLayer {
  slotIndex: number;
  kind: CompositeLayerKind;
  blend: BlendMode;
  opacity: number;
  keyThreshold: number;
  /** Array layer of this slot's output. */
  layer: number;
  /** Mask to draw into this layer's r8unorm texture (blend layers only). */
  mask: MaskDraw | null;
}

export interface CompositeGroupPlan {
  /** Composited slots in slot order (the order they blend in). */
  layers: CompositeLayer[];
  layerCount: number;
  /** Masks that could not be honored (e.g. `slot3` when slot 3 is not in the group). */
  warnings: string[];
}

/** True when this output takes part in compositing at all. */
export function outputComposites(output: SlotOutput | undefined): boolean {
  return !!output && output.mode !== 'replace';
}

/**
 * Plan the composite of one parallel group from the slots that actually encoded
 * passes this frame, in slot order. Null when every output is `replace`: the group
 * then keeps today's last-one-wins path, byte for byte.
 */
export function planCompositeGroup(
  slots: ReadonlyArray<{ slotIndex: number; output?: SlotOutput }>,
): CompositeGroupPlan | null {
  if (!slots.some((s) => outputComposites(s.output))) return null;
  const used = slots.slice(0, MAX_COMPOSITE_LAYERS);
  const layerOf = new Map<number, number>();
  used.forEach((s, i) => layerOf.set(s.slotIndex, i));
  const warnings: string[] = [];

  const layers = used.map((s, layer): CompositeLayer => {
    const o = normalizeSlotOutput(s.output);
    let mask: MaskDraw | null = null;
    if (o.mode === 'blend' && o.mask !== 'none') {
      const base = { invert: o.maskInvert, feather: o.feather };
      if (o.mask === 'luma') {
        mask = { source: 'luma', sourceLayer: layer, matte: 'alpha', ...base };
      } else if (o.mask === 'depth') {
        mask = { source: 'depth', sourceLayer: layer, matte: 'alpha', ...base };
      } else {
        const sourceSlot = maskSourceSlot(o.mask);
        const sourceLayer = sourceSlot === null ? undefined : layerOf.get(sourceSlot);
        if (sourceLayer === undefined) {
          warnings.push(
            `slot ${s.slotIndex + 1}: mask ${o.mask} is not a parallel slot of this group — drawn unmasked`,
          );
        } else {
          const source = used[sourceLayer];
          const matte = normalizeSlotOutput(source?.output).mode === 'mask' ? 'luma' : 'alpha';
          mask = { source: 'slot', sourceLayer, matte, ...base };
        }
      }
    }
    return {
      slotIndex: s.slotIndex,
      kind: o.mode,
      blend: o.blend,
      opacity: o.opacity,
      keyThreshold: o.keyThreshold,
      layer,
      mask,
    };
  });
  return { layers, layerCount: layers.length, warnings };
}

// ── Uniform packing (layouts in public/shaders/_compositor/*.wgsl) ───────────

/** `CompositeParams`: 16-byte header + 6 × 32-byte `Layer`. */
export const COMPOSITE_PARAMS_BYTES = 16 + MAX_COMPOSITE_LAYERS * 32;
/** `MaskParams` / `FeatherParams` are 16 bytes; slices sit at the uniform offset alignment. */
export const PARAM_SLICE_BYTES = 256;

const KIND_CODE: Record<CompositeLayerKind, number> = { replace: 0, blend: 1, mask: 2 };

export function packCompositeParams(plan: CompositeGroupPlan): ArrayBuffer {
  const buf = new ArrayBuffer(COMPOSITE_PARAMS_BYTES);
  const u32 = new Uint32Array(buf);
  const f32 = new Float32Array(buf);
  const count = Math.min(plan.layers.length, MAX_COMPOSITE_LAYERS);
  u32[0] = count;
  plan.layers.slice(0, count).forEach((l, i) => {
    const o = 4 + i * 8;
    u32[o] = KIND_CODE[l.kind];
    u32[o + 1] = Math.max(0, BLEND_MODES.indexOf(l.blend));
    u32[o + 2] = l.layer;
    u32[o + 3] = l.mask ? l.layer : NO_MASK;
    f32[o + 4] = l.opacity;
    f32[o + 5] = l.keyThreshold;
    f32[o + 6] = KEY_SOFTNESS;
  });
  return buf;
}

const MASK_SOURCE_CODE: Record<MaskDraw['source'], number> = { luma: 1, depth: 2, slot: 3 };

export function packMaskParams(mask: MaskDraw): Uint32Array<ArrayBuffer> {
  return new Uint32Array([
    MASK_SOURCE_CODE[mask.source],
    mask.sourceLayer,
    mask.matte === 'luma' ? 1 : 0,
    mask.invert ? 1 : 0,
  ]);
}

/** Feather radius in working-size texels for a 0–1 feather. */
export function featherRadiusPx(feather: number): number {
  return Math.max(0, Math.min(1, feather)) * MAX_FEATHER_RADIUS_PX;
}

export function packFeatherParams(horizontal: boolean, radiusPx: number, width: number, height: number): Float32Array<ArrayBuffer> {
  return new Float32Array([
    horizontal ? 1 / Math.max(1, width) : 0,
    horizontal ? 0 : 1 / Math.max(1, height),
    radiusPx,
    0,
  ]);
}

/** Bytes the compositor's layer + mask textures take at this size. */
export function compositorTextureBytes(
  width: number,
  height: number,
  colorFormat: InternalColorFormat,
  layerCount: number,
  maskCount: number,
  feathered: boolean,
): number {
  const bpp = colorFormat === 'rgba32float' ? 16 : 8;
  return width * height * (bpp * layerCount + maskCount + (feathered ? 1 : 0));
}

// ── GPU side (implemented in slotCompositor.ts) ──────────────────────────────

/** What the frame-plan executor needs from the compositor (implemented by SlotCompositor). */
export interface FrameCompositor {
  /** Copy the slot output in `source` into `layer` of a `layerCount`-layer array. */
  encodeLayerCopy(encoder: GPUCommandEncoder, source: GPUTexture, layer: number, layerCount: number): boolean;
  /** Masks + one compute pass: blend the group's layers over `base` into `out`. */
  encodeComposite(
    encoder: GPUCommandEncoder,
    plan: CompositeGroupPlan,
    base: GPUTexture,
    out: GPUTexture,
    profile?: PassProfiler,
  ): boolean;
}

export interface CompositorAttachment {
  device: GPUDevice;
  colorFormat: InternalColorFormat;
  scaledW: number;
  scaledH: number;
  /** The DPT depth map (catalog binding 4, r32float). */
  depthTex: GPUTexture;
}

export interface CompositorStats {
  /** Layers in the allocated array (0 when nothing is allocated). */
  layers: number;
  masks: number;
  /** MiB held by layer, mask and scratch textures. */
  textureMiB: number;
  /** Composite passes encoded since attach. */
  composites: number;
  /** Set when an allocation failed; the compositor stays off until the size or device changes. */
  error: string | null;
  /** Last group's unresolved-mask warnings. */
  warnings: string[];
}

/** Stats before the GPU side has loaded (or after the renderer released it). */
export const IDLE_COMPOSITOR_STATS: Readonly<CompositorStats> = Object.freeze({
  layers: 0,
  masks: 0,
  textureMiB: 0,
  composites: 0,
  error: null,
  warnings: [],
});
