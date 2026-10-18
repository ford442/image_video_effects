import type { Plugin } from 'vite';

// static/js/<name>.<hash>[.chunk].js and static/css/<name>.<hash>.css
const HASHED = /^static\/(?:js|css)\/(.+?)\.[0-9a-f]{8}(?:\.chunk)?\.(js|css)$/;

/**
 * Emits `asset-manifest.json` in the CRA shape (`files`, `entrypoints`) so
 * `scripts/check-bundle-size.mjs` and the deploy tooling keep working unchanged.
 * Keys are `<chunk name>.js` / `<chunk name>.css`, where the chunk name comes from
 * the file name (so `webpackChunkName` comments, see chunkNamePlugin, carry through);
 * the entry chunk is `main` and worker scripts are `<x>-worker` (`render.worker.ts`
 * -> `render-worker.js`).
 */
export function assetManifestPlugin(): Plugin {
  return {
    name: 'pixelocity:asset-manifest',
    apply: 'build',
    generateBundle(_options, bundle) {
      const files: Record<string, string> = {};
      const entrypoints: string[] = [];
      for (const [fileName, item] of Object.entries(bundle)) {
        const m = HASHED.exec(fileName);
        if (!m) continue;
        const name = m[1]!.replace(/\.worker$/, '-worker');
        files[`${name}.${m[2]}`] = fileName;
        if (item.type === 'chunk' && item.isEntry) entrypoints.push(fileName);
        // The entry stylesheet is what index.html links.
        if (fileName.endsWith('.css') && name === 'main') entrypoints.push(fileName);
      }
      this.emitFile({
        type: 'asset',
        fileName: 'asset-manifest.json',
        source: JSON.stringify({ files, entrypoints }, null, 2),
      });
    },
  };
}
