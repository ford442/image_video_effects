# WASM / real-GPU runtime invariants

Single source of truth: [`src/contracts/wasm_runtime_invariants.json`](../src/contracts/wasm_runtime_invariants.json).
CI: `npm run verify:device-policy` (includes these checks) and `npm run verify:wasm-invariants`.

These are **regression locks** for bugs already fixed on 2026-08-30/31. They do **not** replace a Pascal/Chrome confirm. Promotion stays HOLD until the maintainer marks GPU-CONFIRMED in [`reports/wasm_promotion_evidence.md`](../reports/wasm_promotion_evidence.md).

| Invariant | Issue / tracker | Guard |
|-----------|-----------------|--------|
| Do not call `wgpuSurfacePresent` (acquire + blit + submit, then return; JS rAF drives the loop) | unnumbered — `memory/2026-08-31.md` present abort | C++ scan of `wasm_renderer/**/*.cpp` for `wgpuSurfacePresent(`; WASM import-section reader on `public/wasm/pixelocity_wasm.wasm` (`scripts/wasm_import_table.js`, section id 2) |
| `samplerDesc.maxAnisotropy = 1` before all three `wgpuDeviceCreateSampler` calls (filtering, non-filtering, comparison) | unnumbered — `memory/2026-08-31.md` Invalid Sampler | Source order check in `wasm_renderer/resources.cpp` |
| historyTex probe ladder `[[2048,8],[1024,8],[1024,4],[1024,1]]` and sessionStorage `px_history_oom_cap` | **#1204** | Parse `vramBudget.ts` + `historyTexProbe.ts` + `HISTORY_DEPTH` against the JSON rungs |
| Catalog WGSL stays `rgba32float`; WASM rewrites storage decls to the probed colour format (`rgba16float` after a yes probe) | **#1205** | `wgslFormatRewrite.ts` + `RewriteWgslStorageFormats` in `wasm_internal.cpp` + Rgba16Float probe path in `device.cpp` |
| Chores dispatch ceiling `maxComputeWorkgroupsPerDimension` **65535**; 2D `@workgroup_size(8,8)` — never `ceil(w*h/64)` as 1D | **#1200** (flatten `2048²/64=65536`) | `workgroups2d` + `assertDispatchWithinLimits` on all five `GpuChoresHost` passes; Jest 2048² and oversized |
| After exclusive JS→WASM switch, re-upload current image/video then `resyncShaderStack` | **#1206** | `rebindMediaAfterBackendSwitch` present in `inputSourceBridge.ts` and called from `RendererManager`; Playwright smoke (skips without adapter) |

## What this does not do

- Does not rebuild `public/wasm/*` (this VM’s emcc cannot). The import-table gate asserts the **committed** artifact.
- Does not close GitHub issues. Real-GPU confirmation is maintainer-owned.
- Does not change catalog workgroup contracts (`workgroup_dispatch.json` stays 16×16). gpu-chores remain 8×8 (`exemptPaths`).
