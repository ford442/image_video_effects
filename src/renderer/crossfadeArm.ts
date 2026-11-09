/**
 * crossfadeArm.ts
 *
 * Page-side policy for the live cue crossfade (webgpu/presentHold.ts does the
 * pixels). A cue is *armed* with its duration and fires once, on the first call
 * that changes what a slot renders — shader id, slot enabled, chained/parallel
 * mode. A slider move never fires it, so param-only cues keep lerping and never
 * allocate a hold. Firing sends the single `startCrossfade` command; a duration
 * of 0 never arms (today's hard cut), and WASM / Canvas2D never arm at all.
 */

import type { SlotMode } from './webgpu/webgpuConstants';

/** How long an armed cue waits for its shader stack to land (loads are async). */
export const CROSSFADE_ARM_WINDOW_MS = 8000;

export interface SlotIdentity {
  shaderId: string | null;
  enabled: boolean;
  mode: SlotMode;
}

/** True when `after` renders something other than `before`: id, enabled or mode. */
export function slotIdentityChanged(
  before: SlotIdentity | null,
  after: { shaderId: string | null; enabled: boolean; mode?: SlotMode },
): boolean {
  const beforeId = before?.shaderId ?? null;
  const beforeEnabled = !!before?.enabled && beforeId !== null;
  const afterEnabled = after.enabled && after.shaderId !== null;
  if (beforeEnabled !== afterEnabled) return true;
  // A disabled slot renders nothing, so its leftover id or mode is not a change.
  if (!afterEnabled) return false;
  if (beforeId !== after.shaderId) return true;
  return after.mode !== undefined && (before?.mode ?? 'chained') !== after.mode;
}

export class CrossfadeArm {
  private armed: { durationMs: number; expiresAt: number } | null = null;

  /** Wait for the next stack change; false (and disarmed) for a duration that is a hard cut. */
  arm(durationMs: number, nowMs: number, windowMs = CROSSFADE_ARM_WINDOW_MS): boolean {
    if (!Number.isFinite(durationMs) || durationMs <= 0) {
      this.armed = null;
      return false;
    }
    this.armed = { durationMs, expiresAt: nowMs + windowMs };
    return true;
  }

  disarm(): void {
    this.armed = null;
  }

  get isArmed(): boolean {
    return this.armed !== null;
  }

  /** Consume the arm: the duration to fire with, or null (nothing armed, or it expired). */
  take(nowMs: number): number | null {
    const armed = this.armed;
    this.armed = null;
    if (!armed || nowMs > armed.expiresAt) return null;
    return armed.durationMs;
  }
}
