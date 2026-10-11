/**
 * webmColour.ts — tag a finished WebM with wide-gamut colour primaries.
 *
 * webm-muxer writes the Matroska Colour element from the first chunk's
 * `decoderConfig.colorSpace`, and its lookup tables have no SMPTE EG 432-1
 * (Display P3) entry. Chromium's encoder also reports smpte170m for every
 * input, so a P3 canvas frame would be labelled SMPTE 170M and play back
 * desaturated. The element is fixed-size (four 1-byte uint children), so the
 * two values can be rewritten in place after finalize without moving any byte.
 */

/** Matroska Colour (0x55B0) children and the ITU-T H.273 values this file writes. */
const ID_COLOUR = 0x55b0;
const ID_TRANSFER = 0x55ba;
const ID_PRIMARIES = 0x55bb;

/** H.273 colour primaries 12 (SMPTE EG 432-1 / Display P3, D65). */
export const CICP_PRIMARIES_DISPLAY_P3 = 12;
/** H.273 transfer 13 (IEC 61966-2-1 sRGB curve — what a display-p3 canvas encodes). */
export const CICP_TRANSFER_SRGB = 13;

export type WebmColourTag = 'display-p3' | 'encoder-default';

/** Only the header area precedes the first Cluster; the Colour element sits in Tracks. */
const SCAN_BYTES = 128 * 1024;

/** Read an EBML size vint (1–8 bytes) at `at`; null when malformed. */
function readVint(bytes: Uint8Array, at: number): { value: number; length: number } | null {
  const first = bytes[at];
  if (first === undefined || first === 0) return null;
  const length = Math.clz32(first) - 23;
  if (length < 1 || length > 8 || at + length > bytes.length) return null;
  let value = first & (0xff >> length);
  for (let i = 1; i < length; i++) value = value * 256 + (bytes[at + i] ?? 0);
  return { value, length };
}

/**
 * Rewrite Primaries/Transfer inside the first Colour element to Display P3.
 * Returns false (buffer untouched) when the element is not found or is not the
 * 1-byte-uint layout, so callers can report the take as not tagged.
 */
export function tagWebmDisplayP3(buffer: ArrayBuffer): boolean {
  const bytes = new Uint8Array(buffer);
  const end = Math.min(bytes.length - 2, SCAN_BYTES);
  for (let i = 0; i < end; i++) {
    if (bytes[i] !== ID_COLOUR >> 8 || bytes[i + 1] !== (ID_COLOUR & 0xff)) continue;
    const size = readVint(bytes, i + 2);
    if (!size) continue;
    const bodyStart = i + 2 + size.length;
    const bodyEnd = bodyStart + size.value;
    if (bodyEnd > bytes.length) continue;

    let primariesAt = -1;
    let transferAt = -1;
    let p = bodyStart;
    while (p + 4 <= bodyEnd) {
      const id = ((bytes[p] ?? 0) << 8) | (bytes[p + 1] ?? 0);
      const childSize = readVint(bytes, p + 2);
      if (!childSize || childSize.length !== 1 || childSize.value !== 1) break;
      if (id === ID_PRIMARIES) primariesAt = p + 3;
      else if (id === ID_TRANSFER) transferAt = p + 3;
      p += 2 + 1 + 1;
    }
    if (primariesAt < 0 || transferAt < 0) return false;
    bytes[primariesAt] = CICP_PRIMARIES_DISPLAY_P3;
    bytes[transferAt] = CICP_TRANSFER_SRGB;
    return true;
  }
  return false;
}
