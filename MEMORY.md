# MEMORY.md - Long-Term Curated Memory (Spark Engine)

**Last updated:** 2026-06-11 (this session: C++ WASM renderer audit)

## Core Identity & Vibe (from SOUL + IDENTITY)
- Spark Engine / Cheerleader: bright, protective, kinetic, loud-hearted. "We are NOT done here!" Fast, punchy, energetic. Use "we/let's", 🔥⚡💥🫡, short lines, "one thing first", "messy start? fine", "this is NOT the final boss".
- Never fake slogans. Protect morale + motion. Turn "impossible" into sequence. Remember comeback history.

## User (from USER.md + consolidation + this work)
- Developer (ford442) on github.com/ford442/image_video_effects (WebGPU shader effects app, "Pixelocity").
- Iterative builder, focused sessions on shaders (generative, upgrades, swarm agents using WGSL_BUILTINS etc).
- Values: ship-ready, self-evident systems, canonical refs, clean output over "mostly works". Uses AI as peer ("you do X, I'll do Y").
- Recent focus (from 2026-06): shader swarms, generative, image suggestions, and now hardening the C++ WASM renderer path (long investment, currently not loading reliably).
- Communication: enthusiastic shorthand + technical, approval like "pure gold" when matches.

## Project Context - WASM Renderer (C++)
**Investment:** Multi-phase (2026-03 to now). Advanced compute: multi-slot (chained/parallel), ping-pong, depth, 3-band audio (extra+plasma), RAII WGPUHandle, async capture/readback, workgroup parse, device-lost/uncaptured callbacks, universal 13-bind layout matching all WGSL shaders.
- main.cpp: EM_KEEPALIVE exports, thin bridge to g_renderer.
- renderer.cpp/h: full WebGPURenderer (Initialize/CreateDevice with 4-attempt powerPref ladder + WaitAny+ASYNCIFY for emdawn, CreateResources for 2048² rgba32f + r32 depth + data A/B/C + buffers, bind layout, render pipeline for present blit, LoadShader+parse wg size, Render multi-submit per slot + feedback, PresentToSurface with acquire+BeginRenderPass+draw+present, Recreate on resize, BeginFrameCapture mapAsync etc).
- Has presentation now (Render calls PresentToSurface at 1725).
- JS side: wasm_bridge (newer in wasm_renderer/, stale copy in src/wasm/), WASMRenderer.ts wrapper, RendererManager forwards (now has WASM branches).

**Current Reality (2026-06-11 audit):**
- **Does NOT load reliably** (user + open #799 "harden WebGPU canvas context initialization").
  - Root causes in C++:
    - Format hardcode: JS_EM uses getPreferredCanvasFormat() + configure, but C++ forces BGRA8Unorm for surfaceFormat_, render colorTarget, ConfigureSurface (lines ~430,728,907). Mismatch = silent bad present or validation fail.
    - No limits check: deviceDesc.requiredLimits=nullptr (342). Blind create of large rgba32f textures/binds. No post-adapter wgpuAdapterGetLimits + validate vs workload.
    - Surface non-fatal: JS_Create returns 0 but CreateDevice true; init "ok" but no output.
    - compatibleSurface=nullptr always; surface created after device via importJsSurface.
    - Double-config (EM_JS ctx.configure + C++ wgpuSurfaceConfigure).
    - Bridge skew: src/wasm/wasm_bridge.js (TS import source) outdated vs wasm_renderer/ (Jun 8 artifacts use new). Dev load uses wrong logic/diagnostics/async handling.
  - Other: switch contention (no clean unconfigure), emdawn Win/Chrome fragility (known crbug, ladder helps but not enough), partial inits.
- **What works when it loads:** compute pipeline, multi-slot, audio/depth/image/video upload, capture, resize, shader load+wg parse.
- **Docs drift:** STATUS.md claims "Phase 3 complete" (surface even checked in old README), but GAP (May) was pessimistic (pre-present); now present exists but init is the blocker.
- **Build:** artifacts committed (public/build/wasm), build.sh warns+exit0 no emcc, src/wasm vs renderer skew.

**User directive this session:** Solidify/complete the *C++ code*. Specifically call out that "we can check if we've chosen good webgpu settings for the context via c++" → move adapter/device/surface/limits/format decisions + validation into C++ side, expose/report.

## Decisions / Lessons (write down or they vanish)
- Always keep single source of truth for bridge wrappers; copy step in build for both glue + wrapper.
- For WASM + Dawn + browser WebGPU: context ownership, format negotiation, compatibleSurface, and explicit limits are first-class reliability concerns, not afterthoughts.
- "Works in C++ compute" != "loads and presents reliably cross browser/GPU". The last mile is the surface + init handshake.
- Update GAP/STATUS aggressively when code evolves (present path landed after May doc).
- Use GH issues + Copilot for the C++ work (user has swarm/agent patterns elsewhere).

## TODOs / Open Threads (from this + recent memory)
- [x] Created GH issues 817-823 (2026-06-11) for C++ solidification. All C++-centric, reference #799 (open context init epic) + specific source lines. Includes the explicit "check good webgpu settings via c++" as #817. See daily 2026-06-11 for full list + urls.
- [ ] After issues: can implement (e.g. add query in CreateDevice after adapter, choose/validate format, set limits, make surface fail fatal, etc).
- Ongoing: shader work, but this session was WASM C++ focus per query.
- Memory maintenance: review recent daily (06-07 had swarm, git sync); distill only high-signal (C++ reliability is now key infra bet).

## Quick Refs (for continuity)
- Key files: wasm_renderer/{renderer.cpp:242 CreateDevice, 430 hardcode, 902 Configure, 1595 Render, 1725 PresentToSurface, EM_JS~45}, wasm_renderer/wasm_bridge.js (canonical), src/wasm/wasm_bridge.js (stale, fix), src/renderer/{WASMRenderer.ts,RendererManager.ts}, WASM_RENDERER_GAP_ANALYSIS.md, wasm_renderer/STATUS.md
- GH: #799 (open, context init), #771 (closed windows), #736 (closed testing).
- Build: `cd wasm_renderer && ./build.sh` (needs emsdk); `npm run wasm:build`
- Test: `?renderer=wasm`, `window.__rendererManager?.getDiagnostics()`, switchRenderer in console.
- Soul line: "i am here to help you get back in the fight!" — for the C++ path, we're turning the loading screen into a win.

**Capture principle:** All this written down immediately. Future sessions read this + today's daily before touching WASM C++.

(If consolidating older: 06-07 swarm details in its daily; only kept the "C++ WASM now the reliability focus" signal here.)
