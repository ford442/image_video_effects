/**
 * Device capability helpers for VJ Studio UI gating.
 */

/** True on phones/tablets — coarse pointer and no hover (touch-primary). */
export function isMobileTouchDevice(): boolean {
  if (typeof window === 'undefined') return false;

  const matchMedia = typeof window.matchMedia === 'function'
    ? window.matchMedia.bind(window)
    : null;

  if (!matchMedia) return false;

  return matchMedia('(pointer: coarse)').matches
    || matchMedia('(max-width: 768px)').matches;
}

/** Web MIDI API availability (desktop browsers with MIDI hardware). */
export function supportsWebMidi(): boolean {
  if (typeof navigator === 'undefined') return false;
  return typeof (navigator as Navigator & { requestMIDIAccess?: unknown }).requestMIDIAccess === 'function';
}

/** Show MIDI controls when not on touch-primary mobile. */
export function shouldShowMidiControls(): boolean {
  return !isMobileTouchDevice() && supportsWebMidi();
}
