/**
 * directPresent.ts
 *
 * Direct-to-swapchain present (#1512 Part A, `bgra8unorm-storage`): when the
 * canvas is bgra8unorm and the device has the feature, the boot probe
 * configures the swapchain with STORAGE_BINDING. An eligible final slot then
 * writes the swapchain texture as its binding-2 storage texture and the
 * present blit (one full-screen pass + a texture read) is skipped.
 *
 * The slot runs a variant of its own shader: binding 2 retyped to
 * `texture_storage_2d<bgra8unorm, write>` and every value it stores passed
 * through the blit's encode (clamp, γ 2.2, alpha 1), so the pixels match the
 * blit path exactly. Eligible only when the result is provably the same:
 *
 *   - one enabled slot, chained, a single-pass program (no graph / multipass)
 *     with a pass-through (replace) layer
 *   - working size == canvas size (the blit would not resample)
 *   - not generative input (the generative blit flips Y)
 *   - no history ring (it copies the frame's output from the working texture)
 *   - no thumbnail capture in flight (it reads the working texture)
 *
 * Anything else, or a variant that fails to compile, uses the normal path.
 * Kill switch: `?no_direct_present` (setDirectPresentEnabled(false)).
 */

import canvasConfigureContract from '../../contracts/canvas_configure.json';
import { isPassThroughLayer } from '../layerState';
import type { FrameSlotDispatchPlan } from './slotDispatch';
import type { ComputeOp } from './framePlan';

export const DIRECT_PRESENT_FORMAT = canvasConfigureContract.optIn.storageBinding.format as GPUTextureFormat;

/** Appended to a direct variant: the same encode as BLIT_WGSL's fragment shader. */
const ENCODE_FN = /* wgsl */ `
fn px_direct_present_encode(c: vec4<f32>) -> vec4<f32> {
  return vec4<f32>(pow(clamp(c.rgb, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(1.0 / 2.2)), 1.0);
}
`;

const BINDING2_RE = /(@group\(\s*0\s*\)\s*@binding\(\s*2\s*\)\s*var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*)texture_storage_2d\s*<\s*rgba\w+\s*,\s*write\s*>/;

/** Index of the parenthesis closing the one opened just before `start`, or -1. */
function closingParen(src: string, start: number): number {
  let depth = 1;
  for (let i = start; i < src.length; i++) {
    const ch = src[i];
    if (ch === '(') depth++;
    else if (ch === ')' && --depth === 0) return i;
  }
  return -1;
}

/** Index of the first top-level comma in src[start, end), or -1. */
function topLevelComma(src: string, start: number, end: number): number {
  let depth = 0;
  for (let i = start; i < end; i++) {
    const ch = src[i];
    if (ch === '(' || ch === '[' || ch === '<') depth++;
    else if (ch === ')' || ch === ']' || ch === '>') depth--;
    else if (ch === ',' && depth === 0) return i;
  }
  return -1;
}

/**
 * The direct-present variant of a catalog shader, or null when it cannot be
 * built safely (no binding-2 rgba storage declaration, or a store call the
 * parser does not understand).
 */
export function toDirectPresentVariant(wgsl: string): string | null {
  const decl = BINDING2_RE.exec(wgsl);
  if (!decl) return null;
  const name = decl[2];
  if (!name) return null;
  let out = wgsl.replace(BINDING2_RE, `$1texture_storage_2d<${DIRECT_PRESENT_FORMAT}, write>`);

  const call = new RegExp(`\\btextureStore\\s*\\(\\s*${name}\\s*,`, 'g');
  let result = '';
  let last = 0;
  let stores = 0;
  for (let m = call.exec(out); m; m = call.exec(out)) {
    const argsStart = m.index + m[0].length;
    const close = closingParen(out, out.lastIndexOf('(', argsStart) + 1);
    if (close < 0) return null;
    const comma = topLevelComma(out, argsStart, close);
    if (comma < 0) return null;
    const value = out.slice(comma + 1, close).trim();
    if (!value) return null;
    result += `${out.slice(last, comma + 1)} px_direct_present_encode(${value})`;
    last = close;
    call.lastIndex = close;
    stores++;
  }
  if (stores === 0) return null;
  out = result + out.slice(last);
  return `${out}\n${ENCODE_FN}`;
}

export interface DirectPresentInputs {
  /** Swapchain is bgra8unorm with STORAGE_BINDING (probe accepted, not the HDR canvas). */
  storageReady: boolean;
  enabled: boolean;
  plan: FrameSlotDispatchPlan;
  scaledW: number;
  scaledH: number;
  canvasW: number;
  canvasH: number;
  inputSource: string;
  /** A capture needs the working texture written this frame. */
  captureHold: boolean;
}

export type DirectPresentIneligible =
  | 'storage-unavailable'
  | 'disabled'
  | 'not-single-pass'
  | 'composited'
  | 'resampled'
  | 'generative-flip'
  | 'history-ring'
  | 'capture';

/** Why this frame cannot present directly, or null when it can. */
export function directPresentBlocker(input: DirectPresentInputs): DirectPresentIneligible | null {
  if (!input.storageReady) return 'storage-unavailable';
  if (!input.enabled) return 'disabled';
  const { plan } = input;
  const only = plan.chained[0];
  if (plan.enabledCount !== 1 || plan.parallel.length > 0 || !only) return 'not-single-pass';
  if (only.program.kind !== 'chain' || only.program.shaderIds.length !== 1) return 'not-single-pass';
  if (!isPassThroughLayer(only.slot.layer)) return 'composited';
  if (input.scaledW !== input.canvasW || input.scaledH !== input.canvasH) return 'resampled';
  if (input.inputSource === 'generative') return 'generative-flip';
  if (plan.anyUsesHistory) return 'history-ring';
  if (input.captureHold) return 'capture';
  return null;
}

/** Swaps the final compute op's pipeline + bind group for the direct variant (frame-plan hook). */
export interface DirectPresentFrame {
  shaderId: string;
  pipeline: GPUComputePipeline;
  bindGroup: GPUBindGroup;
  override(op: ComputeOp): { pipeline: GPUComputePipeline; bindGroup: GPUBindGroup } | null;
}

export function makeDirectPresentFrame(
  shaderId: string,
  pipeline: GPUComputePipeline,
  bindGroup: GPUBindGroup,
): DirectPresentFrame {
  return {
    shaderId,
    pipeline,
    bindGroup,
    override: (op) => (op.entry === shaderId ? { pipeline, bindGroup } : null),
  };
}
