# WASM Promotion Evidence — 2026-07-26 (Phase 1 hygiene)

**Decision:** **STAY TIER B**

## Summary

Phase 1 hygiene (#1013) implemented without GPU:

| Item | Status |
|------|--------|
| Single `npm run build` (`wasm:build` once in `prebuild`) | Verified in [`package.json`](../package.json); docs updated |
| Duplicate `-sGROWABLE_ARRAYBUFFERS=0` removed | [`wasm_renderer/build.sh`](../wasm_renderer/build.sh) |
| Dormant `-sg.wgsl` probe removed | [`src/renderer/webgpu/pipeline.ts`](../src/renderer/webgpu/pipeline.ts) |
| Input-source tests expanded | `WASMBridge.uniforms.test.ts`, `WASMRenderer.input.test.ts` |
| `uploadImageData` zero-dimension guard | [`wasm_renderer/bridge/capture.js`](../wasm_renderer/bridge/capture.js) |

**Promotion gates 1–4 remain OPEN.** VM bench/parity cannot observe WebGPU (`gpuBackendObserved: false`).

## Gate results

| Gate | Status | Evidence |
|------|--------|----------|
| 1 Performance | **OPEN** | [`wasm-benchmark-report-stub-2026-07-26.json`](./wasm-benchmark-report-stub-2026-07-26.json) — backends missing |
| 2 Reliability (2 GPUs) | **OPEN** | Parity 6/7 skipped, 1 failed (no adapter) — VM run 2026-07-26 |
| 3 Manual smoke | **OPEN** | Blocked in Cloud VM — requires GPU browser without `testMode` |
| 4 Ops (4-week CI) | **OPEN** | See [`WASM_PROMOTION_TRACKING.md`](../WASM_PROMOTION_TRACKING.md) weekly table |

## VM run commands (2026-07-26)

```bash
SKIP_WASM_BUILD=1 npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench   # gpuBackendObserved: false
WASM_GPU_TESTS=1 npm run test:wasm:parity  # 6 skipped, 1 failed (no adapter)
lspci | grep -iE 'vga|3d|display'          # Device 1234:1111 (QEMU)
```

## Human GPU checklist (still required)

```bash
npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench
WASM_GPU_TESTS=1 npm run test:wasm:parity
# WASM_SMOKE_TEST.md Tests 1–5 without testMode
```

Attach `test-results/wasm-benchmark-report.json` with **`gpuBackendObserved: true`** + hardware notes on **≥2 GPU configs**.

## Issue comment template (#1013 / #890)

> **WASM Tier B review — 2026-07-26: STAY TIER B**
>
> Phase 1 hygiene merged: single `npm run build`, emcc flag dedupe, `-sg.wgsl` probe removed, input-source test coverage.
>
> Promotion gates **not met** — VM evidence shows `gpuBackendObserved: false`. Awaiting discrete-GPU bench + parity on ≥2 configs and manual smoke sign-off.
>
> Evidence: `reports/wasm-promotion-evidence-2026-07-26.md`

## Decision

**STAY TIER B** — experimental badge unchanged; no production-ready claims.
