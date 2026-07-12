# WASM Tier B → Tier A Promotion Tracking

**Policy:** [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md)  
**Status doc:** [`wasm_renderer/STATUS.md`](./wasm_renderer/STATUS.md)  
**Test how-to:** [`WASM_TEST_SUITE.md`](./WASM_TEST_SUITE.md) · [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md)  
**Umbrella (closed):** [#885](https://github.com/ford442/image_video_effects/issues/885)  
**Docs refresh (closed):** [#890](https://github.com/ford442/image_video_effects/issues/890)

**Current tier:** **B — Experimental (opt-in)**  
**Last evidence review:** 2026-07-11

---

## Promotion gates (all must pass)

| # | Gate | Threshold | Status | Evidence |
|---|------|-----------|--------|----------|
| 1 | **Performance** | WASM ≥ **1.25×** TS FPS (or inverse frame-time) on **≥3** benchmark shaders | ⬜ **OPEN** | No `wasm-benchmark-report.json` with `gpuBackendObserved: true` |
| 2 | **Reliability** | Playwright parity green on **≥2 distinct GPU configs** | ⬜ **OPEN** | CI skips parity without adapter; no vendor matrix attached |
| 3 | **Integration** | Manual Controls smoke outside `testMode` — shader pick, params, input sources, recording | ⬜ **OPEN** | Checklist in [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md) not signed off |
| 4 | **Ops** | `wasm` + `test-wasm-e2e` jobs green **4 consecutive calendar weeks** on `main` | ⬜ **OPEN** | See [Weekly CI table](#weekly-ci-table) |

---

## Decision (2026-07-11)

### **STAY TIER B** — do not promote

Integration epics #817–#890 are closed; remaining work is **measurement**, not features. None of the four promotion gates have sufficient GPU-backed evidence. CI `test-wasm-e2e` green on `ubuntu-latest` **does not** satisfy gates 1–2 because Playwright skips GPU-dependent specs when no WebGPU adapter is present (see [CI interpretation](#ci-interpretation)).

**Demote?** No — WASM builds, unit tests pass, smoke API surface holds. Keep experimental opt-in.

**Next measurement actions (human + GPU hardware):**

1. On **discrete GPU** machine (e.g. NVIDIA GTX 1060+):  
   `npm run wasm:build && npm run build && WASM_GPU_TESTS=1 npm run test:wasm:bench`  
   Attach `test-results/wasm-benchmark-report.json` + `lspci` / `chrome://gpu` notes.

2. On **iGPU or second vendor** (Intel/AMD): repeat bench + parity.

3. Run [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md) Tests 1–5 **without** `testMode=1`; record pass/fail in [Evidence log](#evidence-log).

4. Continue weekly CI monitoring until 4 consecutive green weeks.

---

## Gate 1 — Performance benchmark

### Command

```bash
npm run wasm:build && npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench
```

### Benchmark matrix (3 shaders)

From [`tests/fixtures/parityMatrix.ts`](./tests/fixtures/parityMatrix.ts) → `BENCHMARK_MATRIX`:

| Shader | Category |
|--------|----------|
| `sim-fluid-feedback-coupled` | fluid |
| `gen-lichen-reaction-diffusion` | reaction-diffusion |
| `cyber-ripples` | audio-reactive |

### Promotion math

- `speedupRatio = wasm.avgFps / webgpu.avgFps` (fallback: `webgpu.avgTotalMs / wasm.avgTotalMs`)
- Gate met when **≥3** comparisons have `speedupRatio ≥ 1.25`
- WASM `getGPUTimings().available` is **always false** — compare wall-clock only

### Evidence slot

| Run date | Hardware | Report path | `promotionGateMet` | Notes |
|----------|----------|-------------|-------------------|-------|
| — | — | `test-results/wasm-benchmark-report.json` | — | **Not collected** |

Stub report (no GPU): [`test-results/wasm-benchmark-report.json`](./test-results/wasm-benchmark-report.json)

---

## Gate 2 — Playwright parity (≥2 GPU configs)

### Command

```bash
WASM_GPU_TESTS=1 npm run test:wasm:parity
```

### Matrix (5 shaders)

`sim-fluid-feedback-coupled`, `gen-lichen-reaction-diffusion`, `cyber-ripples`, `plasma`, `liquid`

### Evidence slot

| Run date | GPU / OS / Browser | Parity result | Report / run URL |
|----------|-------------------|---------------|------------------|
| — | — | — | — |

**Minimum:** one discrete + one integrated GPU, or two vendors (NVIDIA + AMD/Intel).

---

## Gate 3 — Controls integration (manual)

Outside `testMode`. See [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md).

| Check | Pass? | Date | Tester |
|-------|-------|------|--------|
| `?renderer=wasm` init, no crash | ⬜ | | |
| Shader browser → load effect | ⬜ | | |
| Param sliders → `zoom_params` | ⬜ | | |
| Input source switch (image/video/webcam) | ⬜ | | |
| Mouse / ripples on interactive shader | ⬜ | | |
| Recording start/stop + blob | ⬜ | | |
| Renderer switcher wasm ↔ webgpu | ⬜ | | |

---

## Gate 4 — Weekly CI table

Jobs: `wasm` (build + Jest WASM unit) and `test-wasm-e2e` (Playwright).  
Source: `main` branch push runs — [Actions](https://github.com/ford442/image_video_effects/actions/workflows/ci.yml).

| ISO week | `wasm` | `test-wasm-e2e` | Both green? |
|----------|--------|-----------------|-------------|
| 2026-W26 (Jun 23–29) | ❌ failures dominate | ❌ | **FAIL** |
| 2026-W27 (Jun 30–Jul 6) | ❌ | ❌ | **FAIL** |
| 2026-W28 (Jul 7–13) | ✅ Jul 10–11 pushes green | ✅ Jul 10–11 | **PARTIAL** (week not complete; Jul 5–8 failures) |
| 2026-W29+ | — | — | TBD |

**4 consecutive weeks:** **NOT MET** (as of 2026-07-11).

Recent green main pushes (both jobs): `29148209376`, `29144412949`, `29143957549`, `29125958617`, `29082223632` (2026-07-10 – 07-11).

---

## CI interpretation

`test-wasm-e2e` sets `WASM_GPU_TESTS=1` but runs on **GitHub `ubuntu-latest` without a WebGPU adapter**. Observed on run `29148209376`:

- ✅ `wasm-benchmark.spec.ts` → **getGPUTimings API surface** (no GPU needed)
- ⏭️ `wasm-benchmark.spec.ts` → **benchmark matrix** — skipped (`WebGPU adapter unavailable`)
- ⏭️ `renderer-parity.spec.ts` — skipped when backends fall back
- ✅ Smoke tests that only require build + test API — pass

**Implication:** CI green ≠ promotion gates 1–2 met. GPU runners or local hardware required.

---

## Evidence log

| Date | Collector | What | Result |
|------|-----------|------|--------|
| 2026-07-11 | Agent (Cloud VM) | `npm run test:wasm:unit` | **29/29 pass** |
| 2026-07-11 | Agent (Cloud VM) | Playwright bench/parity/smoke | **Blocked** — no `build/` (branch TS error in `webgpuDevicePolicy.test.ts`); VM has no GPU |
| 2026-07-11 | CI `29148209376` | `wasm` + `test-wasm-e2e` on main | **Green** — GPU specs skipped |
| 2026-07-11 | Review | Promotion decision | **STAY TIER B** |

---

## Attachments checklist (for PR / issue comment)

When closing promotion review, attach:

- [ ] `test-results/wasm-benchmark-report.json` (`gpuBackendObserved: true`)
- [ ] Hardware notes per run (GPU model, driver, browser, resolution)
- [ ] Playwright HTML report or `gh run` URL for parity on ≥2 configs
- [ ] Signed manual smoke table (Gate 3)
- [ ] Updated weekly CI table through gate week 4

---

## Related closed work

| Range | Topic |
|-------|-------|
| #817–#823 | C++ init / bridge / docs |
| #845–#849 | Manager forwarding, CI, tests |
| #886–#889 | Recording, parity API, Playwright suite |
| #885 | Umbrella integration epic |
