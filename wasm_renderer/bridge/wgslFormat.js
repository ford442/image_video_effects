// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

function rewriteWgslStorageFormats(wgsl, colorFormatWasm) {
  const colorFormat = colorFormatWasm === 1 ? "rgba16float" : "rgba32float";
  const re = /texture_storage_2d\s*<\s*(rgba\w+)\s*,\s*(read_write|write|read)\s*>/g;
  return wgsl.replace(re, (full, fmt, access) => {
    if (access !== "write" || fmt === colorFormat) return full;
    return `texture_storage_2d<${colorFormat}, write>`;
  });
}
export {
  rewriteWgslStorageFormats
};
