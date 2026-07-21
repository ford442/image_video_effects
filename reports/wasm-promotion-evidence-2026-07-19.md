# WASM Promotion Evidence — 2026-07-19 (Measurement harness)

**Decision:** **STAY TIER B**

## Summary

Implemented measurement harness polish (Phase A of promotion plan). Ran bench + parity in Cloud VM; all GPU-dependent specs skipped. **No promotion gates closed.**

## Code changes (measurement support)

| Change | File |
|--------|------|
| Bench report: `benchmarkShaderIds`, adapter summaries, `userAgent` | `tests/helpers/rendererHarness.ts`, `tests/wasm-benchmark.spec.ts` |
| `__pixelocity__.getAdapterSummary()` in testMode | `src/hooks/useTestHarness.ts` |
| CI artifact: `wasm-benchmark-report` | `.github/workflows/ci.yml` |
| Early skip when no GPU (avoids bench timeout) | `tests/wasm-benchmark.spec.ts` |

## Gate results

| Gate | Status | Evidence |
|------|--------|----------|
| 1 Performance | **OPEN** | [`wasm-benchmark-report-stub-2026-07-19.json`](./wasm-benchmark-report-stub-2026-07-19.json) — `gpuBackendObserved: false`, `promotionGateMet: false` |
| 2 Reliability (2 GPUs) | **OPEN** | Parity 7/7 skipped in VM |
| 3 Manual smoke | **OPEN** | Requires GPU browser without `testMode` — not runnable in Cloud VM |
| 4 Ops (4-week CI) | **OPEN** | W29: `wasm` green, `test-wasm-e2e` skipped (`test` job failing on main) |

## VM run commands

```bash
npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench   # skipped — no adapter
WASM_GPU_TESTS=1 npm run test:wasm:parity  # 7/7 skipped
lspci | grep -iE 'vga|3d|display'          # Device 1234:1111 (QEMU)
```

## Human GPU checklist (still required)

```bash
npm run wasm:build && npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench
WASM_GPU_TESTS=1 npm run test:wasm:parity
# Then WASM_SMOKE_TEST.md Tests 1–5 without testMode
```

Attach `test-results/wasm-benchmark-report.json` with `gpuBackendObserved: true` + `lspci` / `chrome://gpu` notes on **≥2 GPU configs**.

## Decision

**STAY TIER B** — measurement infrastructure ready; GPU-backed evidence and 4-week CI green streak still required before promotion.
