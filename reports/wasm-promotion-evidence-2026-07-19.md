# WASM Promotion Evidence — 2026-07-19 (Foundation Wave 2)

**Decision:** **STAY TIER B** (reaffirmed)

## Context

Foundation Wave 2 (#965) delivered C++ binding-13 parity (`historyTexture`, `historyHead` in `extraBuffer[4]`), TS device policy sync (`maxBindingsPerBindGroup: 14`), and modular WebGPU init. Promotion still requires GPU-backed measurement.

## Gates

| Gate | Status | Notes |
|------|--------|-------|
| Performance (≥1.25× on 3 shaders) | OPEN | No GPU bench in CI VM |
| Reliability (2 GPU configs) | OPEN | Playwright skips without adapter |
| Integration smoke | OPEN | Manual checklist unsigned |
| Ops (4-week CI green) | OPEN | Not re-verified this cycle |

## Commands for human GPU run

```bash
npm run wasm:build && npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench
npm run test:wasm:parity
# Then WASM_SMOKE_TEST.md Tests 1–5 without testMode
```

Attach `test-results/wasm-benchmark-report.json` with `gpuBackendObserved: true` to close gate 1.
