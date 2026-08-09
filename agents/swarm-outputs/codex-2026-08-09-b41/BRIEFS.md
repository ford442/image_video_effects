# Batch 41 briefs — 2026-08-09 (tracker #364–371) — FAST MOTION ENCORE

Eight smallest clean, unclaimed, single-pass generative shaders selected after
deferring parser-invalid `gen-ethereal-quantum-holographic-fractal-coral`.
Every target entered the batch with four saved controls; `params` and
`updatedParams` are immutable preset contracts.

| # | Shader | Baseline lines | Agent | Focus |
|---|--------|----------------|-------|-------|
| 364 | `morphogenic-resonance` | 232 | Algorithmist | Morph conveyor, resonance runners, edge streaks |
| 365 | `gen-fireworks-chrysanthemum` | 234 | Algorithmist | Ballistic petals, radial speed lines, bass bursts |
| 366 | `volumetric-cloud-nebula` | 234 | Visualist | Warp-flight camera, cloud streaks, ion flashes |
| 367 | `gen-quantum-neural-lace` | 236 | Interactivist | Fiber pulse packets, lattice wave advection |
| 368 | `aurora-borealis-loom` | 237 | Visualist | Curtain conveyance, ion drift streaks |
| 369 | `gen-fireworks-willow-cascade` | 238 | Interactivist | Gravity droop trails, wind-advected embers |
| 370 | `gen-hyperbolic-crystal-symbiosis` | 239 | Optimizer | Racing growth fronts, tile runners |
| 371 | `gen-fireworks-wind-ripple` | 240 | Optimizer | Wind conveyors, ripple shocks, comet tails |

## Batch contract

- At least two closed-form or history-advected fast-motion techniques per shader.
- Canonical 13 bindings, exact `Uniforms` layout, bounds guards, `@workgroup_size(16, 16, 1)`.
- `config=[time,rippleCount,resW,resH]`; ripple loops cap with `min(u32(u.config.y), 50u)`.
- Audio reads `plasmaBuffer[0].xyz`; normalized mouse UV is neither divided by resolution nor vertically mirrored.
- Presentation, bounded A history, and generated near-is-one depth every frame; B remains unused.
- No persistent `extraBuffer` writes and no additional raymarch pass.
- Existing `params` and `updatedParams` entries stay exact; metadata is additive and truthful.
- VM validation is structural. Live animation acceptance requires verified discrete-GPU hardware.

## Pre-scan repair flags

| Shader | Repairs |
|--------|---------|
| `morphogenic-resonance` | Aspect mouse; textureLoad HDR trails |
| `gen-fireworks-chrysanthemum` | Normalized mouseUV; remove B writes; real depth |
| `volumetric-cloud-nebula` | Add A/depth/audio; warp-flight; trails |
| `gen-quantum-neural-lace` | Add A/depth/audio; uniform comment truth |
| `aurora-borealis-loom` | Faster curtain conveyor; ion streaks |
| `gen-fireworks-willow-cascade` | Normalized mouseUV; remove B; real depth |
| `gen-hyperbolic-crystal-symbiosis` | Add A store; growth depth; boundary A write |
| `gen-fireworks-wind-ripple` | Normalized mouseUV; remove B; real depth |
