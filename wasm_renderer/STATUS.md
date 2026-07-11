# C++ WASM Renderer — Current Status

**Last updated:** July 2026

---

## Support tier: **B — Experimental (opt-in)**

**Production default:** TypeScript WebGPU renderer.

The C++ WASM path is available via `?renderer=wasm` or the Controls renderer switcher.
It is labeled **Experimental** in the UI and is **not** held to the same SLA as the TS backend.

| Doc | Purpose |
|-----|---------|
| [`WASM_BACKEND_POLICY.md`](../WASM_BACKEND_POLICY.md) | Tier B policy, promotion/demotion rules |
| [`WASM_PROMOTION_TRACKING.md`](../WASM_PROMOTION_TRACKING.md) | Tier B → A checklist + evidence log ([#890](https://github.com/ford442/image_video_effects/issues/890)) |
| [`WASM_RENDERER_GAP_ANALYSIS.md`](../WASM_RENDERER_GAP_ANALYSIS.md) | Technical gaps + July 2026 status |

---

## Pipeline status: compute + present implemented (not production-ready)

The C++ WASM renderer runs the full compute pipeline and blits to the canvas via
`PresentToSurface()`. Init/format/limits handshake was hardened in #817–#822.

> **Do not read "pipeline implemented" as "production ready."** WASM remains Tier B
> until all promotion gates in [`WASM_PROMOTION_TRACKING.md`](../WASM_PROMOTION_TRACKING.md) pass.

Older analysis files (`ARCHITECTURE_ANALYSIS.md`, `COMPLETENESS_ANALYSIS.md`,
`PERFORMANCE_ANALYSIS.md`, `STABILITY_ANALYSIS.md`, `RENDERER_PLAN.md`) are
**March–May 2026 snapshots** — see their disclaimers; use this file + GAP analysis instead.

### What is implemented

| Feature | Status |
|---------|--------|
| WebGPU device + queue initialisation | ✅ |
| Universal bind group layout (700+ shaders) | ✅ |
| Ping-pong texture pipeline | ✅ |
| Multi-slot shader pipeline (slots 0–2) | ✅ |
| Slot execution modes (`chained` / `parallel`) | ✅ |
| Shader loading & pipeline caching | ✅ |
| Uniform buffer (time, mouse, ripples, params) | ✅ |
| Audio reactivity + FFT bins (`updateAudioData`, `SetAudioFrequencyBins`) | ✅ (#888) |
| Depth map support (`updateDepthMap`) | ✅ |
| Image / video upload from JS | ✅ |
| Canvas resize + resource recreation | ✅ |
| Frame capture / screenshot (`captureFrame`) | ✅ |
| Video recording (GPU readback → offscreen `captureStream`) | ✅ (#886) |
| Mouse position / ripple input | ✅ |
| Presentation (`PresentToSurface`) | ✅ |
| RAII + structured init diagnostics (#822) | ✅ |
| TypeScript wrapper (`WASMRenderer.ts`) | ✅ |
| `wasm_bridge.js` canonical sync (#821) | ✅ |
| RendererManager duck-typed forwarding (#887) | ✅ |
| `setInputSource` app wiring (#887) | ✅ |
| Playwright smoke + parity + bench (#889) | ✅ |

### Known limitations (Tier B)

| Limitation | Notes |
|------------|-------|
| Not production default | TS WebGPU is Tier A |
| GPU timings on WASM | Wall-clock only (`getGPUTimings().available === false`) |
| Promotion gates open | See [`WASM_PROMOTION_TRACKING.md`](../WASM_PROMOTION_TRACKING.md) |
| Edge GPU coverage | Informal — run manual smoke on target hardware |
| Visual pixel-diff | Not automated (statistical luminance parity only) |
| Per-slot `QueueSubmit` | May affect perf — benchmark gate tracks |

---

## Closed tracking (historical)

### C++ solidification (#817–#823) — ✅ closed

| Issue | Description |
|-------|-------------|
| [#821](https://github.com/ford442/image_video_effects/issues/821) | Bridge sync |
| [#818](https://github.com/ford442/image_video_effects/issues/818) | Format negotiation |
| [#820](https://github.com/ford442/image_video_effects/issues/820) | Fatal surface creation |
| [#817](https://github.com/ford442/image_video_effects/issues/817) | Adapter query/log |
| [#819](https://github.com/ford442/image_video_effects/issues/819) | `requiredLimits` validation |
| [#822](https://github.com/ford442/image_video_effects/issues/822) | Init hardening + diagnostics |
| [#823](https://github.com/ford442/image_video_effects/issues/823) | Docs refresh (June 2026) |

Full table: [`WASM_RENDERER_GAP_ANALYSIS.md` § C++ Solidification](../WASM_RENDERER_GAP_ANALYSIS.md#c-solidification-tracking-2026-06)

### Integration / CI / tests (#845–#849, #886–#889) — ✅ closed in tree

| Issue | Topic |
|-------|-------|
| #845–#849 | Manager forwarding, input sources, CI, tests (June 2026) |
| [#886](https://github.com/ford442/image_video_effects/issues/886) | Recording readback |
| [#887](https://github.com/ford442/image_video_effects/issues/887) | Forwarding audit |
| [#888](https://github.com/ford442/image_video_effects/issues/888) | Feature parity (FFT, timings) |
| [#889](https://github.com/ford442/image_video_effects/issues/889) | Playwright + benchmarks |

Umbrella: [#885](https://github.com/ford442/image_video_effects/issues/885)

### Open: promotion + docs (#890)

- [`WASM_PROMOTION_TRACKING.md`](../WASM_PROMOTION_TRACKING.md) — evidence checklist
- [#890](https://github.com/ford442/image_video_effects/issues/890) — docs refresh (this pass)

---

## Architecture summary

```
Browser (TypeScript)
  └─ RendererManager.ts        — selects WebGPU / WASM / Canvas2D
       └─ WASMRenderer.ts      — TypeScript wrapper
            └─ wasm_bridge.js  — JS glue (canonical: wasm_renderer/wasm_bridge.js)
                 └─ pixelocity_wasm.{js,wasm}  — Emscripten output
                      └─ renderer.cpp / main.cpp  — C++ WebGPU via Dawn/emdawnwebgpu
```

## Selecting the WASM renderer

```
http://localhost:3000/?renderer=wasm
```

Or Controls → Renderer switcher (shows **Experimental** badge).

Full testing guide: [`WASM_TESTING.md`](../WASM_TESTING.md) · [`WASM_TEST_SUITE.md`](../WASM_TEST_SUITE.md)

Runtime switch:

```js
window.__rendererManager?.switchRenderer('wasm');
```

## Build

```bash
cd wasm_renderer && ./build.sh   # requires emsdk
# or from repo root:
npm run wasm:build
```

Outputs: `public/wasm/pixelocity_wasm.{js,wasm}` + synced `wasm_bridge.js` in `public/wasm/` and `src/wasm/`.

See [`ARTIFACTS.md`](./ARTIFACTS.md) for CI artifact strategy.

## Historical scripts

One-off maintenance scripts live in [`archive/`](./archive/) (not used by build).
