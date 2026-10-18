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
  const plugin: Plugin & { chunkName(facadeModuleId: string | null | undefined): string | undefined } = {
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
    chunkName(facadeModuleId) {
      return facadeModuleId ? namesById.get(facadeModuleId) : undefined;
    },
  };
  return plugin;
}
