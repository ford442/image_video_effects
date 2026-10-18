# Frontend toolchain decision

**Status: Vite 6 + Vitest 3 + ESLint 9 + TypeScript 5.9** (#1343 Phase 2). Replaces Create React App 5 / CRACO 7 / Jest 27.

Parent: [#965](https://github.com/ford442/image_video_effects/issues/965) · Epic: [#1076](https://github.com/ford442/image_video_effects/issues/1076) · Toolchain hygiene: [#1083](https://github.com/ford442/image_video_effects/issues/1083) · Migration: #1343

## Current stack

| Piece | Version / tool | Notes |
|-------|----------------|-------|
| Bundler / dev server | Vite 6 (`@vitejs/plugin-react`) | `vite.config.ts`; output stays in `build/` with CRA's `static/js|css` layout |
| Unit tests | Vitest 3 (jsdom) | `test` block in `vite.config.ts`; `globals: true`, `mockReset: true` (CRA's `resetMocks`) |
| Lint | ESLint 9 flat config + typescript-eslint 8 | `eslint.config.mjs`; `no-floating-promises` is an error; `--max-warnings` ratchet in `package.json` |
| TypeScript | 5.9 (`~5.9.3`) | `moduleResolution: bundler`, `noImplicitOverride`, `noUnusedLocals/Parameters`; `tests/tsconfig.json` type-checks the Playwright specs |
| React | 19.1 | |
| WebGPU types | `@webgpu/types` | dev dependency |
| Node | 24 (`.nvmrc`, `engines`) | |

## What replaced the CRACO overrides

| Old (`craco.config.js`) | Now |
|-------------------------|-----|
| `import.meta` shim loader for transformers.js | Not needed — Vite handles `import.meta` natively |
| `extensionAlias` `.js` → `.ts` and the Jest `moduleNameMapper` | Vite/Vitest resolve `.js` specifiers to `.ts` importers |
| `sharp$` / `onnxruntime-node$` → `false` | Both are only reachable through transformers.js's node entry; the browser build never loads them |
| `topLevelAwait` experiment | `build.target: es2022` |
| `devServer.headers` (COOP/COEP) | `server.headers` and `preview.headers` |
| `__webpack_public_path__` re-anchoring in workers | ES module workers; chunks resolve against the worker URL |
| `process.env.REACT_APP_*` | Inlined through `define` (same variable names) |
| `asset-manifest.json` | `scripts/vite/assetManifestPlugin.ts` emits the CRA shape |
| `webpackChunkName` comments | `scripts/vite/chunkNamePlugin.ts` keeps them as chunk file names |
| `patches/react-dev-utils` (Node 24 `fs.F_OK`) | Gone with `react-scripts` |

## Dependency boundaries

- `@huggingface/transformers` and `@mlc-ai/web-llm` must be dynamically imported only through their loader modules — enforced by `npm run verify:dependency-boundaries`.
- `scripts/vite/ortWasmPlugin.ts` stops Vite from copying onnxruntime-web's 27 MB wasm into the build (transformers.js loads it from jsDelivr at runtime).

Run `npm run verify:toolchain-foundation` before merge (it reports every failing gate, not just the first).
