import { STORAGE_API_URL } from '../config/appConfig';
import { resolveShaderUrl } from './resolveShaderUrl';

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
 * Order:
 * 1. Caller-provided URL (absolute or resolved)
 * 2. Same-origin public/shaders copy (local dev + full app deploys)
 * 3. Static CDN base (test.1ink.us)
 * 4. Storage manager API (/api/shaders/{id}/code)
 */
export async function fetchShaderWgsl(id: string, url?: string): Promise<string | null> {
  const candidates: string[] = [
    `./shaders/${id}.wgsl`,
  ];

  if (url) {
    candidates.push(url);
    if (!/^https?:\/\//i.test(url)) {
      candidates.push(resolveShaderUrl(url));
    }
  } else {
    candidates.push(resolveShaderUrl(`shaders/${id}.wgsl`));
  }

  candidates.push(`${STORAGE_API_URL}/api/shaders/${id}/code`);

  const seen = new Set<string>();
  for (const candidate of candidates) {
    if (!candidate || seen.has(candidate)) continue;
    seen.add(candidate);
    const wgsl = await tryFetchWgsl(candidate);
    if (wgsl) return wgsl;
  }

  return null;
}
