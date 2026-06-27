# Transformers security migration (@xenova → @huggingface via npm alias)

**Date:** 2026-06-27  
**Production depth model:** `Xenova/dpt-hybrid-midas` (`pipeline('depth-estimation', ...)`)  
**Resolved package:** `@xenova/transformers` → `npm:@huggingface/transformers@4.2.0`

## Audit before / after (`npm audit --omit=dev`)

| Severity  | Pre (`reports/pre-audit.json`) | Post (`reports/post-audit.json`) |
|-----------|--------------------------------|----------------------------------|
| Critical  | 1 (`protobufjs`)               | **0**                            |
| High      | 3 (`@xenova/transformers`, `onnxruntime-web`, `onnx-proto`) | **0** |
| Moderate  | 1 (`@protobufjs/utf8`)         | **0**                            |
| Total     | 5                              | **0**                            |

**Dependency chain cleared:** `@xenova/transformers` → `onnxruntime-web` → `onnx-proto` → `protobufjs` → `@protobufjs/utf8`

No `overrides` block was required after alias migration.

## Migration mechanism

```json
"@xenova/transformers": "npm:@huggingface/transformers@^4.2.0"
```

Zero import changes — all existing `from '@xenova/transformers'` resolve to Hugging Face v4.

## Smoke harnesses (standalone)

| Tier | Command | Purpose |
|------|---------|---------|
| CPU/WASM contract | `npm run test:depth:cpu` | Node, `device: 'cpu'`, single-thread ORT — validates tensor shape/range only |
| WebGPU production path | `npm run test:depth:webgpu` | Playwright + esbuild bundle, `device: 'webgpu'` — requires GPU Chromium (`DEPTH_GPU_TESTS=1`) |

Shared config: `tests/smoke/depthEstimationConfig.mjs`  
Fixture: `tests/smoke/fixtures/sample-rgb.png` (64×64 RGB)

### Smoke results (this environment)

- **CPU smoke:** PASS — `dims=[64,64]`, `len=4096`, finite non-negative values
- **WebGPU smoke:** SKIPPED — headless VM has no WebGPU adapter (`navigator.gpu.requestAdapter()` → null). Run on GPU CI or local Chrome with `DEPTH_GPU_TESTS=1`.

## Verification

| Check | Result |
|-------|--------|
| `npm audit --omit=dev` | 0 vulnerabilities |
| `CI=true npx react-scripts test --watchAll=false` | 178/178 pass |
| `SKIP_WASM_BUILD=1 npx react-scripts build` (clean `HEAD` src) | **PASS** — main bundle **2.66 MB gzip** (`main.*.js`) |
| `npx tsc --noEmit` | **Not clean** — see TypeScript note below |
| Runtime feature code (`src/`) | **Untouched** |

## Bundle / package size

| Metric | Before (legacy `@xenova/transformers` 2.x) | After (alias → `@huggingface/transformers` 4.2.0) |
|--------|-----------------------------------------------|-----------------------------------------------------|
| `node_modules/@xenova/transformers` (fresh install) | ~243 MB | ~16 MB |
| CRA production JS (gzip, clean tree build) | ~2.66 MB (similar order of magnitude) | ~2.66 MB |

ORT `.wasm` blobs are loaded at runtime from the transformers package / CDN cache, not embedded in the CRA bundle. No bundler 404 observed during CPU smoke (model + ORT WASM fetched successfully).

## COOP / COEP / CSP notes

- **COOP/COEP:** DreamHost deploy headers not verified in this session. Without `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp`, ORT falls back to **single-threaded WASM** (slower depth inference, still functional).
- **CSP / `eval()`:** `protobufjs` (transitive via ORT) may trigger bundler/CSP warnings under strict `script-src` without `'unsafe-eval'`. No strict CSP observed in CRA default hosting.

## TypeScript note (`npx tsc --noEmit`)

`@huggingface/transformers@4.x` ships `.d.ts` using TypeScript 5+ syntax (e.g. `const` type parameters). With project TypeScript **4.9.5**, standalone `tsc` reports parse errors in `node_modules/@xenova/transformers/types/pipelines/*.d.ts`.

- **Pre-migration baseline:** `tsc` already had 1 pre-existing src error (`WASMRenderer.input.test.ts` mock typing).
- **Post-migration:** additional lib parse noise; **does not block** `react-scripts build` (CRA fork-ts-checker + `skipLibCheck`).
- **Upgrading to TS 5.4+** fixes lib parsing but surfaces additional strictness errors in `AutoDJ.ts` (regex `/s` vs `target: es5`) when combined with v4 import graph — requires a separate `tsconfig` target bump (out of scope for this decoupled track).

**Strategy B (pin legacy + overrides) was not triggered** — no depth-output type errors in forbidden consumer files.

## Files touched (this track)

- `package.json`, `package-lock.json`
- `reports/pre-audit.json`, `reports/post-audit.json`, this file
- `tests/smoke/*`, `tests/depth-estimation.webgpu.spec.ts`
