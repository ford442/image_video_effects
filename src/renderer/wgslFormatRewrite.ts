/**
 * Host-side WGSL storage format rewrite for non-ultra tiers.
 * Shaders stay authored as rgba32float; bindings 2/7/8 are rewritten at compile.
 *
 * Fail-soft contract: a storage declaration the rewrite cannot reach (unusual spelling,
 * a format we do not tier, a generated variant) would make the pipeline's storage format
 * disagree with the texture the host actually allocated — a hard pipeline-creation error.
 * `rewriteWgslStorageFormatsChecked` reports those so the caller can fall back to FP32
 * for that shader instead of failing to compile it.
 */

import type { InternalColorFormat } from '../config/formatPolicy';

const RGBA32_STORAGE_RE =
  /texture_storage_2d\s*<\s*rgba32float\s*,\s*write\s*>/g;

/** Any rgba* storage-texture declaration, whatever the format spelling. */
const ANY_RGBA_STORAGE_RE =
  /texture_storage_2d\s*<\s*(rgba\w+)\s*,\s*(read_write|write|read)\s*>/g;

export interface FormatRewriteResult {
  wgsl: string;
  /** Number of declarations rewritten to the tier format. */
  rewritten: number;
  /**
   * rgba storage declarations still not matching the tier format after the rewrite.
   * Non-empty means the pipeline would disagree with the allocated textures.
   */
  missed: string[];
}

export function rewriteWgslStorageFormats(
  wgsl: string,
  colorFormat: InternalColorFormat,
): string {
  if (colorFormat === 'rgba32float') {
    return wgsl;
  }
  return wgsl.replace(RGBA32_STORAGE_RE, `texture_storage_2d<${colorFormat}, write>`);
}

/** Rewrite + report declarations the rewrite could not bring onto the tier format. */
export function rewriteWgslStorageFormatsChecked(
  wgsl: string,
  colorFormat: InternalColorFormat,
): FormatRewriteResult {
  if (colorFormat === 'rgba32float') {
    return { wgsl, rewritten: 0, missed: [] };
  }

  const before = wgsl.match(RGBA32_STORAGE_RE)?.length ?? 0;
  const out = rewriteWgslStorageFormats(wgsl, colorFormat);

  const missed: string[] = [];
  for (const m of out.matchAll(ANY_RGBA_STORAGE_RE)) {
    if (m[1] !== colorFormat) {
      missed.push(m[0]);
    }
  }

  return { wgsl: out, rewritten: before, missed };
}

export function pipelineCacheKey(wgsl: string, colorFormat: InternalColorFormat): string {
  return `${colorFormat}:${wgsl.length}:${wgsl}`;
}
