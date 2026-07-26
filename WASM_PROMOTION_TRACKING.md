# WASM Tier B → Tier A Promotion Tracking

**Policy:** [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md)  
**Status doc:** [`wasm_renderer/STATUS.md`](./wasm_renderer/STATUS.md)  
**Test how-to:** [`WASM_TEST_SUITE.md`](./WASM_TEST_SUITE.md) · [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md)  
**Umbrella (closed):** [#885](https://github.com/ford442/image_video_effects/issues/885)  
**Docs refresh (closed):** [#890](https://github.com/ford442/image_video_effects/issues/890)

**Current tier:** **B — Experimental (opt-in)**  
**Last evidence review:** 2026-07-26 (Phase 1 hygiene; GPU gates still open)

---

## Decision (2026-07-26) — reaffirm STAY TIER B

Phase 1 hygiene landed (#1013): single `npm run build` path documented, emcc flag dedupe, dormant `-sg.wgsl` probe removed, input-source test coverage expanded. **Promotion gates 1–4 remain open** — GPU bench/parity/smoke require discrete-GPU human runs; Cloud VM cannot observe WebGPU.

**Action:** Run checklist below on ≥2 GPU configs. Until then: **STAY TIER B**.

## Decision (2026-07-19) — reaffirm STAY TIER B

Foundation Wave 2 (#965) closed binding-13 parity in C++ and wired TS device policy, but **promotion gates 1–4 remain open**. Measurement harness now writes enriched bench reports (`benchmarkShaderIds`, `wasmAdapterSummary`, `webgpuAdapterSummary`, `userAgent`); CI uploads `wasm-benchmark-report` artifact. **GPU-backed evidence still required** from a discrete-GPU workstation.

---

## Promotion gates (all must pass)

| # | Gate | Threshold | Status | Evidence |
|---|------|-----------|--------|----------|
| 1 | **Performance** | WASM ≥ **1.25×** TS FPS (or inverse frame-time) on **≥3** benchmark shaders | ⬜ **OPEN** | VM stub only — [`reports/wasm-benchmark-report-stub-2026-07-19.json`](./reports/wasm-benchmark-report-stub-2026-07-19.json) has `gpuBackendObserved: false` |
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
   `npm run build && WASM_GPU_TESTS=1 npm run test:wasm:bench`  
   (`prebuild` runs `wasm:build` once; use `SKIP_WASM_BUILD=1 npm run build` only when reusing committed artifacts.)  
   Attach `test-results/wasm-benchmark-report.json` + `lspci` / `chrome://gpu` notes.

2. On **iGPU or second vendor** (Intel/AMD): repeat bench + parity.

3. Run [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md) Tests 1–5 **without** `testMode=1`; record pass/fail in [Evidence log](#evidence-log).

4. Continue weekly CI monitoring until 4 consecutive green weeks.

---

## Gate 1 — Performance benchmark

### Command

```bash
npm run build
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
| 2026-07-26 | Cloud VM — QEMU (no WebGPU) | [`reports/wasm-benchmark-report-stub-2026-07-26.json`](./reports/wasm-benchmark-report-stub-2026-07-26.json) | `false` | Post–Phase 1 hygiene VM validation; **not promotion evidence** |
| 2026-07-19 | Cloud VM — `Device 1234:1111` (QEMU, no WebGPU) | [`reports/wasm-benchmark-report-stub-2026-07-19.json`](./reports/wasm-benchmark-report-stub-2026-07-19.json) | `false` | `gpuBackendObserved: false`; backends fell back — **not promotion evidence** |
| — | Discrete GPU (NVIDIA+) | `test-results/wasm-benchmark-report.json` | — | **Awaiting human run** |

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
| 2026-07-26 | Cloud VM — QEMU / Linux / Chromium 149 | **6 skipped, 1 failed** — no WebGPU adapter | Local: `WASM_GPU_TESTS=1 npm run test:wasm:parity` |
| 2026-07-19 | Cloud VM — QEMU / Linux / Chromium 149 | **Skipped** (7/7) — no WebGPU adapter | Local run: `WASM_GPU_TESTS=1 npm run test:wasm:parity` |
| — | Discrete GPU | — | **Awaiting human run** |
| — | Second vendor (iGPU / AMD) | — | **Awaiting human run** |

**Minimum:** one discrete + one integrated GPU, or two vendors (NVIDIA + AMD/Intel).

---

## Gate 3 — Controls integration (manual)

Outside `testMode`. See [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md).

| Check | Pass? | Date | Tester |
|-------|-------|------|--------|
| `?renderer=wasm` init, no crash | ⬜ | | Requires GPU browser — see [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md) |
| Shader browser → load effect | ⬜ | | |
| Param sliders → `zoom_params` | ⬜ | | |
| Input source switch (image/video/webcam) | ⬜ | | |
| Mouse / ripples on interactive shader | ⬜ | | |
| Recording start/stop + blob | ⬜ | | |
| Renderer switcher wasm ↔ webgpu | ⬜ | | |

**Blocked in Cloud VM** (no WebGPU, no interactive Controls). Run `npm start` on a GPU workstation without `?testMode=1`. Re-validated 2026-07-26 after Phase 1 hygiene — still blocked.

---

## Gate 4 — Weekly CI table

Jobs: `wasm` (build + Jest WASM unit) and `test-wasm-e2e` (Playwright).  
Source: `main` branch push runs — [Actions](https://github.com/ford442/image_video_effects/actions/workflows/ci.yml).

| ISO week | `wasm` | `test-wasm-e2e` | Both green? |
|----------|--------|-----------------|-------------|
| 2026-W26 (Jun 23–29) | ❌ failures dominate | ❌ | **FAIL** |
| 2026-W27 (Jun 30–Jul 6) | ❌ | ❌ | **FAIL** |
| 2026-W28 (Jul 7–13) | ✅ Jul 10–11 pushes green | ✅ Jul 10–11 | **PARTIAL** (week not complete; Jul 5–8 failures) |
| 2026-W29 (Jul 14–20) | ✅ `wasm` green on Jul 14–18 pushes | ❌ `test` job fails → e2e **skipped** | **FAIL** |
| 2026-W30+ | — | — | TBD |

**4 consecutive weeks:** **NOT MET** (as of 2026-07-26).

Recent main CI pattern (Jul 14–18): `wasm` ✅, `test` ❌, `test-wasm-e2e` skipped (needs `test` green). Example runs: `29645534494`, `29645412792`, `29645154775`.

Prior green main pushes (both jobs): `29148209376`, `29144412949`, `29143957549`, `29125958617`, `29082223632` (2026-07-10 – 07-11).

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
| 2026-07-19 | Agent (Cloud VM) | Bench harness polish | Report schema + `getAdapterSummary` in test API; CI bench artifact upload |
| 2026-07-19 | Agent (Cloud VM) | `WASM_GPU_TESTS=1 npm run test:wasm:bench` | **Skipped** — `gpuBackendObserved: false`; stub → [`reports/wasm-benchmark-report-stub-2026-07-19.json`](./reports/wasm-benchmark-report-stub-2026-07-19.json) |
| 2026-07-19 | Agent (Cloud VM) | `WASM_GPU_TESTS=1 npm run test:wasm:parity` | **7/7 skipped** — no WebGPU adapter |
| 2026-07-19 | Agent (Cloud VM) | `lspci` | `Device 1234:1111` (QEMU VGA — not a real GPU) |
| 2026-07-19 | Review | Promotion decision | **STAY TIER B** — gates 1–4 open; human GPU runs required |
| 2026-07-26 | Agent (Cloud VM) | Phase 1 hygiene (#1013) | Build dedupe, `-sg` probe removed, input tests; bridge `uploadImageData` guard |
| 2026-07-26 | Agent (Cloud VM) | `WASM_GPU_TESTS=1 npm run test:wasm:bench` | **Skipped** — `gpuBackendObserved: false`; stub → [`reports/wasm-benchmark-report-stub-2026-07-26.json`](./reports/wasm-benchmark-report-stub-2026-07-26.json) |
| 2026-07-26 | Agent (Cloud VM) | `WASM_GPU_TESTS=1 npm run test:wasm:parity` | **6 skipped, 1 failed** — no WebGPU adapter |
| 2026-07-26 | Review | Promotion decision | **STAY TIER B** — Phase 1 complete; gates 1–4 open; human GPU runs required |

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

## Follow-up: GraphRunner WASM parity ([#929](https://github.com/ford442/image_video_effects/issues/929))

Tier C multipass graphs ship on the **TypeScript WebGPU** path only ([`docs/MULTIPASS_GRAPH.md`](./docs/MULTIPASS_GRAPH.md)). Port `GraphRunner` + copy barriers to `wasm_renderer/frame.cpp` before promoting graph-heavy sims to WASM Tier A evidence runs.
