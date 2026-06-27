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

2. **WebGPU-capable browser** (Chrome/Chromium with GPU). Headless CI VMs often lack a GPU adapter — GPU tests auto-skip when backends fall back.

3. **Install Playwright** (once):

   ```bash
   npx playwright install chromium
   ```

## Quick reference

| Command | What it runs |
|---------|----------------|
| `npm run test:wasm:unit` | Jest — bridge API + RendererManager parity mocks |
| `npm run test:wasm:smoke` | Playwright — init, multi-shader, error checks |
| `npm run test:wasm:parity` | Playwright — WASM vs WebGPU statistical parity matrix |
| `npm run test:wasm:bench` | Playwright — FPS + `getGPUTimings()` benchmark report |
| `npm run test:wasm` | All of the above (unit + full Playwright suite) |

## Running locally (with GPU)

```bash
# 1. Build
npm run wasm:build && npm run build

# 2. Unit tests (no GPU needed)
npm run test:wasm:unit

# 3. Playwright suites (GPU required for meaningful results)
WASM_GPU_TESTS=1 npm run test:wasm:smoke
WASM_GPU_TESTS=1 npm run test:wasm:parity
WASM_GPU_TESTS=1 npm run test:wasm:bench

# Or everything:
WASM_GPU_TESTS=1 npm run test:wasm
```

Set `WASM_GPU_TESTS=1` to **opt in** to GPU-dependent tests. Without it, parity/benchmark specs skip (safe for headless VMs).

## Parity matrix

Defined in [`tests/fixtures/parityMatrix.ts`](./tests/fixtures/parityMatrix.ts):

| Category | Shader | What we compare |
|----------|--------|-----------------|
| fluid | `sim-fluid-feedback-coupled` | Mean luminance + active pixel coverage |
| reaction-diffusion | `gen-lichen-reaction-diffusion` | Same + audio uniform injection |
| audio-reactive | `cyber-ripples` | Same + bass/mid/treble |
| generative | `plasma` | Same |
| interactive | `liquid` | Same + mouse position |

Both backends render with identical `setTestRenderState()` (fixed time/mouse/audio), then we compare canvas statistics. This avoids brittle pixel-perfect diffs while catching "black canvas" and major divergence.

Optional canvas snapshots (first 2 matrix entries) live under `tests/renderer-parity.spec.ts-snapshots/`.

## Benchmark suite

[`tests/wasm-benchmark.spec.ts`](./tests/wasm-benchmark.spec.ts) runs `__pixelocity__.runBenchmark(60)` on each benchmark-matrix shader for **wasm** and **webgpu**, reporting:

- `avgFps`
- `avgTotalMs` / `p95TotalMs` from `getGPUTimings()`

**Note:** WASM `getGPUTimings().available` is always `false` today — C++ records CPU wall-clock per slot, not GPU timestamp queries. TS WebGPU may report `available: true` when timestamp queries are supported.

## Shader hot-reload (dev)

Edit WGSL under `public/shaders/` and reload compute pipelines without restarting:

```
http://localhost:3000/?renderer=wasm&shaderHotReload=1
```

Implementation:
- Browser polls `Last-Modified` via `HEAD` requests
- Calls C++ `reloadShader()` → destroys old pipeline, recompiles WGSL
- TS WebGPU path already recompiles on content hash change via `loadShader()`

Also works in test mode: `?renderer=wasm&testMode=1&shaderHotReload=1`

## Manual smoke testing

See [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md) for browser DevTools checks when automated tests aren't available.

## CI

The `test-wasm-e2e` job in [`.github/workflows/ci.yml`](./.github/workflows/ci.yml):

1. Downloads WASM artifacts from the `wasm` job
2. Builds production app (`SKIP_WASM_BUILD=1`)
3. Runs all Playwright WASM specs with `WASM_GPU_TESTS=1`
4. Uploads Playwright HTML report

The `wasm` job runs Jest unit smoke (`--testPathPattern=WASM`).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| All Playwright tests skip | Set `WASM_GPU_TESTS=1` and use a GPU browser |
| `build/` missing | Run `npm run build` first |
| Parity luminance delta fails | Expected for shaders with timing-dependent feedback; tighten `testState.time` or raise `maxLuminanceDelta` in matrix |
| Hot reload not firing | Ensure dev server serves `Last-Modified` headers; use `npm start` not static `build/` |
| Bridge export missing | Run `npm run wasm:build` after C++ changes |

## Adding a new parity case

1. Add entry to `PARITY_MATRIX` in `tests/fixtures/parityMatrix.ts`
2. Choose fixed `testState` for stability
3. Run `WASM_GPU_TESTS=1 npx playwright test tests/renderer-parity.spec.ts -g "your-shader-id"`
