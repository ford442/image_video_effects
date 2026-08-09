// src/wasm/bridge/wgslFormat.js
// WGSL storage format rewrite — keep in sync with src/renderer/wgslFormatRewrite.ts

const RGBA32_STORAGE_RE =
  /texture_storage_2d\s*<\s*rgba32float\s*,\s*write\s*>/g;

/**
 * @param {string} wgsl
 * @param {number} colorFormatWasm 0=rgba32float, 1=rgba16float
 */
export function rewriteWgslStorageFormats(wgsl, colorFormatWasm) {
  if (colorFormatWasm === 0) return wgsl;
  return wgsl.replace(RGBA32_STORAGE_RE, 'texture_storage_2d<rgba16float, write>');
}
