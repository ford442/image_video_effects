/**
 * compositorPlan.ts
 *
 * Pure planning half of the layer compositor (#1512 Part B): which slot
 * outputs are captured into the layer stack, and what each composite op
 * blends. framePlan.ts emits these ops; compositor.ts encodes them. No GPU
 * calls here, so the whole plan is unit-testable.
 *
 * Stack layers are assigned in encode order, one per captured slot, so a
 * mask can reference any slot that ran earlier in the frame (or anywhere in
 * the same parallel group, since the group's captures all precede its
 * composite).
 */

import {
  BLEND_MODES,
  isPassThroughLayer,
  layerKeyThreshold,
  type BlendMode,
  type LayerOutput,
  type SlotLayer,
} from '../layerState';
import type { ShaderSlot } from './webgpuConstants';

/** One layer per physical slot at most. */
export const MAX_STACK_LAYERS = 6;

/** Half-width of the luma/depth key edge (smoothstep around the threshold). */
export const KEY_SOFTNESS = 0.04;

export interface ResolvedLayerMask {
  source: 'luma' | 'depth' | 'slot';
  /** Stack layer the mask reads (own layer for luma; the referenced slot for 'slot'). */
  srcStackLayer: number;
  /** The referenced slot is a matte (use its luma), else its alpha. */
  srcIsMatte: boolean;
  invert: boolean;
  /** 0..1, 0 = no feather pass. */
  feather: number;
}

export interface CompositeLayer {
  slotIndex: number;
  stackLayer: number;
  output: LayerOutput;
  blend: BlendMode;
  /** Index into BLEND_MODES (the shader's BLEND_* constants). */
  blendIndex: number;
  opacity: number;
  key: number;
  mask: ResolvedLayerMask | null;
}

export interface CaptureLayerOp {
  kind: 'captureLayer';
  slotIndex: number;
  stackLayer: number;
}

export interface CompositeOp {
  kind: 'composite';
  label: string;
  /** A parallel group over its shared input, or one chained slot over its input. */
  group: 'parallel' | 'chained';
  layers: CompositeLayer[];
  /** Slots whose 'slot' mask names a slot not captured before this composite (drawn unmasked). */
  unresolvedMasks: number[];
}

interface PlannedSlot {
  slotIndex: number;
  slot: ShaderSlot;
}

/** Slots some enabled blend layer uses as its mask source. */
export function maskSourceSlots(plans: readonly PlannedSlot[]): Set<number> {
  const out = new Set<number>();
  for (const { slot } of plans) {
    const layer = slot.layer;
    if (layer?.output === 'blend' && layer.mask.source === 'slot' && layer.mask.slot !== undefined) {
      out.add(layer.mask.slot);
    }
  }
  return out;
}

/** A parallel group runs through the compositor once any member is not a plain replace. */
export function groupNeedsCompositor(plans: readonly PlannedSlot[]): boolean {
  return plans.some(({ slot }) => !isPassThroughLayer(slot.layer));
}

/** Assigns stack layers and resolves masks while the frame plan compiles. */
export class LayerStackBuilder {
  private readonly bySlot = new Map<number, { stackLayer: number; output: LayerOutput }>();
  private composites = 0;

  get size(): number {
    return this.bySlot.size;
  }

  get compositeCount(): number {
    return this.composites;
  }

  /** Null when the stack is full (the capture is dropped; that layer then renders as replace). */
  capture(slotIndex: number, slot: ShaderSlot): CaptureLayerOp | null {
    const existing = this.bySlot.get(slotIndex);
    if (existing) return { kind: 'captureLayer', slotIndex, stackLayer: existing.stackLayer };
    if (this.bySlot.size >= MAX_STACK_LAYERS) return null;
    const stackLayer = this.bySlot.size;
    this.bySlot.set(slotIndex, { stackLayer, output: slot.layer?.output ?? 'replace' });
    return { kind: 'captureLayer', slotIndex, stackLayer };
  }

  has(slotIndex: number): boolean {
    return this.bySlot.has(slotIndex);
  }

  private resolveMask(slotIndex: number, layer: SlotLayer, ownStackLayer: number): ResolvedLayerMask | null | 'unresolved' {
    if (layer.output !== 'blend') return null;
    const mask = layer.mask;
    const base = { invert: !!mask.invert, feather: mask.feather ?? 0 };
    switch (mask.source) {
      case 'luma':
        return { source: 'luma', srcStackLayer: ownStackLayer, srcIsMatte: false, ...base };
      case 'depth':
        return { source: 'depth', srcStackLayer: ownStackLayer, srcIsMatte: false, ...base };
      case 'slot': {
        const ref = mask.slot === undefined ? undefined : mask.slot === slotIndex
          ? { stackLayer: ownStackLayer, output: layer.output }
          : this.bySlot.get(mask.slot);
        if (!ref) return 'unresolved';
        return { source: 'slot', srcStackLayer: ref.stackLayer, srcIsMatte: ref.output === 'mask', ...base };
      }
      default:
        return null;
    }
  }

  /**
   * Composite over the captured layers of `plans` (in order). Slots whose
   * capture was dropped (stack full) are left out, so they behave as if the
   * compositor were off.
   */
  composite(group: 'parallel' | 'chained', plans: readonly PlannedSlot[]): CompositeOp {
    const layers: CompositeLayer[] = [];
    const unresolvedMasks: number[] = [];
    for (const { slotIndex, slot } of plans) {
      const entry = this.bySlot.get(slotIndex);
      if (!entry) continue;
      const layer = slot.layer;
      const output = layer?.output ?? 'replace';
      const blend: BlendMode = layer?.blend ?? 'normal';
      let mask: ResolvedLayerMask | null = null;
      if (layer) {
        const resolved = this.resolveMask(slotIndex, layer, entry.stackLayer);
        if (resolved === 'unresolved') unresolvedMasks.push(slotIndex);
        else mask = resolved;
      }
      layers.push({
        slotIndex,
        stackLayer: entry.stackLayer,
        output,
        blend,
        blendIndex: Math.max(0, BLEND_MODES.indexOf(blend)),
        opacity: output === 'blend' ? layer?.opacity ?? 1 : 1,
        key: layer ? layerKeyThreshold(layer) : 0.5,
        mask,
      });
    }
    this.composites++;
    const slotsLabel = plans.map((p) => p.slotIndex).join('+');
    return { kind: 'composite', label: `composite-${group}-${slotsLabel}`, group, layers, unresolvedMasks };
  }
}
