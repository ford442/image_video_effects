/**
 * Host-side WGSL storage format rewrite so bind-group layout and shader agree.
 * Shaders stay authored as rgba32float; write-only rgba storage decls are forced
 * onto the allocated tier format at compile (16→32 or 32→16).
 *
 * Fail-soft contract: a storage declaration the rewrite cannot reach (unusual spelling,
 * a format we do not tier, a generated variant) would make the pipeline's storage format
 * disagree with the texture the host actually allocated — a hard pipeline-creation error.
 * `rewriteWgslStorageFormatsChecked` reports those so the caller can skip that slot
 * instead of submitting an invalid pipeline.
 */

import type { InternalColorFormat } from '../config/formatPolicy';

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
  return rewriteWgslStorageFormatsChecked(wgsl, colorFormat).wgsl;
}

/** Rewrite + report declarations the rewrite could not bring onto the tier format. */
export function rewriteWgslStorageFormatsChecked(
  wgsl: string,
  colorFormat: InternalColorFormat,
): FormatRewriteResult {
  let rewritten = 0;
  const missed: string[] = [];
  const re = /texture_storage_2d\s*<\s*(rgba\w+)\s*,\s*(read_write|write|read)\s*>/g;
  const out = wgsl.replace(re, (full, fmt: string, access: string) => {
    if (access !== 'write') {
      if (fmt !== colorFormat) missed.push(full);
      return full;
    }
    if (fmt === colorFormat) return full;
    rewritten += 1;
    return `texture_storage_2d<${colorFormat}, write>`;
  });
  return { wgsl: out, rewritten, missed };
}

export function pipelineCacheKey(wgsl: string, colorFormat: InternalColorFormat): string {
  return `${colorFormat}:${wgsl.length}:${wgsl}`;
}
