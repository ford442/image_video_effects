/**
 * Host-side WGSL storage format rewrite for non-ultra tiers.
 * Shaders stay authored as rgba32float; bindings 2/7/8 are rewritten at compile.
 */

import type { InternalColorFormat } from '../config/formatPolicy';

const RGBA32_STORAGE_RE =
  /texture_storage_2d\s*<\s*rgba32float\s*,\s*write\s*>/g;

export function rewriteWgslStorageFormats(
  wgsl: string,
  colorFormat: InternalColorFormat,
): string {
  if (colorFormat === 'rgba32float') {
    return wgsl;
  }
  return wgsl.replace(RGBA32_STORAGE_RE, `texture_storage_2d<${colorFormat}, write>`);
}

export function pipelineCacheKey(wgsl: string, colorFormat: InternalColorFormat): string {
  return `${colorFormat}:${wgsl.length}:${wgsl}`;
}
