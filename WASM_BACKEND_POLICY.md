# WASM Backend Support Policy (Tier B)

**Decision:** June 2026 — **Option B: Opt-in experimental backend**

The TypeScript WebGPU renderer is the **default production path**. The C++ Emscripten WASM renderer is an **experimental, opt-in performance backend** until promotion criteria are met.

## Support tiers

| Tier | Backend | User-facing | SLA |
|------|---------|-------------|-----|
| **A — Production** | TypeScript WebGPU | Default; recommended | Full feature parity; must work on supported browsers |
| **B — Experimental** | C++ WASM (`?renderer=wasm`, Controls switcher) | Labeled **Experimental (C++)** | Must not crash app; best-effort parity; no guarantee on edge GPUs |
| Fallback | Canvas2D (`js`) | Automatic when WebGPU unavailable | No shader effects |

WASM is **never** an automatic fallback. Users must explicitly choose it.

## How to enable (developers / power users)

```
http://localhost:3000/?renderer=wasm
```

Or use the **Renderer** switcher in Controls → WASM (shows experimental badge).

## Promotion gate (Tier B → Tier A)

Promote WASM to full production support only when **all** are true:

1. **Performance:** WASM ≥ **1.25×** TS WebGPU (FPS or frame time) on **≥3** priority shaders (fluids, reaction-diffusion, multi-slot stacks) — measured via `npm run test:wasm:bench` with `WASM_GPU_TESTS=1`
2. **Reliability:** Playwright parity suite green on **≥2** distinct GPU configs (document hardware in issue/PR)
3. **Integration:** No P0 gaps in normal Controls flow (shader pick, params, input sources, recording) — not just `testMode`
4. **Ops:** CI `wasm` + `test-wasm-e2e` jobs green for **4 consecutive weeks** without emdawn/emsdk breakage

## Demotion gate (Tier B → remove)

Archive or remove the WASM path if:

- Benchmark pass shows **no meaningful win** on target shader classes, **or**
- Init failure rate is unacceptably high on target browsers after #817–#822 fixes

Demotion action: hide UI toggle, keep `wasm_renderer/` as R&D or move to separate branch; stop committing `public/wasm/*` binaries.

## Engineering rules while Tier B

1. **TS first:** New renderer features land in `WebGPURenderer` + `RendererManager`; WASM ports are follow-ups, not blockers
2. **No dual-SLA bugs:** P0 fixes target TS path; WASM gets P1 unless WASM-only regression
3. **CI:** WASM must **build** on every PR (`wasm` job); parity/benchmark Playwright tests may skip without GPU
4. **Docs:** Do not describe WASM as "Phase 3 complete / production ready" — see `wasm_renderer/STATUS.md`

## Related docs

- [`WASM_RENDERER_GAP_ANALYSIS.md`](./WASM_RENDERER_GAP_ANALYSIS.md) — technical gaps
- [`WASM_TEST_SUITE.md`](./WASM_TEST_SUITE.md) — how to run benchmarks and parity tests
- [`wasm_renderer/ARTIFACTS.md`](./wasm_renderer/ARTIFACTS.md) — build artifacts
- GitHub: #799 (init handshake), #845–#849 (integration / CI / testing)

## Native desktop (out of scope for Tier B)

A future Vulkan/Metal app via Dawn would likely **fork** `wasm_renderer/` into a separate repo. The browser WASM module is not the desktop delivery vehicle.
