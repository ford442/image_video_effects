/**
 * compositeReference.ts
 *
 * CPU reference of public/shaders/_compositor/composite.wgsl + mask.wgsl for one
 * pixel (#1512 Part B). The unit tests pin the blend math with it, and the
 * golden-frame suite (tests/compositor-golden.swiftshader.spec.ts) derives its
 * expected colours from it, so the GPU and this file must stay in step.
 */

import type { CompositeGroupPlan, MaskDraw } from './compositor';
import { KEY_SOFTNESS } from './compositor';

export type Rgba = [number, number, number, number];

const luma = (c: Rgba | number[]) => 0.2126 * c[0]! + 0.7152 * c[1]! + 0.0722 * c[2]!;
const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
const smoothstep = (e0: number, e1: number, x: number) => {
  const t = clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
};

function screen(b: number, s: number): number {
  return b + s - Math.min(b, 1) * Math.min(s, 1);
}

function overlay(b: number, s0: number): number {
  const s = clamp01(s0);
  return b <= 0.5 ? 2 * b * s : 1 - 2 * (1 - b) * (1 - s);
}

function softLight(b0: number, s0: number): number {
  const b = clamp01(b0);
  const s = clamp01(s0);
  const d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : Math.sqrt(b);
  const v = s <= 0.5 ? b - (1 - 2 * s) * b * (1 - b) : b + (2 * s - 1) * (d - b);
  return v + Math.max(b0 - 1, 0);
}

/** One channel of a blend mode (linear light), as composite.wgsl `blend3`. */
export function blendChannel(mode: string, b: number, s: number): number {
  switch (mode) {
    case 'add': return b + s;
    case 'screen': return screen(b, s);
    case 'multiply': return b * s;
    case 'overlay': return overlay(b, s);
    case 'soft-light': return softLight(b, s);
    case 'difference': return Math.abs(b - s);
    default: return s;
  }
}

/** mask.wgsl for one pixel; `layers` holds every layer of the group at that pixel. */
export function maskValue(mask: MaskDraw, layers: readonly Rgba[], depth: number): number {
  let m = 1;
  const src = layers[mask.sourceLayer] ?? [0, 0, 0, 0];
  if (mask.source === 'luma') m = luma(src);
  else if (mask.source === 'depth') m = depth;
  else m = mask.matte === 'luma' ? luma(src) * src[3] : src[3];
  m = clamp01(m);
  return mask.invert ? 1 - m : m;
}

/**
 * composite.wgsl for one pixel (no feather: a feathered mask is a blur of
 * neighbouring mask values, which a single pixel cannot reproduce).
 */
export function compositePixel(
  plan: CompositeGroupPlan,
  base: Rgba,
  layers: readonly Rgba[],
  depth = 0,
): Rgba {
  let acc: Rgba = [...base];
  for (const l of plan.layers) {
    if (l.kind === 'mask') continue;
    const src = layers[l.layer] ?? [0, 0, 0, 0];
    if (l.kind === 'replace') {
      acc = [...src];
      continue;
    }
    let a = clamp01(l.opacity);
    if (l.mask) a *= maskValue(l.mask, layers, depth);
    if (l.blend === 'luma-key') {
      a *= smoothstep(l.keyThreshold - KEY_SOFTNESS, l.keyThreshold + KEY_SOFTNESS, luma(src.map((v) => Math.max(v, 0))));
    } else if (l.blend === 'depth-key') {
      a *= smoothstep(l.keyThreshold - KEY_SOFTNESS, l.keyThreshold + KEY_SOFTNESS, depth);
    }
    const mixed = [0, 1, 2].map((c) => {
      const b = acc[c]!;
      return b + (blendChannel(l.blend, b, src[c]!) - b) * a;
    });
    acc = [mixed[0]!, mixed[1]!, mixed[2]!, acc[3] + (src[3] - acc[3]) * a];
  }
  return acc;
}
