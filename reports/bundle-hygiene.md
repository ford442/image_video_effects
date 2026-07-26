# Bundle hygiene report (#1010)

**Date:** 2026-07-26

## Summary

Foundation hygiene split heavy ML, HLS, Live Studio, and AutoDJ runtime out of the initial `main` chunk. Initial route JS dropped from **~2.66 MB gzip** to **~256 KB gzip** while deferred chunks load on feature activation.

## JS bundle sizes (gzip / raw)

| Chunk | Before (gzip) | After (gzip) | After (raw) | Load trigger |
|-------|---------------|--------------|-------------|--------------|
| `main.*.js` | ~2.66 MB | **256.36 KB** | ~850 KB | Initial route |
| `transformers.*.chunk.js` | (in main or split) | 179.99 KB | — | Depth model / AI captioner |
| `web-llm.*.chunk.js` | (in main or split) | 2.14 MB | — | AI VJ LLM init |
| `hls.*.chunk.js` | (in main) | 159.63 KB | — | HLS live stream URL |
| `auto-dj.*.chunk.js` | — | 7.08 KB | — | AI VJ toggle |
| `live-studio.*.chunk.js` | — | 6.71 KB | — | Live Studio tab |

**Before** baseline from [`reports/transformers-migration.md`](transformers-migration.md) (CRA production build, clean tree).

**After** from `SKIP_WASM_BUILD=1 npm run build` on this branch (CRA file-size table + `gzip -9` on `build/static/js/*.js`).

## Changes

1. **Types split** — [`src/types/aiVj.ts`](src/types/aiVj.ts); main bundle no longer pulls [`AutoDJ.ts`](src/AutoDJ.ts) for `ImageRecord` / `AIStatus` types.
2. **Dynamic AutoDJ** — [`useAiVjHandlers`](src/hooks/useAiVjHandlers.ts) `import()` with `webpackChunkName: "auto-dj"`.
3. **Dynamic HLS** — [`LiveStreamBridge`](src/components/LiveStreamBridge.tsx), [`HLSVideoSource`](src/components/HLSVideoSource.tsx).
4. **Lazy Live Studio** — `React.lazy` + `Suspense` in [`AppShell`](src/components/app/AppShell.tsx).
5. **`package.json`** — removed duplicate prod deps; `build` = `craco build` only (`wasm:build` once in `prebuild`).
6. **TypeScript 5.4.5** — devDependency; minimal WebGPU / `Float16Array` compatibility fixes.
7. **Repo hygiene** — removed root `a.out.js`, `patch*.diff`; `.gitignore` for emcc accidents.

## `npm audit --omit=dev`

4 **high** (transitive, no fix available):

| Package | Chain | Notes |
|---------|-------|-------|
| `adm-zip` | `onnxruntime-node` → `@huggingface/transformers` | Node-only ORT path; stubbed `onnxruntime-node$ → false` in webpack |
| `sharp` | `@huggingface/transformers` | Node-only; stubbed `sharp$ → false` in webpack |

Runtime browser path uses `onnxruntime-web` WASM fetched at model load — not reflected as a fixable npm audit item. Residual risk documented; upgrade path is Hugging Face transformers releases that drop or update these optional Node deps.

## Verification

| Check | Result |
|-------|--------|
| `npm test -- --watchAll=false --ci` | 395 passed |
| `SKIP_WASM_BUILD=1 npm run build` | PASS |
| `npm run wasm:validate` | PASS |
| `npx tsc --noEmit` | PASS |
| `npm run test:depth:cpu` | PASS (CPU smoke) |

## CRA warning

CRA still warns "bundle significantly larger than recommended" because **`web-llm.*.chunk.js` (~2.14 MB gzip)** is the largest single file — expected for Gemma weights loader. It is **not** in the initial route payload.
