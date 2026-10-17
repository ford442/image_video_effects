/**
 * Small non-cryptographic hashing for WGSL cache keys. Pipelines used to be
 * keyed by the full source text, which kept every compiled shader's source
 * alive in the cache maps for the whole session.
 */

const FNV_PRIME = 0x01000193;
const FNV_OFFSET_BASIS = 0x811c9dc5;
/** Second, independent offset basis so a collision needs both 32-bit hashes to agree. */
const FNV_OFFSET_BASIS_ALT = 0x9747b28c;

/** 32-bit FNV-1a over the UTF-16 code units of `text`. */
export function fnv1a32(text: string, offsetBasis: number = FNV_OFFSET_BASIS): number {
  let hash = offsetBasis >>> 0;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, FNV_PRIME) >>> 0;
  }
  return hash;
}

/** 64 bits of FNV-1a (two seeds) as 16 hex characters. */
export function hashWgslSource(wgsl: string): string {
  const hi = fnv1a32(wgsl, FNV_OFFSET_BASIS).toString(16).padStart(8, '0');
  const lo = fnv1a32(wgsl, FNV_OFFSET_BASIS_ALT).toString(16).padStart(8, '0');
  return hi + lo;
}
