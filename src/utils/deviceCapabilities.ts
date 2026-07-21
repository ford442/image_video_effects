/**
 * Device capability helpers for VJ Studio UI gating.
 */

/** True on phones/tablets — coarse pointer and no hover (touch-primary). */
export function isMobileTouchDevice(): boolean {
  if (typeof window === 'undefined') return false;
  return Boolean(window.matchMedia && window.matchMedia('(pointer: coarse)') && window.matchMedia('(pointer: coarse)').matches)
    || Boolean(window.matchMedia && window.matchMedia('(max-width: 768px)') && window.matchMedia('(max-width: 768px)').matches);
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
