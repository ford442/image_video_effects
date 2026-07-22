import { STORAGE_API_URL } from '../config/appConfig';
import { resolveShaderUrl } from './resolveShaderUrl';

export interface FetchShaderWgslOptions {
  /**
   * When true, only try the caller-provided URL (plus a same-origin
   * `./shaders/{id}.wgsl` probe). Skips CDN / storage API fallbacks.
   * Use for optional assets such as `-sg.wgsl` subgroup variants so a
   * missing file does not cascade into remote 404 spam.
   */
  primaryOnly?: boolean;
}

async function tryFetchWgsl(url: string): Promise<string | null> {
  try {
    const response = await fetch(url);
    if (!response.ok) return null;

    const contentType = response.headers.get('content-type') || '';
    if (contentType.includes('application/json')) {
      const data = await response.json() as { code?: string };
      return typeof data.code === 'string' ? data.code : null;
    }

    const text = await response.text();
    return text.trim().length > 0 ? text : null;
  } catch {
    return null;
  }
}

/**
 * Fetch WGSL source for a shader, trying several hosting locations.
 *
 * Order (full cascade):
 * 1. Same-origin public/shaders copy (local dev + full app deploys)
 * 2. Caller-provided URL (absolute or resolved)
 * 3. Static CDN base (test.1ink.us) via resolveShaderUrl
 * 4. Storage manager API (/api/shaders/{id}/code)
 *
 * With `primaryOnly: true`, only steps 1–2 run (no remote fallbacks).
 */
export async function fetchShaderWgsl(
  id: string,
  url?: string,
  options?: FetchShaderWgslOptions,
): Promise<string | null> {
  const candidates: string[] = [
    `./shaders/${id}.wgsl`,
  ];

  if (url) {
    candidates.push(url);
    if (!options?.primaryOnly && !/^https?:\/\//i.test(url)) {
      candidates.push(resolveShaderUrl(url));
    }
  } else if (!options?.primaryOnly) {
    candidates.push(resolveShaderUrl(`shaders/${id}.wgsl`));
  }

  if (!options?.primaryOnly) {
    candidates.push(`${STORAGE_API_URL}/api/shaders/${id}/code`);
  }

  const seen = new Set<string>();
  for (const candidate of candidates) {
    if (!candidate || seen.has(candidate)) continue;
    seen.add(candidate);
    const wgsl = await tryFetchWgsl(candidate);
    if (wgsl) return wgsl;
  }

  return null;
}
