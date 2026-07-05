# WASM Tier B → Tier A Promotion Tracking

**Policy:** [`WASM_BACKEND_POLICY.md`](./WASM_BACKEND_POLICY.md)  
**Epic:** [#885](https://github.com/ford442/image_video_effects/issues/885)  
**Docs refresh:** [#890](https://github.com/ford442/image_video_effects/issues/890)

**Current verdict:** **Tier B — experimental opt-in.** TypeScript WebGPU remains the production default. Do not describe WASM as production-ready until **all four gates** below are checked with attached evidence.

---

## Promotion gates (all required)

Copy this checklist into promotion PRs/issues. Each gate needs **linked evidence** — not checkbox claims alone.

### Gate 1 — Performance

- [ ] WASM ≥ **1.25×** TS WebGPU (FPS or frame time) on **≥ 3** priority shaders (fluids, reaction-diffusion, multi-slot stacks)

**How to measure:**

```bash
npm run wasm:build && npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench
```

**Evidence required:**

- Attach `test-results/wasm-benchmark-report.json`
- Report must show `promotionGateMet: true` **or** manual table with per-shader `speedupRatio` ≥ 1.25 on ≥ 3 shaders
- Note hardware: GPU model, browser version, display scale

**Benchmark shaders (default):** `sim-fluid-feedback-coupled`, `gen-lichen-reaction-diffusion`, `cyber-ripples` (see `tests/fixtures/parityMatrix.ts`)

---

### Gate 2 — Reliability (multi-GPU parity)

- [ ] Playwright parity suite **green** on **≥ 2** distinct GPU configs

**How to run:**

```bash
WASM_GPU_TESTS=1 npm run test:wasm:parity
# Full suite including smoke + bench:
WASM_GPU_TESTS=1 npm run test:wasm:full
```

**Evidence required:**

- CI run URL **or** local Playwright HTML report (`playwright-report/`)
- Table of GPU configs tested (vendor, device, OS, browser)
- `tests/renderer-parity.spec.ts` green on each config (no skipped parity cases due to init failure)

**CI note:** GitHub-hosted runners have no WebGPU adapter — run on self-hosted GPU machines or trigger `wasm-gpu-manual` workflow dispatch.

---

### Gate 3 — Integration (Controls flow)

- [ ] No **P0** gaps in normal Controls flow (shader pick, params, input sources, recording) — exercised outside `testMode=1` only

**Manual smoke:** [`WASM_SMOKE_TEST.md`](./WASM_SMOKE_TEST.md) checklist on WASM backend.

**Evidence required:**

- Issue/PR comment listing Controls paths verified (shader dropdown, slot stack, generative/image/video/webcam, audio, recording, screenshots)
- Any remaining P1/P2 gaps filed as issues with WASM label

**July 2026 baseline (closed in tree):** #886 recording readback, #887 manager forwarding, #888 FFT/audio parity — re-verify on target GPUs before promotion sign-off.

---

### Gate 4 — Ops (sustained CI health)

- [ ] CI jobs `wasm` + `test-wasm-e2e` green for **4 consecutive weeks** without emdawn/emsdk breakage

**Evidence required:**

- Link to 4 weeks of green `main` CI history (or release branch) for both jobs
- Note any `SKIP_WASM_BUILD=1` usage — acceptable for app build job, but `wasm` job must still compile from source

**Track here:**

| Week ending (UTC) | `wasm` job | `test-wasm-e2e` job | Notes |
|-------------------|------------|---------------------|-------|
| _TBD_ | ⬜ | ⬜ | |
| _TBD_ | ⬜ | ⬜ | |
| _TBD_ | ⬜ | ⬜ | |
| _TBD_ | ⬜ | ⬜ | |

---

## Evidence log (append-only)

Maintainers append rows when new benchmark or parity data is collected.

| Date | Contributor | Hardware / browser | Artifact | Gate(s) | Result |
|------|-------------|-------------------|----------|---------|--------|
| _none yet_ | — | — | — | — | Promotion not started |

---

## Prerequisites already closed (do not re-open)

| Batch | Issues | Status |
|-------|--------|--------|
| C++ init / format / limits | #817–#823, parent #799 | ✅ Closed — in tree |
| Integration / CI / tests (June) | #845–#849 | ✅ Closed |
| July glue + parity + tests | #886–#889 | ✅ Implemented in tree (July 2026) |

---

## Demotion triggers (reminder)

Per policy, consider **hiding the WASM toggle** if:

- Benchmarks show **no meaningful win** on target shader classes, **or**
- Init failure rate is unacceptably high on target browsers after #817–#822 fixes

---

## Related docs

- [`WASM_RENDERER_GAP_ANALYSIS.md`](./WASM_RENDERER_GAP_ANALYSIS.md) — technical gaps + July 2026 status
- [`wasm_renderer/STATUS.md`](./wasm_renderer/STATUS.md) — implementation snapshot
- [`WASM_TEST_SUITE.md`](./WASM_TEST_SUITE.md) — how to run tests and benchmarks
