export function rewriteWgslStorageFormats(wgsl: string, colorFormatWasm: number): string {
  const colorFormat = colorFormatWasm === 1 ? 'rgba16float' : 'rgba32float';
  const re = /texture_storage_2d\s*<\s*(rgba\w+)\s*,\s*(read_write|write|read)\s*>/g;
  return wgsl.replace(re, (full, fmt: string, access: string) => {
    if (access !== 'write' || fmt === colorFormat) return full;
    return `texture_storage_2d<${colorFormat}, write>`;
  });
}
