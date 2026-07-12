# WASM Tier B → A Evidence Collection — 2026-07-11

**Reviewer:** automated + CI log analysis  
**Branch reviewed:** `feat/midi-control-and-wasm-parity` (local) · CI evidence from `main`  
**Decision:** **STAY TIER B**

---

## Executive summary

Integration epics #817–#890 are closed. The WASM path **builds**, **unit tests pass**, and **CI smoke jobs are green** on recent `main` pushes. However, **none of the four promotion gates** in [`WASM_BACKEND_POLICY.md`](../WASM_BACKEND_POLICY.md) are satisfied because GPU-dependent benchmarks and parity tests **skip** on headless CI, and no local GPU benchmark artifacts exist.

**Do not promote.** Continue Tier B experimental policy.

---

## Gate 1 — Performance (≥1.25× on ≥3 shaders)

| Item | Status |
|------|--------|
| `npm run test:wasm:bench` with `WASM_GPU_TESTS=1` | **Not run** (no GPU in Cloud VM) |
| `test-results/wasm-benchmark-report.json` | **Stub only** — `gpuBackendObserved: false` |
| Discrete GPU run | **Pending** |
| iGPU / second vendor run | **Pending** |

**Target shaders:** `sim-fluid-feedback-coupled`, `gen-lichen-reaction-diffusion`, `cyber-ripples`

---

## Gate 2 — Reliability (parity on ≥2 GPU configs)

| Item | Status |
|------|--------|
| `npm run test:wasm:parity` | **Not run** on real hardware |
| CI run `29148209376` | Parity specs **skipped** (no adapter) |
| Vendor matrix | **Empty** |

---

## Gate 3 — Integration (manual Controls smoke)

| Item | Status |
|------|--------|
| [`WASM_SMOKE_TEST.md`](../WASM_SMOKE_TEST.md) outside `testMode` | **Not signed off** |
| Recording / input sources / shader browser | **Needs human GPU session** |

---

## Gate 4 — Ops (4 consecutive green weeks)

Recent `main` push history:

| Period | `wasm` + `test-wasm-e2e` |
|--------|--------------------------|
| Jun 23 – Jul 9 | Predominantly **failure** |
| Jul 10 – Jul 11 | **Success** (runs `29148209376` et al.) |

**4 consecutive weeks:** **NOT MET**

CI job breakdown (run `29148209376`, 2026-07-11):

```
wasm: success
test: success
test-wasm-e2e: success  (13 tests skipped — no WebGPU adapter)
```

---

## What was verified locally (2026-07-11)

```
npm run test:wasm:unit  →  29/29 pass (WASMBridge, WASMRenderer.parity, WASMRenderer.input)
```

Playwright suites blocked on this branch: production `npm run build` fails with `TS2352` in `webgpuDevicePolicy.test.ts` (unrelated to WASM C++). Use `main` or fix TS before local Playwright.

---

## Recommended next steps (measurement only)

1. **Machine A (discrete):** run full bench + parity; attach JSON + `chrome://gpu` screenshot text.
2. **Machine B (iGPU or AMD):** repeat.
3. **Manual smoke:** complete Gate 3 table in [`WASM_PROMOTION_TRACKING.md`](../WASM_PROMOTION_TRACKING.md).
4. Re-review when **week 2026-W32** completes with 4 consecutive green weeks (if trend holds from Jul 10).

---

## Promotion comment (for #890 / PR)

> **Decision: STAY TIER B (2026-07-11).** Gates 1–3 lack GPU-backed evidence; gate 4 not met (June/July CI mostly red until Jul 10). CI `test-wasm-e2e` green does not imply benchmark or parity pass — ubuntu-latest skips GPU specs. Unit tests 29/29 green. Next: bench on discrete + iGPU, attach `wasm-benchmark-report.json`, sign manual smoke checklist. No renderer glue changes unless a gate fails on a fixable bug.
