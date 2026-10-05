# WASM benchmark report (schema v2)

Written by `tests/wasm-benchmark.spec.ts` (`npm run test:wasm:bench`). The harness fixes and the reasons for them are in #1330 / #1357.

## Where it goes

| Path | When |
|---|---|
| `test-results/wasm-benchmark-report.json` | Every run, including the stub. Playwright wipes this folder on the next run. `wasm.yml` uploads it as an artifact. |
| `reports/data/wasm-benchmark-<platform>-<ISO>.json` | Runs that measured at least one shader. Override the folder with `WASM_BENCH_OUT_DIR`. Committing is a per-run choice. |

`reports/data/wasm-benchmark-T4-2026-09-27-run{1,2}.json` are **v1**. They have no `schemaVersion`, store adapters as top-level `wasmAdapterSummary` / `webgpuAdapterSummary`, report `userAgent` (spoofed as Windows), and take p95 from a 5-sample tail.

## Running on a real GPU

```bash
SKIP_WASM_BUILD=1 npm run build
WASM_GPU_TESTS=1 npm run test:wasm:bench
```

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

Without it, the spec writes a stub report and skips.

## Fields

```jsonc
{
  "schemaVersion": 2,
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
    "passTimings": []             // only for 'gpu-timestamp' TS results
  }],
  "comparisons": [{
    "shaderId": "plasma",
    "wasmFps": 58.9, "webgpuFps": 47.1,
    "wasmAvgTotalMs": 4.1, "webgpuAvgTotalMs": 2.3,
    "speedupRatio": 1.25,         // WASM fps / TS fps (or inverse frame-time ratio)
    "wasmTimingSource": "wall-clock",
    "webgpuTimingSource": "gpu-timestamp",
    "likeForLike": false,
    "meetsPromotionGate": false,  // never true when likeForLike is false
    "gateReason": "mixed timing sources"
  }],
  "promotionGateMet": false,      // ≥ promotionMinShaders rows meet the gate
  "promotionMinShaders": 3,
  "promotionSpeedupRatio": 1.25
}
```

### Statistics

`totalMsStats` and `fpsStats` come from `src/utils/benchmarkStats.ts`. They are computed in the page over **every** sampled frame, excluding the warm-up. Percentiles are nearest-rank, and an empty input gives zeros. `totalMsStats` counts only frames with `gpu.totalTime > 0`. `runBenchmark` still returns `samples` (the last 5), but nothing derives a percentile from that tail anymore.

### Timing sources

The TS renderer uses `timestamp-query` when the device supports it (`src/renderer/webgpu/WebGPUTiming.ts`). The WASM renderer's `getGPUTimings()` is always wall-clock. A row with different sources still reports `speedupRatio`, but it cannot meet the promotion gate. Giving WASM GPU timestamps needs C++ changes, and the WASM renderer is frozen R&D (#1080).

### Leg isolation

For each shader:

1. The WASM leg runs on the test page.
2. That page navigates to `about:blank`, which stops its render loop.
3. The TS leg runs on a fresh page that is brought to the front (to avoid background-tab rAF throttling).
4. The TS page's adapter summary is read **before** the page closes, and the close happens in `finally`.

## Not covered here

The WASM adapter-failure message in `wasm_renderer/device.cpp` still says the problem "commonly happens on Windows with Chrome/Edge". That is C++, and it is deferred while the WASM renderer is frozen.
