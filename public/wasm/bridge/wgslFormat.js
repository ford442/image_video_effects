// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

const RGBA32_STORAGE_RE = /texture_storage_2d\s*<\s*rgba32float\s*,\s*write\s*>/g;
function rewriteWgslStorageFormats(wgsl, colorFormatWasm) {
  if (colorFormatWasm === 0) return wgsl;
  return wgsl.replace(RGBA32_STORAGE_RE, "texture_storage_2d<rgba16float, write>");
}
export {
  rewriteWgslStorageFormats
};
