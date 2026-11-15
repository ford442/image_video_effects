/**
 * calibrationKeys.ts — keyboard calibration, shared by the control panel and
 * keys forwarded from a stage window.
 *
 *   1–4 / Tab (Shift+Tab)  select a corner (TL, TR, BR, BL)
 *   arrows                 move it 1 output pixel (Shift ×10, Alt ×0.25)
 *   t                      next test pattern
 *   o                      outline on / off
 */

import { nudgeCorner, TEST_PATTERNS, type OutputConfig } from './outputConfig';

export interface CalibrationKeyState {
  config: OutputConfig;
  selected: number;
}

export interface KeyMods {
  shift?: boolean;
  alt?: boolean;
}

/** The new state, or null when the key means nothing to calibration. */
export function applyCalibrationKey(
  state: CalibrationKeyState,
  key: string,
  mods: KeyMods,
  outputSize: { width: number; height: number },
): CalibrationKeyState | null {
  const selected = ((state.selected % 4) + 4) % 4;
  if (key === 'Tab') return { ...state, selected: (selected + (mods.shift ? 3 : 1)) % 4 };
  if (key === '1' || key === '2' || key === '3' || key === '4') return { ...state, selected: Number(key) - 1 };
  if (key === 't' || key === 'T') {
    const i = TEST_PATTERNS.indexOf(state.config.testPattern);
    const next = TEST_PATTERNS[(i + 1) % TEST_PATTERNS.length] ?? 'none';
    return { ...state, config: { ...state.config, testPattern: next } };
  }
  if (key === 'o' || key === 'O') return { ...state, config: { ...state.config, outline: !state.config.outline } };
  const px = mods.shift ? 10 : mods.alt ? 0.25 : 1;
  const sx = px / Math.max(1, outputSize.width);
  const sy = px / Math.max(1, outputSize.height);
  const delta: Record<string, [number, number]> = {
    ArrowLeft: [-sx, 0],
    ArrowRight: [sx, 0],
    ArrowUp: [0, -sy],
    ArrowDown: [0, sy],
  };
  const d = delta[key];
  if (!d) return null;
  return { selected, config: nudgeCorner(state.config, selected, d[0], d[1]) };
}
