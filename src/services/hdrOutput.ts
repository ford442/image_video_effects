/**
 * hdrOutput.ts
 *
 * The final tonemap of the HDR canvas (#1512 Part A): when extended tone
 * mapping is negotiated the canvas is rgba16float / display-p3 and the present
 * pass maps working-space linear light to it with two user settings:
 *
 *   paper white  nits the working-space 1.0 is shown at
 *   peak         nits highlights roll off toward (the display's headroom)
 *
 * Canvas value 1.0 is the display's SDR white, which browsers take as the
 * BT.2408 reference white (203 nits), so both settings are divided by it.
 * Persisted per browser (localStorage) and in project files (render.hdr).
 */

import canvasConfigureContract from '../contracts/canvas_configure.json';

export interface HdrToneMapSettings {
  paperWhiteNits: number;
  peakNits: number;
}

const HDR = canvasConfigureContract.hdrToneMap;

export const SDR_REFERENCE_WHITE_NITS: number = HDR.sdrReferenceWhiteNits;

export const DEFAULT_HDR_TONE_MAP: HdrToneMapSettings = {
  paperWhiteNits: HDR.paperWhiteNitsDefault,
  peakNits: HDR.peakNitsDefault,
};

export const HDR_NITS_LIMITS = { min: HDR.nitsRange[0] ?? 80, max: HDR.nitsRange[1] ?? 10000 };

function clampNits(value: unknown, fallback: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return fallback;
  return Math.min(HDR_NITS_LIMITS.max, Math.max(HDR_NITS_LIMITS.min, value));
}

/** Clamp to the contract range; peak never below paper white. */
export function normalizeHdrToneMap(raw: Partial<HdrToneMapSettings> | null | undefined): HdrToneMapSettings {
  const paperWhiteNits = clampNits(raw?.paperWhiteNits, DEFAULT_HDR_TONE_MAP.paperWhiteNits);
  const peakNits = Math.max(paperWhiteNits, clampNits(raw?.peakNits, DEFAULT_HDR_TONE_MAP.peakNits));
  return { paperWhiteNits, peakNits };
}

/**
 * The HDR present pass's uniform (vec4<f32>): x exposure (paper white ÷ SDR
 * white), y headroom (peak ÷ SDR white, canvas units), zw unused.
 */
export function hdrToneMapUniform(settings: HdrToneMapSettings): Float32Array<ArrayBuffer> {
  const s = normalizeHdrToneMap(settings);
  return new Float32Array([s.paperWhiteNits / SDR_REFERENCE_WHITE_NITS, s.peakNits / SDR_REFERENCE_WHITE_NITS, 0, 0]);
}

export function loadHdrToneMap(): HdrToneMapSettings {
  if (typeof localStorage === 'undefined') return { ...DEFAULT_HDR_TONE_MAP };
  try {
    const raw = localStorage.getItem(HDR.storageKey);
    return normalizeHdrToneMap(raw ? (JSON.parse(raw) as Partial<HdrToneMapSettings>) : null);
  } catch {
    return { ...DEFAULT_HDR_TONE_MAP };
  }
}

export function saveHdrToneMap(settings: HdrToneMapSettings): void {
  if (typeof localStorage === 'undefined') return;
  try {
    localStorage.setItem(HDR.storageKey, JSON.stringify(normalizeHdrToneMap(settings)));
  } catch {
    // ignore quota / privacy errors
  }
}
