/**
 * Host audio-param hold registry.
 *
 * The audio-reactive mapper modulates slot sliders every frame. When a human
 * (slider drag, MIDI CC, OSC, set playback) is driving a param, the mapper must
 * back off so it does not fight the performer. Holds are keyed by slot + param
 * key; releasing a hold records the performer's value as the new audio base so
 * modulation resumes around it instead of snapping back to shader defaults.
 *
 * Plain module singleton (no React) so panels, live-control dispatch and the
 * audio rAF loop can all share it without prop drilling.
 */

type Key = string;

const DEFAULT_TOUCH_MS = 600;

const held = new Set<Key>();
const touchedUntil = new Map<Key, number>();
const bases = new Map<Key, number>();

let now: () => number = () =>
  typeof performance !== 'undefined' && typeof performance.now === 'function' ? performance.now() : Date.now();

const keyOf = (slot: number, param: string): Key => `${slot}:${param}`;

/** Freeze audio on a param until {@link release} (pointer grab, MIDI learn). */
export function hold(slot: number, param: string): void {
  held.add(keyOf(slot, param));
}

/** End a hold; `value` (when finite) becomes the audio base for that param. */
export function release(slot: number, param: string, value?: number): void {
  const k = keyOf(slot, param);
  held.delete(k);
  if (typeof value === 'number' && Number.isFinite(value)) bases.set(k, value);
}

/**
 * Timed hold for sources with no release event (MIDI CC, OSC, playback).
 * Each call extends the hold; `value` becomes the base immediately so the
 * mapper picks up from it once the hold lapses.
 */
export function touch(slot: number, param: string, value?: number, ms = DEFAULT_TOUCH_MS): void {
  const k = keyOf(slot, param);
  touchedUntil.set(k, now() + ms);
  if (typeof value === 'number' && Number.isFinite(value)) bases.set(k, value);
}

export function isHeld(slot: number, param: string): boolean {
  const k = keyOf(slot, param);
  if (held.has(k)) return true;
  const until = touchedUntil.get(k);
  if (until === undefined) return false;
  if (now() < until) return true;
  touchedUntil.delete(k);
  return false;
}

/** Pointer / learn hold only (ignores timed touches) — "hands on this param". */
export function isGrabbed(slot: number, param: string): boolean {
  return held.has(keyOf(slot, param));
}

/** Performer-set base value for a param, if any. */
export function baseFor(slot: number, param: string): number | undefined {
  return bases.get(keyOf(slot, param));
}

/** Forget holds and bases for a slot (its shader changed). */
export function clearSlot(slot: number): void {
  const prefix = `${slot}:`;
  for (const k of Array.from(held)) if (k.startsWith(prefix)) held.delete(k);
  for (const k of Array.from(touchedUntil.keys())) if (k.startsWith(prefix)) touchedUntil.delete(k);
  for (const k of Array.from(bases.keys())) if (k.startsWith(prefix)) bases.delete(k);
}

/** Test helper: reset all state and optionally inject a clock. */
export function __resetAudioParamHold(clock?: () => number): void {
  held.clear();
  touchedUntil.clear();
  bases.clear();
  if (clock) now = clock;
}
