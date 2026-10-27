/**
 * compositorReference.ts
 *
 * CPU mirror of public/shaders/_compositor/composite.wgsl, one pixel at a
 * time. The golden-frame suite (tests/compositor-golden.swiftshader.spec.ts)
 * derives its expected pixels from it, and compositor.test.ts pins it to the
 * shader's formulas. Keep the two in lock-step: a change to a blend formula
 * in the WGSL must land here in the same commit.
 */

import { BLEND_MODES, type BlendMode, type LayerOutput } from '../layerState';
import { KEY_SOFTNESS } from '../webgpu/compositorPlan';

export type Rgba = [number, number, number, number];
type Rgb = readonly [number, number, number, ...number[]];

export interface ReferenceLayer {
  output: LayerOutput;
  blend: BlendMode;
  opacity: number;
  key?: number;
  /** Mask value at this pixel, 0..1 (absent = unmasked). */
  mask?: number;
  color: Rgba;
}

const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
const luma = (c: Rgb) => 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
const mix = (a: number, b: number, t: number) => a + (b - a) * t;

function smoothstep(e0: number, e1: number, x: number): number {
  const t = clamp01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
}

function overlay(a: number, b: number): number {
  return a <= 0.5 ? 2 * a * b : 1 - 2 * (1 - a) * (1 - b);
}

function softLight(a: number, b: number): number {
  const d = a <= 0.25 ? ((16 * a - 12) * a + 4) * a : Math.sqrt(a);
  return b <= 0.5 ? a - (1 - 2 * b) * a * (1 - a) : a + (2 * b - 1) * (d - a);
}

function blendChannel(mode: BlendMode, a: number, b: number): number {
  const sa = clamp01(a);
  const sb = clamp01(b);
  const excess = Math.max(a - 1, 0);
  switch (mode) {
    case 'add': return a + b;
    case 'screen': return a + b - sa * sb;
    case 'multiply': return a * b;
    case 'overlay': return overlay(sa, sb) + excess;
    case 'soft-light': return softLight(sa, sb) + excess;
    case 'difference': return Math.abs(a - b);
    default: return b;
  }
}

export function referenceBlendRgb(
  mode: BlendMode,
  a: Rgb,
  b: Rgb,
  depth: number,
  key: number,
): [number, number, number] {
  if (mode === 'luma-key' || mode === 'depth-key') {
    const k = smoothstep(key - KEY_SOFTNESS, key + KEY_SOFTNESS, mode === 'luma-key' ? luma(b) : depth);
    return [mix(a[0], b[0], k), mix(a[1], b[1], k), mix(a[2], b[2], k)];
  }
  return [blendChannel(mode, a[0], b[0]), blendChannel(mode, a[1], b[1]), blendChannel(mode, a[2], b[2])];
}

/** The compositor's output for one pixel: `base` under `layers`, in order. */
export function referenceComposite(base: Rgba, layers: readonly ReferenceLayer[], depth = 0): Rgba {
  let acc: Rgba = [...base];
  for (const layer of layers) {
    if (layer.output === 'mask') continue;
    if (layer.output === 'replace') {
      acc = [...layer.color];
      continue;
    }
    const a = clamp01(layer.opacity) * (layer.mask ?? 1);
    const rgb = referenceBlendRgb(layer.blend, acc, layer.color, depth, layer.key ?? 0.5);
    acc = [mix(acc[0], rgb[0], a), mix(acc[1], rgb[1], a), mix(acc[2], rgb[2], a), mix(acc[3], layer.color[3], a)];
  }
  return acc;
}

export { BLEND_MODES };
