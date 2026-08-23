# Frontend toolchain decision (July 2026)

**Status: stay on CRA + CRACO** — TypeScript 5.4.5 landed (Aug 2026); Vite spike deferred.

Parent: [#965](https://github.com/ford442/image_video_effects/issues/965) · Epic: [#1076](https://github.com/ford442/image_video_effects/issues/1076) · Toolchain hygiene: [#1083](https://github.com/ford442/image_video_effects/issues/1083)

## Current stack

| Piece | Version / tool | Notes |
|-------|----------------|-------|
| Bundler | Create React App 5 (`react-scripts`) | Webpack 5 under the hood |
| Override layer | `@craco/craco` 7 | Patches webpack without eject |
| React | 19.1 | Works with CRA 5 via overrides |
| TypeScript | **5.4.5** (locked `~5.4.5`) | `tsconfig` targets ES2020; CI runs `npm run typecheck` |
| WebGPU types | `@webgpu/types` 0.1.64 | Dev-time only; `device.ts` configure options stay typed |

## Decision log

| Date | Decision |
|------|----------|
| Jul 2026 | **Stay CRA + CRACO** — lowest risk for foundation work (#965) |
| Aug 2026 (#1042) | **TypeScript 5.4.5 landed** on CRA 5 + CRACO 7 — not blocked |
| Aug 2026 (#1083) | Docs + deprecated shim cleanup; Vite spike still deferred |

**TS 5 status:** Landed and CI-proven (`tsc --noEmit`, full Jest, `SKIP_WASM_BUILD=1` production build). Residual noise only: `react-scripts@5` peer metadata still lists TypeScript through 4.x, so `npm ls typescript` may show an invalid peer even though the locked compiler passes. Removing that metadata mismatch is one reason the optional Vite migration remains a separate follow-up — not a blocker for daily dev.

## Why CRACO exists (`craco.config.js`)

CRA’s default webpack config is insufficient for this repo. CRACO patches:

1. **`fullySpecified: false` for `.m?js`** — ESM packages (e.g. `@huggingface/transformers`) omit `.js` extensions; webpack 5 strict resolution breaks without this.
2. **`import.meta` shim for `@xenova/transformers`** — Custom loader (`scripts/webpack-import-meta-shim-loader.js`) runs before webpack parses the package; transformers assumes Vite/Node ESM.
3. **`topLevelAwait` + `dynamicImport` output env** — Required for async WASM / dynamic `import()` in the app and ML paths.
4. **`sharp$` and `onnxruntime-node$` → `false`** — Stub Node-only optional deps so browser bundle does not pull native binaries.
5. **`ignoreWarnings`** — Source-map and `import.meta` parse noise from third-party ML packages.

Without CRACO, `npm start` / `npm run build` fail on transformers import resolution and optional native modules.

## Dependency boundary honesty

| Boundary | Mechanism |
|----------|-----------|
| `@xenova/transformers` alias | `package.json` maps `@xenova/transformers` → `npm:@huggingface/transformers@^4.2.0` — keeps import path stable for [`transformersLoader.ts`](src/services/aiModels/transformersLoader.ts) |
| No accidental Node ONNX | CRACO stubs `sharp$` / `onnxruntime-node$` → `false` in [`craco.config.js`](craco.config.js) |
| AI lazy boundaries | `@xenova/transformers` and `@mlc-ai/web-llm` must be dynamically imported only through their loader modules — enforced by `npm run verify:dependency-boundaries` |
| Shader list URLs | Committed `public/shader-lists/*.json` must use relative paths (no leaked test-CDN URLs) — same gate |

Run `npm run verify:toolchain-foundation` before merge (bundle budget + dependency boundaries + shader-list URL policy).

## Toolchain commands

| Goal | Command |
|------|---------|
| Dev | `BROWSER=none npm start` |
| Prod JS (no emcc) | `SKIP_WASM_BUILD=1 npm run build` |
| WASM artifacts | `npm run wasm:build` (needs `emcc` + emdawn) |
| Typecheck | `npm run typecheck` |
| Device policy sync | `npm run verify:device-policy` |
| Uniforms layout | `npm run verify:uniforms` |
| Foundation gates | `npm run verify:toolchain-foundation` |

## Pain points (documented, not blocking)

- **CRA peer metadata** — `react-scripts` still declares TypeScript ≤4.x; locked TS 5.4.5 works in practice.
- **CRACO patch surface** — every new ESM-heavy dependency may need another webpack rule.
- **Slow HMR / opaque webpack** — large shader catalog + ML chunks; hard to tune without ejecting.
- **`prestart` / `prebuild`** — shader list generation and manifest steps add startup latency (independent of bundler choice).

## Vite spike scope (not executed)

TS 5 prerequisite is satisfied. Spike still **deferred** — revisit triggers not met (no second CRACO shim yet).

A dev-only Vite + React 19 + `@webgpu/types` spike would validate:

- Native `import.meta` and faster cold start for `src/`
- Whether `@huggingface/transformers` works without the custom loader
- HMR on `WebGPURenderer` modular files

**Out of scope for spike:** WASM `public/` copy path, CRA Jest config, Playwright production build (still `craco build`), deploy scripts.

**Estimated integration cost:** New `vite.config.ts`, dual `index.html` entry, Jest either kept on CRA or migrated to Vitest, CI `build` job unchanged until cutover.

## Decision

| Option | Verdict |
|--------|---------|
| **Stay CRA + CRACO** | ✅ **Chosen** — lowest risk; foundation work does not depend on bundler migration |
| **TypeScript 5.x on CRA** | ✅ **Landed** (#1042 / #1083) — CI green; peer-metadata noise only |
| Migrate to Vite | Defer until a dedicated tooling sprint or revisit trigger fires |
| Hybrid (Vite dev / CRA prod) | Rejected — two configs diverge quickly; only worth it if HMR pain blocks daily dev |

## Revisit triggers

- `react-scripts` security EOL or unfixable webpack conflict
- Second CRACO shim for a major dependency
- Team commits to Vitest + Vite as a standalone epic

## Related docs

- `craco.config.js` — live CRACO overrides
- `WASM_BUILD_CI_GUIDE.md` — WASM build path (independent of frontend bundler)
- `docs/APP_STRUCTURE.md` — app layout after #966 strangler
- `README.md` — contributor command matrix
