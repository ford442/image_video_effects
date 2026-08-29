const RGBA32_STORAGE_RE =
  /texture_storage_2d\s*<\s*rgba32float\s*,\s*write\s*>/g;

export function rewriteWgslStorageFormats(wgsl: string, colorFormatWasm: number): string {
  if (colorFormatWasm === 0) return wgsl;
  return wgsl.replace(RGBA32_STORAGE_RE, 'texture_storage_2d<rgba16float, write>');
}
