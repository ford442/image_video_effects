import path from 'node:path';
import { loadEnv } from 'vite';
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { assetManifestPlugin } from './scripts/vite/assetManifestPlugin';
import { chunkNamePlugin } from './scripts/vite/chunkNamePlugin';
import { ortWasmPlugin } from './scripts/vite/ortWasmPlugin';

// App code reads `process.env.REACT_APP_*` (CRA heritage; also imported by tsx
// scripts and Playwright where import.meta.env does not exist). Inline them.
const KNOWN_APP_ENV = [
  'REACT_APP_API_BASE_URL',
  'REACT_APP_SHADER_BASE_URL',
  'REACT_APP_SHADER_FILES_BASE_URL',
  'REACT_APP_SHADER_FILES_URL',
  'REACT_APP_STATIC_NGINX_URL',
  'REACT_APP_STORAGE_API_URL',
  'REACT_APP_STORAGE_VPS_HOST',
  'REACT_APP_STORAGE_VPS_PORT',
  'REACT_APP_STORAGE_VPS_URL',
  'REACT_APP_VERSION',
];

// Same cross-origin isolation as production (build.sh .htaccess, #1314), so
// `npm start` / `vite preview` exercise the SharedArrayBuffer input ring of the render worker.
const ISOLATION_HEADERS = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'credentialless',
};

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), 'REACT_APP_');
  const define: Record<string, string> = {};
  for (const key of new Set([...KNOWN_APP_ENV, ...Object.keys(env)])) {
    const value = env[key] ?? process.env[key];
    // Vitest copies `process.env.*` defines onto the real process.env as strings,
    // turning an unset var into the truthy string "undefined". Node has a real
    // process.env there, so only the browser build needs the placeholder.
    if (value === undefined && mode === 'test') continue;
    define[`process.env.${key}`] = JSON.stringify(value) ?? 'undefined';
  }
  const chunkNames = chunkNamePlugin();

  return {
    base: './',
    envPrefix: ['VITE_', 'REACT_APP_'],
    define,
    plugins: [react(), chunkNames, ortWasmPlugin(), assetManifestPlugin()],
    server: { port: 3000, headers: ISOLATION_HEADERS },
    preview: { port: 3000, headers: ISOLATION_HEADERS },
    optimizeDeps: {
      // Heavy lazy packages with their own WASM/worker loading; keep them out of the prebundle.
      exclude: ['@huggingface/transformers', 'onnxruntime-web', '@mlc-ai/web-llm'],
    },
    worker: {
      format: 'es' as const,
      plugins: () => [ortWasmPlugin()],
      rollupOptions: {
        output: {
          entryFileNames: 'static/js/[name].[hash].js',
          chunkFileNames: 'static/js/[name].[hash].chunk.js',
          hashCharacters: 'hex' as const,
        },
      },
    },
    build: {
      outDir: 'build',
      emptyOutDir: true,
      target: 'es2022',
      sourcemap: true,
      rollupOptions: {
        input: { main: path.resolve(__dirname, 'index.html') },
        output: {
          hashCharacters: 'hex' as const,
          entryFileNames: 'static/js/[name].[hash].js',
          chunkFileNames: chunk =>
            `static/js/${chunkNames.chunkName(chunk) ?? '[name]'}.[hash].chunk.js`,
          assetFileNames: info => {
            const name = info.names[0] ?? '';
            if (name.endsWith('.css')) return 'static/css/[name].[hash][extname]';
            return 'static/media/[name].[hash][extname]';
          },
        },
      },
    },
    test: {
      globals: true,
      environment: 'jsdom',
      setupFiles: ['./src/setupTests.ts'],
      include: ['src/**/*.{test,spec}.{ts,tsx}'],
      css: false,
      // CRA ran Jest with resetMocks: true; keep that isolation.
      mockReset: true,
      coverage: { provider: 'v8', reporter: ['text-summary', 'lcov'], include: ['src/**'] },
    },
  };
});

