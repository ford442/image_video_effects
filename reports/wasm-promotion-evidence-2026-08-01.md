# WASM Promotion Evidence — 2026-08-01 (pre-GPU tooling)

**Decision:** **STAY TIER B**

## Summary

No GPU evidence was collected. This review landed the pre-GPU tooling the policy calls for and
reaffirms Tier B; **promotion gates 1–4 remain OPEN**, unchanged since 2026-07-26.

| Item | Status |
|------|--------|
| Pixel-diff harness (frozen seeds, TS vs WASM) | Landed — [`tests/wasm-pixel-diff.spec.ts`](../tests/wasm-pixel-diff.spec.ts) |
| Clearer init failure (surface / partial bring-up) | Landed — [`src/renderer/wasmInitDiagnostics.ts`](../src/renderer/wasmInitDiagnostics.ts) |
| Diagnostics visible in Controls debug panel | Landed — `AdvancedDebugPanel` renderer-diagnostics block |
| WebGPU adapter identity in diagnostics | Landed — `WebGPURenderer.getAdapterSummary()` → `getDiagnostics().webgpu.adapterInfo` |
| GPU bench/parity/pixel-diff runs | **Not run** — see below |

## Environment honesty note

This review ran in a Cloud VM that has **no GPU and no browser adapter**:

```
lspci | grep -iE 'vga|3d|display'   → lspci unavailable
ls /dev/dri                          → no /dev/dri
```

Additionally, `node_modules` could not be installed in this session, so **even the usual
VM-stub runs** (`test:wasm:bench`, `test:wasm:parity`) were not executed this cycle — there is
no 2026-08-01 stub report, deliberately. Previous cycles' stubs already establish the same fact
(`gpuBackendObserved: false`); producing another would add no information.

**Nothing in this review is promotion evidence.** Gate status is carried forward from 2026-07-26.

## Gate results

| Gate | Status | Evidence |
|------|--------|----------|
| 1 Performance (≥1.25× on ≥3 shaders) | ⬜ **OPEN** | No adapter; last stub [`wasm-benchmark-report-stub-2026-07-26.json`](./wasm-benchmark-report-stub-2026-07-26.json) — `gpuBackendObserved: false` |
| 2 Reliability (parity on ≥2 GPU configs) | ⬜ **OPEN** | Not run. Pixel-diff harness now available to strengthen this gate when a GPU exists |
| 3 Integration (manual Controls smoke) | ⬜ **OPEN** | Requires a GPU browser without `testMode`; [`WASM_SMOKE_TEST.md`](../WASM_SMOKE_TEST.md) unsigned |
| 4 Ops (4 consecutive green CI weeks) | ⬜ **OPEN** | Weekly table in [`WASM_PROMOTION_TRACKING.md`](../WASM_PROMOTION_TRACKING.md) — not met as of last review |

## What changed this cycle (no C++ features)

Per the strategic call, **no new C++ renderer features** were added; the GraphRunner port and
making WASM default stay out of scope.

### 1. Pixel-diff harness — gate 2 strengthening

`tests/wasm-pixel-diff.spec.ts` loads each `PARITY_MATRIX` shader on both backends, pins render
state at three frozen times, captures the canvas on each, and reports per-pixel deltas
(`meanAbsDelta`, `maxAbsDelta`, `differingCellRatio`) plus side-by-side PNGs under
`test-results/pixel-diff/`.

Why it matters: the existing parity spec compares **mean luminance and coverage**, which two
structurally different images can both satisfy. A statistical pass is weak evidence for "the
backends render the same thing".

Thresholds are deliberately **report-only** (`REPORT_ONLY = true`): what counts as acceptable
FP drift between Dawn-in-WASM and browser WebGPU is unknown until a real GPU run measures it.
Set the gate after the first discrete-GPU run, not before.

```bash
npm run build && WASM_GPU_TESTS=1 npx playwright test tests/wasm-pixel-diff.spec.ts
```

Without an adapter it writes a stub report marked `gpuObserved: false` and skips.

### 2. Clearer init failure

`initWasmRenderer` returning `false` used to produce one message blaming Windows/Dawn adapter
acquisition regardless of what actually happened. It now names the stage reached
(`Instance → Adapter → Device → Surface → Resources → BindGroups → Pipeline → Ready`), the C++
error, the adapter string, and a hint that distinguishes the three cases that matter for triage:

- **no adapter** — expected in cloud VMs, driver/browser issue on real hardware, *not* a WASM bug
- **partial bring-up** (device acquired, failed at Surface/Resources/BindGroups/Pipeline) — a
  genuine WASM-side bug, Tier B P1, file it as a parity bug
- **module never loaded** — artifact/serving problem, check `npm run wasm:validate`

Unit-tested in [`src/renderer/wasmInitDiagnostics.test.ts`](../src/renderer/wasmInitDiagnostics.test.ts)
(no GPU required).

### 3. Diagnostics always visible

The debug panel now renders a live block: backend, FPS, **adapter identity**, adapter-ladder rung,
WASM init summary (`ready` / `partial at Surface` / `failed at Adapter`), and the last WASM init
error — including when WASM failed and the app fell back to TS, which is exactly when someone
needs it. Previously this required typing `getDiagnostics()` into the console.

`WebGPURenderer` now retains `adapterSummary` / `adapterAttemptLabel` from the init ladder and
exposes them through `RendererManager.getDiagnostics().webgpu`, so **both** backends' adapter
names are reportable. Gate 2 asks for "document hardware in issue/PR" — that string is now
copy-pasteable from the UI rather than reconstructed from `chrome://gpu`.

## Human GPU checklist (still required — unchanged)

```bash
npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench                                # gate 1
WASM_GPU_TESTS=1 npm run test:wasm:parity                               # gate 2
WASM_GPU_TESTS=1 npx playwright test tests/wasm-pixel-diff.spec.ts      # gate 2 (new)
# then WASM_SMOKE_TEST.md Tests 1–5 WITHOUT testMode                    # gate 3
```

Attach, per config (**≥2** GPU configs, ideally one discrete + one integrated/second vendor):

- `test-results/wasm-benchmark-report.json` with **`gpuBackendObserved: true`**
- `test-results/wasm-pixel-diff.json` + the `test-results/pixel-diff/*.png` pairs
- Adapter strings for **both** backends — now readable from Controls → Dev Tools → renderer diagnostics
- Driver / OS / browser version, and whether the machine was plugged in

## Issue comment template (#890 / #1013)

> **WASM Tier B review — 2026-08-01: STAY TIER B**
>
> No GPU evidence this cycle — the Cloud VM has no adapter (`/dev/dri` absent), so gates 1–4 are
> carried forward OPEN from 2026-07-26. Per policy, feature work stays frozen: **parity bugs only**,
> no new C++ renderer features, no GraphRunner port.
>
> Landed pre-GPU tooling instead: frozen-seed pixel-diff harness (`tests/wasm-pixel-diff.spec.ts`),
> stage-aware init failure messages that separate "no adapter" from a partial bring-up, and a live
> renderer-diagnostics block in the debug panel exposing both backends' adapter identity.
>
> Evidence: `reports/wasm-promotion-evidence-2026-08-01.md`

## Decision

**STAY TIER B** — experimental badge unchanged, WASM stays opt-in, no production-ready claims.
Feature work remains frozen to parity bugs until a human GPU session closes gates 1–3.
