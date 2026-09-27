# WASM Promotion Evidence — 2026-09-27

**Issue:** #1080 · **Parent:** #1076 · **Related:** `WASM_BACKEND_POLICY.md`, `WASM_PROMOTION_TRACKING.md`, #885 / #890
**Commit tested:** `5e245f49fc12ec287b6715312592c28f402b4372` (`origin/main` at run time. This was inferred from commit timestamps: the next commits on `main` only add the benchmark JSON.)
**Decision:** **Stay Tier B — freeze as R&D.** Do not promote.

## Summary

Gate 1 (`test:wasm:bench`, `WASM_GPU_TESTS=1`) was run twice on a real GPU (Tesla T4). Neither run met the gate: run 1 passed on 1 of 3 shaders, run 2 on 0 of 3.

- **Frame rate is identical.** Both backends are vsync-bound at 60 fps on all three priority shaders. The single run-1 pass (`gen-lichen-reaction-diffusion`, 1.38×) came from a TS frame drop that did not reproduce in run 2 (0.99×).
- **WASM has lower CPU submit time.** It was lower in 6 of 6 measurements: 20–66% lower (median about 46%), which is 0.04–0.26 ms per frame. That is roughly 1–2% of a 16.7 ms frame budget and is not user-visible at these workloads.
- **GPU execution time was not measured** (`gpuTimingsAvailable: false` on both backends). Both backends submit the same WGSL to the same Dawn instance and driver (emdawnwebgpu calls the browser's `navigator.gpu`), so a GPU-side 1.25× advantage is not expected.

## Test environment

| | |
|---|---|
| Host | Google Colab (Linux container) |
| GPU | NVIDIA Tesla T4 (Turing, device `0x1eb8`), NVIDIA Vulkan ICD |
| Browser | Playwright bundled Chromium headless shell 149.0.7827.55 |
| Node | v24.21.0 |
| Build | `SKIP_WASM_BUILD=1 npm run build`, prebuilt `public/wasm/*` |
| Cross-origin isolated | No, so `performance.now()` resolution is about 100 µs |
| Launch flags (both runs) | `--enable-unsafe-webgpu --enable-features=Vulkan --use-vulkan=native --use-angle=vulkan --disable-vulkan-surface --ignore-gpu-blocklist` |
| Extra flags (run 2 only) | `--enable-dawn-features=allow_unsafe_apis --enable-webgpu-developer-features` |

The `userAgent` field in the report JSON says Windows. That string comes from Playwright's `devices['Desktop Chrome']` spoof, not from the real platform.

**Adapters observed (run 2):**

- **WASM:** `nvidia | 0x1eb8 | turing`; features `[float32-filterable]`; surface `rgba8unorm`
- **TS WebGPU:** HighPerformance attempt; features `[float32-filterable, timestamp-query, subgroups]`; device limits maxTex2D 8192, computeInvocations 256; surface `rgba8unorm`

Run 1's WASM adapter summary has an empty device-id field (`nvidia |  | turing`). It is the same GPU.

## Gate 1 results

"Submit ms" is the wall-clock CPU time per frame (`avgTotalMs` / `p95TotalMs`). The FPS ratio is the gate metric as currently implemented. Target: ≥ 1.25× on ≥ 3 shaders.

The p95 values are not true p95s. `runBenchmark` returns only the last 5 samples, so `p95TotalMs` is roughly the max of the last 5 frames. See [Interpretation](#interpretation), point 4.

### Run 1 (2026-09-27 01:44 UTC, base flags)

| Shader | WASM fps | TS fps | FPS ratio | WASM submit ms (avg / p95) | TS submit ms (avg / p95) | Gate |
|---|---|---|---|---|---|---|
| sim-fluid-feedback-coupled | 60.02 | 58.84 | 1.02 | 0.12 / 0.2 | 0.35 / 0.2 | ✗ |
| gen-lichen-reaction-diffusion | 60.00 | 43.50 | 1.38 | 0.15 / 0.1 | 0.19 / 0.2 | ✓ |
| cyber-ripples | 60.00 | 59.98 | 1.00 | 0.14 / 0.2 | 0.24 / 0.1 | ✗ |

**NOT MET (1/3).**

### Run 2 (2026-09-27 01:51 UTC, + developer flags)

| Shader | WASM fps | TS fps | FPS ratio | WASM submit ms (avg / p95) | TS submit ms (avg / p95) | Gate |
|---|---|---|---|---|---|---|
| sim-fluid-feedback-coupled | 60.00 | 59.99 | 1.00 | 0.17 / 0.2 | 0.32 / 0.1 | ✗ |
| gen-lichen-reaction-diffusion | 59.52 | 59.99 | 0.99 | 0.28 / 2.4 | 0.52 / 0.3 | ✗ |
| cyber-ripples | 60.00 | 60.39 | 0.99 | 0.20 / 1.0 | 0.46 / 0.4 | ✗ |

**NOT MET (0/3).**

## Interpretation

1. **The FPS ratio can't tell the backends apart on this hardware.** Both backends finish well inside the 16.7 ms vsync budget, so the ratio only confirms that both are fast enough. With FPS capped at 60, a TS baseline would have to fall below 48 fps before any shader could reach 1.25×.
2. **Lichen's 1.38× was transient.** It did not reproduce in run 2. The likely cause is a TS frame drop inside the sample window. Two candidates:
   - Pipeline compilation.
   - A harness bias. `benchBackend` does not navigate the WASM page away after its leg, so the WASM page keeps rendering its shader while the TS leg runs on a second page. This competes with TS for the same GPU and CPU, and could only make TS look slower, never WASM.
3. **The CPU submit advantage is consistent but small.** WASM encodes and submits faster in every measurement. It is not an artifact of what each backend times. The WASM span (`frame.cpp`, `Render()` start through `PresentToSurface()`) covers uniform upload and present. The TS span (`slotDispatch.ts` `wallStart` → submit) starts after `writeUniforms` and the input copy. So WASM times more work and still comes in lower. Since the timer resolution is about 100 µs, treat the magnitudes as indicative only. The savings would only matter on CPU-bound workloads, such as many passes per frame on a low-end CPU.
4. **The tail numbers can't be compared.** `p95TotalMs` is computed from `samples.slice(-5)`, the last 5 frames only. That explains why some TS means exceed their own "p95": the slow frames fell outside the last 5. WASM's higher lichen (2.4 ms) and cyber-ripples (1.0 ms) values are single-frame maxima inside that window. With about 100 µs timer resolution on top of that, the harness cannot rank the two backends' tails.
5. **GPU time is unmeasured, but the expected answer is parity.** The TS adapter exposes `timestamp-query` under developer flags, but `runBenchmark` doesn't use it, and the WASM device doesn't request the feature.

## Other gates

| Gate | Status |
|---|---|
| 2 Reliability (parity + pixel-diff, ≥2 configs) | Not run this session |
| 3 Integration (manual Controls smoke) | Not run |
| 4 Ops (4 green weeks on `main`) | Not assessed |

Gates 2–4 are only required to promote. They are not needed for a Stay-B decision.

## Decision

**Stay Tier B and freeze as R&D.** This meets the demotion trigger in `WASM_BACKEND_POLICY.md` ("no meaningful win on target shader classes"). The tree is frozen, not deleted.

- TS WebGPU remains the Tier A default.
- WASM stays reachable only via `?renderer=wasm`, and the UI toggle gets hidden (#1329).
- The feature freeze continues: parity bugs only.
- **GraphRunner stays TS-only.** There will be no C++ multipass graph port.
- `public/wasm/*` is no longer treated as a hot path in PR narratives, and WASM CI jobs get trimmed (#1329).
- The `wasm_renderer/` tree is kept for R&D and possible future Dawn-native work outside browser scope.

## What would reopen this

- A GPU-timestamp or uncapped benchmark showing WASM ≥ 1.25× on ≥ 3 priority shaders across ≥ 2 hardware configs, **or**
- A CPU-bound target where the ~0.1–0.25 ms/frame encode savings become user-visible. Testing that would first require a multipass workload on WASM, which is currently an anti-goal.

## Artifacts

| Run | Retained copy | Original |
|---|---|---|
| 1 | [`reports/data/wasm-benchmark-T4-2026-09-27-run1.json`](./data/wasm-benchmark-T4-2026-09-27-run1.json) | `test-results/wasm-benchmark-a_9-26-26.json` (verbatim) |
| 2 | [`reports/data/wasm-benchmark-T4-2026-09-27-run2.json`](./data/wasm-benchmark-T4-2026-09-27-run2.json) | `test-results/wasm-benchmark-b_9-26-26.json` |

The run-2 original starts with a free-text line recording the extra launch flags, so it is not valid JSON. The copy in `reports/data/` drops that line and is otherwise identical. The flags are listed in [Test environment](#test-environment).

Playwright wipes `test-results/` at the start of every run, so copy artifacts to `reports/data/` before rerunning.

## Local harness changes used for these runs

These changes were not committed:

- `playwright.config.ts`: GPU launch args, gated on `WASM_GPU_TESTS=1`.
- `tests/wasm-benchmark.spec.ts`: moved `tsPage.close()` after `collectAdapterSummary()`. The committed spec still closes `tsPage` first and then reads adapter info from the closed page.

These changes and the other harness fixes are tracked in #1330. Optional GPU-timing work is tracked in #1331.

## Appendix: reproducing on a Linux GPU VM

```bash
apt-get install -y -qq vulkan-tools
vulkaninfo --summary | grep -iE "deviceName|driverName"   # must show the NVIDIA GPU, not llvmpipe
export XDG_RUNTIME_DIR=/tmp WASM_GPU_TESTS=1
npm ci && npx playwright install chromium
SKIP_WASM_BUILD=1 npm run build
PLAYWRIGHT_HTML_OPEN=never npx playwright test tests/wasm-benchmark.spec.ts --project=chromium --reporter=list
cp test-results/wasm-benchmark-report.json reports/data/wasm-benchmark-<gpu>-<date>.json
```

Before trusting any numbers, confirm that both adapter summaries in the JSON name the real GPU vendor. A SwiftShader or fallback adapter invalidates the run.

On Windows, keep only `--enable-unsafe-webgpu --ignore-gpu-blocklist`. The Vulkan/ANGLE flags can push Chrome off D3D12 or break the adapter.
