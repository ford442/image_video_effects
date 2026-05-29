import { SHADER_FILES_BASE_URL } from '../config/appConfig';

/**
 * Resolve a shader URL against the configured shader files base URL.
 *
 * - Absolute URLs (http:// or https://) are returned as-is.
 * - Relative URLs like `shaders/xxx.wgsl` or `./shaders/xxx.wgsl` are
 *   resolved against SHADER_FILES_BASE_URL.
 *
 * This makes it easy to switch shader hosting between local dev, VPS, and
 * static CDN without touching the JSON list files.
 */
export function resolveShaderUrl(url: string): string {
  if (!url) return url;

  // Already absolute — leave it alone
  if (/^https?:\/\//.test(url)) {
    return url;
  }

  // Normalize base URL (ensure no trailing slash)
  const base = SHADER_FILES_BASE_URL.replace(/\/$/, '');

  // Normalize path (strip leading ./ or /)
  const path = url.replace(/^\.?\//, '');

  return `${base}/${path}`;
}
