# WASM Test Suite

Full automated testing for the C++ WASM renderer path — parity with the TypeScript WebGPU backend, benchmarks, and smoke coverage.

**Support policy:** WASM is **Tier B (experimental opt-in)** — see [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md). Tests inform promotion to Tier A; they do not imply production SLA today.

## Prerequisites

1. **Build WASM + production app** (requires [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html)):

   ```bash
   npm run wasm:build
   npm run build
   # or on machines without emsdk:
   SKIP_WASM_BUILD=1 npm run build
   npm run wasm:validate
   ```

2. **WebGPU-capable browser** (Chrome/Chromium with GPU) for strict GPU suites.

3. **Install Playwright** (once):

   ```bash
   npx playwright install chromium
   ```

## Quick reference

| Command | GPU required | What it runs |
|---------|--------------|--------------|
| `npm run test:wasm:unit` | No | Jest — bridge API + RendererManager parity mocks |
| `npm run test:wasm:e2e` | No | Playwright soft smoke — build loads, test API, parity matrix (skips WASM assertions if no adapter) |
| `npm run test:wasm:smoke` | Alias for `test:wasm:e2e` | Same |
| `npm run test:wasm:gpu` | Yes (`WASM_GPU_TESTS=1`) | Parity matrix + benchmark JSON report |
| `npm run test:wasm:parity` | Yes | WASM vs WebGPU statistical parity only |
| `npm run test:wasm:bench` | Yes | FPS + `getGPUTimings()` benchmark → `test-results/wasm-benchmark-report.json` |
| `npm run test:wasm` | No | Unit + soft e2e (CI default) |
| `npm run test:wasm:full` | Yes | Unit + e2e + GPU parity + bench |

## Running locally

### Headless / CI-style (no GPU)

```bash
npm run wasm:build && SKIP_WASM_BUILD=1 npm run build
npm run test:wasm
```

Verifies WASM artifacts, production build, Playwright loads `?renderer=wasm&testMode=1`, and exercises the shader matrix without requiring a real WebGPU adapter.

### With GPU (promotion / benchmark data)

```bash
npm run wasm:build && npm run build

# Strict mode — fails if ?renderer=wasm cannot initialize
export WASM_GPU_TESTS=1

npm run test:wasm:full
# or individually:
npm run test:wasm:gpu
```

**`WASM_GPU_TESTS=1`** enables strict mode:
- Smoke tests **require** active `wasm` backend (FPS ≥ 5, non-black canvas)
- Parity/benchmark tests run (skip if adapter missing)
- Benchmark writes **`test-results/wasm-benchmark-report.json`** with promotion gate assessment

**Promotion tracking:** [`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md)

Attach that JSON to promotion PRs per [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md).

## Parity matrix (5 shaders)

Defined in [`tests/fixtures/parityMatrix.ts`](./tests/fixtures/parityMatrix.ts). Exercised by:

- [`tests/wasm-renderer.smoke.spec.ts`](./tests/wasm-renderer.smoke.spec.ts) — per-shader smoke + multi-slot stack
- [`tests/renderer-parity.spec.ts`](./tests/renderer-parity.spec.ts) — WASM vs WebGPU luminance comparison

| Category | Shader | Notes |
|----------|--------|-------|
| fluid | `sim-fluid-feedback-coupled` | Fixed testState time/mouse |
| reaction-diffusion | `gen-lichen-reaction-diffusion` | + audio uniforms |
| audio-reactive | `cyber-ripples` | + bass/mid/treble |
| generative | `plasma` | generative input |
| interactive | `liquid` | mouse-driven |

## Benchmark suite & promotion gate

[`tests/wasm-benchmark.spec.ts`](./tests/wasm-benchmark.spec.ts) compares **wasm** vs **webgpu** on the first 3 matrix shaders (fluid, RD, cyber-ripples).

Report fields:
- `avgFps`, `avgTotalMs`, `p95TotalMs` per backend
- `comparisons[].speedupRatio` — WASM fps / WebGPU fps (≥ **1.25** meets gate)
- `promotionGateMet` — true when ≥ **3** shaders meet the ratio

**Note:** WASM `getGPUTimings().available` is `false`; `timingSource` is `wall-clock`. TS WebGPU may report `gpu-timestamp` when supported.

## Shader hot-reload (dev)

```
http://localhost:3000/?renderer=wasm&shaderHotReload=1
```

Also works in test mode: `?renderer=wasm&testMode=1&shaderHotReload=1`

## Manual smoke testing

See [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md) for browser DevTools checks.

## CI

[`.github/workflows/ci.yml`](./.github/workflows/ci.yml):

| Job | What runs |
|-----|-----------|
| `wasm` | emsdk build, `wasm:validate`, Jest `--testPathPattern=WASM` |
| `test` | unit tests + production build |
| `test-wasm-e2e` | **soft** `test:wasm:e2e` + **strict** `test:wasm:gpu` (GPU specs skip on headless) |
| `wasm-gpu-manual` | `workflow_dispatch` only — run `test:wasm:full` on a machine with WebGPU |

Artifacts:
- `wasm-benchmark-report` — JSON when GPU suite produces data
- `wasm-playwright-report` — HTML report

### Self-hosted GPU runner (recommended for promotion)

On a machine with Chromium + WebGPU:

```bash
WASM_GPU_TESTS=1 npm run test:wasm:full
```

Upload `test-results/wasm-benchmark-report.json` to the promotion issue/PR.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| GPU tests all skip | Set `WASM_GPU_TESTS=1` and use Chrome with GPU; headless CI has no adapter |
| Strict smoke fails | Verify `?renderer=wasm` in browser; check `getDiagnostics().wasm` |
| `build/` missing | Run `npm run build` first |
| No benchmark JSON | GPU suite skipped — run locally with `WASM_GPU_TESTS=1` |
| Parity luminance delta fails | Raise `maxLuminanceDelta` in matrix or tune `testState.time` |

## Adding a new parity case

1. Add entry to `PARITY_MATRIX` in `tests/fixtures/parityMatrix.ts`
2. Choose fixed `testState` for stability
3. Run `WASM_GPU_TESTS=1 npx playwright test tests/wasm-renderer.smoke.spec.ts -g "your-shader-id"`
