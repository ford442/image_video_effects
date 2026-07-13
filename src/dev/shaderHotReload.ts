/**
 * Dev-only shader hot-reload for the WASM C++ path.
 * Polls `public/shaders/*.wgsl` for Last-Modified changes and calls reloadShader.
 *
 * Enable with: ?renderer=wasm&shaderHotReload=1
 */

type ReloadableRenderer = {
  reloadShader(id: string, url: string): Promise<boolean>;
  loadShader(id: string, url: string): Promise<boolean>;
};

const tracked = new Map<string, { url: string; version: string }>();

/** Register a shader URL for hot-reload polling. */
export function trackShaderForHotReload(id: string, url: string, version = ''): void {
  tracked.set(id, { url, version });
}

async function fetchVersion(url: string): Promise<string> {
  const res = await fetch(url, { method: 'HEAD', cache: 'no-store' });
  if (!res.ok) return '';
  return res.headers.get('last-modified') ?? res.headers.get('etag') ?? '';
}

/**
 * Poll tracked shaders and reload when files change on disk (via dev server).
 * Returns a cleanup function.
 */
export function attachShaderHotReload(renderer: ReloadableRenderer, intervalMs = 2000): () => void {
  console.log('[HotReload] Watching', tracked.size, 'shader(s) under public/shaders/');

  const timer = window.setInterval(async () => {
    for (const [id, info] of tracked) {
      try {
        const version = await fetchVersion(info.url);
        if (!version) continue;
        if (!info.version) {
          info.version = version;
          continue;
        }
        if (version !== info.version) {
          console.log(`[HotReload] ♻️  ${id} changed — reloading`);
          const ok = await renderer.reloadShader(id, info.url);
          if (ok) info.version = version;
        }
      } catch (err) {
        console.warn('[HotReload] poll failed for', id, err);
      }
    }
  }, intervalMs);

  return () => window.clearInterval(timer);
}

/** Wrap loadShader to auto-track URLs for hot reload. */
export function wrapLoadShaderForHotReload(
  renderer: ReloadableRenderer
): (id: string, url: string) => Promise<boolean> {
  return async (id: string, url: string) => {
    const version = await fetchVersion(url);
    trackShaderForHotReload(id, url, version);
    return renderer.loadShader(id, url);
  };
}
