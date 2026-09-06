# grok.md — Grok AI Assistant Guide for image_video_effects

> Read this first. Then `AGENTS.md`. For **upgrading existing shaders**, read [`docs/SHADER_UPGRADE_BATCH.md`](docs/SHADER_UPGRADE_BATCH.md) before touching WGSL.

## Project Overview
**Pixelocity / image_video_effects** is a React + WebGPU catalog of real-time compute shader effects (fluids, generative, glitch, post, interactive). Catalog ~1,350+ effects.

- **Live Demo**: https://go.1ink.us/pixelocity/index.html
- **Focus**: Distinct per-effect identities, mouse/audio reactivity, hot-swap WGSL + JSON.

## Technology Stack
- TypeScript + **Create React App / CRACO** (not Vite — Vite is a deferred spike)
- WebGPU compute shaders (WGSL), optional C++/WASM renderer (`?renderer=wasm`)
- Image / video / webcam input; AI depth is lazy

## Grok Guidelines
- **Compute Shader First**: Catalog effects are WGSL compute, 13 bindings, `@workgroup_size(16, 16, 1)`.
- **Upgrades add ideas**: 2–4 native visual additions to the existing effect. Not a rewrite. Not ACES/bindings-only. See `docs/SHADER_UPGRADE_BATCH.md`.
- **Interactivity**: Mouse, time, audio, depth — **when they belong on that effect**. Do not stamp springs + ripples on every file.
- **Hot-swap sacred**: Drop `.wgsl` + JSON. Do not edit `Renderer.ts` / bind groups in a shader batch.
- **Performance**: 60fps on mid-range. This Cloud VM has **no GPU** — structural gates only.

## Common Tasks
- Upgrade a claimed 6–10 shader batch (Idea Cards first)
- Add a new effect only when asked (scaffold: `python3 scripts/new_shader.py`)
- Foundation / WASM work is a separate track — do not mix it into a shader batch

Bindings: `agents/WGSL_BUILTINS_GENERATIVE.md`. Floor snippets: `agents/CLOUD_UPGRADE.md`.