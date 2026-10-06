# WASM benchmark report (schema v3)

Written by `tests/wasm-benchmark.spec.ts` (`npm run test:wasm:bench`). The harness fixes and the reasons for them are in #1330 / #1357. The v3 metric (GPU ms, uncapped ms/frame, isolation) is the #1080 follow-up.

## Where it goes

| Path | When |
|---|---|
| `test-results/wasm-benchmark-report.json` | Every run, including the stub. Playwright wipes this folder on the next run. `wasm.yml` uploads it as an artifact. |
| `reports/data/wasm-benchmark-<platform>-<ISO>.json` | Runs that measured at least one shader. Override the folder with `WASM_BENCH_OUT_DIR`. Committing is a per-run choice. |

v2 had no `speedupMetric`, no uncapped leg and no isolation; its `speedupRatio` is always the FPS ratio.

`reports/data/wasm-benchmark-T4-2026-09-27-run{1,2}.json` are **v1**. They have no `schemaVersion`, store adapters as top-level `wasmAdapterSummary` / `webgpuAdapterSummary`, report `userAgent` (spoofed as Windows), and take p95 from a 5-sample tail.

## Running on a real GPU

```bash
SKIP_WASM_BUILD=1 npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench
# un-quantised timestamps (recommended for the gate):
WASM_GPU_TESTS=1 WASM_BENCH_DEV_FEATURES=1 npm run test:wasm:bench
```

`WASM_BENCH_DEV_FEATURES=1` adds `--enable-webgpu-developer-features --enable-dawn-features=allow_unsafe_apis`. Without it Chromium rounds timestamp-query to 100 µs buckets, which is coarse next to sub-millisecond passes. It is off by default (#1357 Q1).

The spec serves `build/` with `scripts/serve-isolated.mjs` (COOP `same-origin`, COEP `credentialless`), so `performance.now()` resolves to about 5 µs instead of about 100 µs. Shaders and thumbnails are same-origin, so they load unchanged. A leg that is not `crossOriginIsolated` fails the run.

`WASM_GPU_TESTS=1` switches the `chromium` Playwright project to:

- `channel: 'chromium'`, which is new headless: the full browser rather than `chromium-headless-shell`.
- The flags from `src/utils/gpuLaunchArgs.ts`:
  - `--enable-unsafe-webgpu --ignore-gpu-blocklist --use-webgpu-adapter=default` on every platform.
  - On Linux, also the Vulkan + ANGLE set. Windows keeps D3D12.
- `devices['Desktop Chrome']` without its spoofed user agent.

With it set, the run **fails** instead of skipping when:

- `requestAdapter()` returns null (`no GPU adapter`), or the adapter is SwiftShader / fallback.
- A leg does not come up as the requested renderer.
- The renderer's diagnostics report a dead device (`getDiagnostics().wasm.initialized` / `.webgpu.initialized`, `lastInitError`, `gpuErrors`).
- A leg's page is not cross-origin isolated.

Without it, the spec writes a stub report and skips.

## Fields

```jsonc
{
  "schemaVersion": 3,
  "generatedAt": "ISO-8601",
  "completed": true,              // false: the run stopped mid-matrix; results hold the shaders done so far
  "strictGpuMode": true,          // WASM_GPU_TESTS=1
  "gpuBackendObserved": true,     // at least one shader measured on both legs
  "benchmarkShaderIds": ["…"],
  "environment": {
    "platform": "linux",          // process.platform: the real host, not the UA
    "osRelease": "6.8.0-…",       // os.release()
    "browserVersion": "147.0.…",  // browser.version()
    "channel": "chromium",        // 'chromium-headless-shell' when not strict
    "launchArgs": ["--enable-unsafe-webgpu", "…"],
    "webgpuDeveloperFeatures": false, // un-quantised timestamps; off by default
    "timestampPeriodNs": 1,       // TS device; 0 = no timestamp-query
    "crossOriginIsolated": { "wasm": true, "webgpu": true },
    "adapters": { "wasm": "…", "webgpu": "…" }
  },
  "warmupFrames": 10,             // discarded before sampling (after the 2 s settle)
  "spoofedUserAgent": "… Windows …", // what the page saw; do not read the platform from it
  "results": [{
    "shaderId": "plasma",
    "backend": "wasm",            // or "webgpu"
    "timingSource": "wall-clock", // 'gpu-timestamp' | 'wall-clock' | 'unavailable'
    "avgFps": 58.9,
    "avgTotalMs": 4.1,
    "p95TotalMs": 5.2,            // = totalMsStats.p95
    "totalMsStats": { "n": 60, "p50": 4.0, "p95": 5.2, "max": 7.9, "mean": 4.1 },
    "fpsStats":     { "n": 60, "p50": 59.8, "p95": 60.1, "max": 60.2, "mean": 58.9 },
    "gpuTimingsAvailable": false,
    "gpuReadbacks": 12,           // distinct totalTime values: the real GPU sample count
    "uncappedMsPerFrame": 3.7,    // N frames without rAF, timed to GPU idle; absent if unavailable
    "passTimings": []             // only for 'gpu-timestamp' TS results
  }],
  "comparisons": [{
    "shaderId": "plasma",
    "wasmFps": 58.9, "webgpuFps": 47.1,
    "wasmAvgTotalMs": 4.1, "webgpuAvgTotalMs": 2.3,
    "wasmUncappedMsPerFrame": 3.7, "webgpuUncappedMsPerFrame": 4.1,
    "speedupRatio": 1.11,         // WASM-over-TS speed by speedupMetric (> 1 = WASM faster)
    "speedupMetric": "uncapped-ms", // 'gpu-ms' | 'uncapped-ms' | 'fps' | 'frame-ms' | 'none'
    "wasmTimingSource": "wall-clock",
    "webgpuTimingSource": "gpu-timestamp",
    "likeForLike": true,          // always true for gpu-ms / uncapped-ms
    "meetsPromotionGate": false,  // never true when likeForLike is false
    "gateReason": "fps (vsync-capped)" // or 'mixed timing sources'; absent when nothing to say
  }],
  "promotionGateMet": false,      // ≥ promotionMinShaders rows meet the gate
  "promotionMinShaders": 3,
  "promotionSpeedupRatio": 1.25
}
```

### Statistics

`totalMsStats` and `fpsStats` come from `src/utils/benchmarkStats.ts`. They are computed in the page over **every** sampled frame, excluding the warm-up. Percentiles are nearest-rank, and an empty input gives zeros. `totalMsStats` counts only frames with `gpu.totalTime > 0`. `runBenchmark` still returns `samples` (the last 5), but nothing derives a percentile from that tail anymore.

### Speedup metric

FPS is capped at the display rate: on the T4 both backends drew 60 fps and the ratio could not separate them (`reports/wasm-promotion-evidence-2026-09-27.md`). `speedupRatio` now comes from the first metric both legs have (`src/utils/benchmarkSpeedup.ts`):

1. **`gpu-ms`**: both legs report `timingSource: 'gpu-timestamp'`. The ratio is TS `totalMsStats.p50` over WASM `totalMsStats.p50`. It uses the median because readbacks repeat values between frames. Check `gpuReadbacks` for the real sample size.
2. **`uncapped-ms`**: both legs have `uncappedMsPerFrame`. The ratio is TS over WASM.
3. **`fps`**: the old ratio, WASM fps over TS fps (`frame-ms` when FPS is missing). The pre-#1080 rule still applies: mixed timing sources never meet the gate. When both legs run at 99% of 60 fps or more, the row gets `gateReason: 'fps (vsync-capped)'`.

### Timing sources

Both renderers use `timestamp-query` when the device has it:

- TS: `src/renderer/webgpu/WebGPUTiming.ts`. It reads back at most every 250 ms.
- WASM: `wasm_renderer/timing.cpp`, added in #1314 D, after the T4 run.

`getGPUTimings()` reports `'gpu-timestamp'` only after a readback has decoded, and `'wall-clock'` before that (CPU encode/submit time). `BENCH_FRAMES` is 180, which gives about 12 TS readbacks at 60 fps.

**Span parity.** The two `totalTime` values are close but not identical:

- TS `'all'` runs from the earliest begin to the latest end over every profiled pass in the frame. That includes the input copy and scale, chores and present.
- WASM total runs from the first profiled compute pass's begin to the present pass's end (`timing.cpp` `DecodePhaseTimings`). Uniform and input uploads are queue writes, not passes, so they are not in the span.

On a generative input the TS frame has no copy pass, and the two spans line up. Compare `passTimings` when a ratio looks off. A WASM frame with no compute pass, such as an empty slot, never resolves and stays `'wall-clock'`.

### Uncapped mode

`__pixelocity__.runUncappedBenchmark(frames = 120, warmupFrames = 10)` calls the backend's `benchmarkUncapped`. The backend:

1. Stops its rAF loop.
2. Waits for the GPU to go idle.
3. Renders N frames back to back, one submit each.
4. Waits for `onSubmittedWorkDone`.
5. Returns `{ frames, wallMs, msPerFrame }` and restarts the loop.

Per backend:

- TS: this runs inside the render worker by default (`benchmarkUncapped` RPC), so the page-to-worker hop is not timed.
- WASM: the `updateUniforms` export renders one frame. The GPU-idle wait goes through the `requestWorkDoneMark` export, which queues `wgpuQueueOnSubmittedWorkDone` (AllowSpontaneous) and calls `Module.__pxWorkDone` from JS. No ASYNCIFY is involved. This is measurement tooling, which the R&D freeze allows (`WASM_BACKEND_POLICY.md` rule 1a).

Both measure the same wall span, from the first submit to GPU idle, so the row is like-for-like whatever `timingSource` says.

### Leg isolation

For each shader:

1. The WASM leg runs on the test page.
2. That page navigates to `about:blank`, which stops its render loop.
3. The TS leg runs on a fresh page that is brought to the front (to avoid background-tab rAF throttling).
4. The TS page's adapter summary is read **before** the page closes, and the close happens in `finally`.

## Not covered here

The WASM adapter-failure message in `wasm_renderer/device.cpp` still says the problem "commonly happens on Windows with Chrome/Edge". That is C++, and it is deferred while the WASM renderer is frozen.
