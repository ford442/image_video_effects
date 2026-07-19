# Frontend toolchain decision (July 2026)

**Status: stay on CRA + CRACO** — Vite spike deferred; no migration planned for Foundation Wave 2.

Parent: [#965](https://github.com/ford442/image_video_effects/issues/965)

## Current stack

| Piece | Version / tool | Notes |
|-------|----------------|-------|
| Bundler | Create React App 5 (`react-scripts`) | Webpack 5 under the hood |
| Override layer | `@craco/craco` 7 | Patches webpack without eject |
| React | 19.1 | Works with CRA 5 via overrides |
| TypeScript | 4.9.5 | `tsconfig` targets ES2020 |
| WebGPU types | `@webgpu/types` 0.1.64 | Dev-time only |

## Why CRACO exists (`craco.config.js`)

CRA’s default webpack config is insufficient for this repo. CRACO patches:

1. **`fullySpecified: false` for `.m?js`** — ESM packages (e.g. `@huggingface/transformers`) omit `.js` extensions; webpack 5 strict resolution breaks without this.
2. **`import.meta` shim for `@xenova/transformers`** — Custom loader (`scripts/webpack-import-meta-shim-loader.js`) runs before webpack parses the package; transformers assumes Vite/Node ESM.
3. **`topLevelAwait` + `dynamicImport` output env** — Required for async WASM / dynamic `import()` in the app and ML paths.
4. **`sharp$` and `onnxruntime-node$` → `false`** — Stub Node-only optional deps so browser bundle does not pull native binaries.
5. **`ignoreWarnings`** — Source-map and `import.meta` parse noise from third-party ML packages.

Without CRACO, `npm start` / `npm run build` fail on transformers import resolution and optional native modules.

## Pain points (documented, not blocking)

- **TypeScript 4.9** while runtime targets ES2020 — newer TS features need a major bump tied to `react-scripts` / `@types` refresh.
- **CRACO patch surface** — every new ESM-heavy dependency may need another webpack rule.
- **Slow HMR / opaque webpack** — large shader catalog + ML chunks; hard to tune without ejecting.
- **`prestart` / `prebuild`** — shader list generation and manifest steps add startup latency (independent of bundler choice).

## Vite spike scope (not executed)

A dev-only Vite + React 19 + `@webgpu/types` spike would validate:

- Native `import.meta` and faster cold start for `src/`
- Whether `@huggingface/transformers` works without the custom loader
- HMR on `WebGPURenderer` modular files

**Out of scope for spike:** WASM `public/` copy path, CRA Jest config, Playwright production build (still `craco build`), deploy scripts.

**Estimated integration cost:** New `vite.config.ts`, dual `index.html` entry, Jest either kept on CRA or migrated to Vitest, CI `build` job unchanged until cutover.

## Decision

| Option | Verdict |
|--------|---------|
| **Stay CRA + CRACO** | ✅ **Chosen** — lowest risk; foundation work (#965) does not depend on bundler migration |
| Migrate to Vite | Defer until a dedicated tooling sprint; revisit after TS 5.x + test runner plan |
| Hybrid (Vite dev / CRA prod) | Rejected — two configs diverge quickly; only worth it if HMR pain blocks daily dev |

## Revisit triggers

- `react-scripts` security EOL or unfixable webpack conflict
- Second CRACO shim for a major dependency
- Team commits to Vitest + Vite as a standalone epic

## Related docs

- `craco.config.js` — live CRACO overrides
- `WASM_BUILD_CI_GUIDE.md` — WASM build path (independent of frontend bundler)
- `docs/APP_STRUCTURE.md` — app layout after #966 strangler
