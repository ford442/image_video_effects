import type { Plugin } from 'vite';

const DYNAMIC_IMPORT_WITH_NAME =
  /import\(\s*\/\*\s*webpackChunkName:\s*["']([^"']+)["']\s*\*\/\s*["']([^"']+)["']\s*\)/g;

/**
 * Keeps the `/* webpackChunkName: "x" *\/` comments meaningful under Rollup: lazy
 * chunks are emitted as `static/js/x.<hash>.chunk.js`, the layout CRA produced and
 * that `verify:bundle-size`, the deploy checks and `.htaccess` caching rules expect.
 */
export function chunkNamePlugin() {
  const namesById = new Map<string, string>();
  const plugin: Plugin & {
    chunkName(chunk: { facadeModuleId: string | null; moduleIds: readonly string[] }): string | undefined;
  } = {
    name: 'pixelocity:chunk-names',
    async transform(code, id) {
      if (!code.includes('webpackChunkName')) return null;
      for (const match of code.matchAll(DYNAMIC_IMPORT_WITH_NAME)) {
        const [, chunk, specifier] = match;
        if (!chunk || !specifier) continue;
        const resolved = await this.resolve(specifier, id);
        if (resolved && !resolved.external) namesById.set(resolved.id, chunk);
      }
      return null;
    },
    chunkName({ facadeModuleId, moduleIds }) {
      if (facadeModuleId) return namesById.get(facadeModuleId);
      // A dynamic entry that shares modules with a chunk it lazy-loads itself (the
      // Graph Lab panel and its canvas) is emitted without a facade; name it after
      // its one named module.
      const named = [...new Set(moduleIds.map((id) => namesById.get(id)).filter((n): n is string => !!n))];
      return named.length === 1 ? named[0] : undefined;
    },
  };
  return plugin;
}
