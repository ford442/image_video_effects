# Batch 39 briefs — 2026-08-06 (tracker #348–355) — FAST MOTION ENCORE

Eight smallest clean, unclaimed, single-pass generative shaders selected after
excluding multipass and `nextShader` ownership. All eight entered the batch with
four indexed `updatedParams`; those arrays are the saved-preset contract and
must remain exact.

| # | Shader | Baseline lines | Focus |
|---|--------|----------------|-------|
| 348 | `gen-chrono-voronoi-mycelium` | 216 | Advected growth fronts and traveling spores |
| 349 | `gen-singularity-forge` | 216 | Relativistic disk shear and ballistic jet knots |
| 350 | `gen-obsidian-echo-chamber` | 217 | Warp corridor and racing reflection echoes |
| 351 | `gen-prismatic-aether-loom` | 217 | Warp-flight braids and spectral speed threads |
| 352 | `gen-rainbow-firefly-dance` | 218 | Velocity-stretched swarm and comet tails |
| 353 | `gen-cybernetic-liquid-chrome-engine` | 221 | Conveyor camera and piston surge waves |
| 354 | `gen-magnetic-field-lines` | 220 | Analytic charged-particle advection |
| 355 | `gen-bifurcation-diagram` | 221 | Chaos scanner and derivative-aligned trails |

## Batch contract

- At least two shader-specific fast-motion techniques per effect.
- Closed-form or otherwise frame-rate-independent motion; no per-frame fixed-step speed.
- Canonical 13 bindings, exact Uniforms layout, `@workgroup_size(16, 16, 1)`, and bounds guards.
- Every frame writes `writeTexture`, `writeDepthTexture`, and `dataTextureA`.
- `config=[time,rippleCount,resW,resH]`; `zoom_config=[time,mouseX,mouseY,mouseDown]`.
- Audio comes from `plasmaBuffer[0].xyz`; ripple loops cap at 50.
- No persistent `extraBuffer` writes in this batch.
- `dataTextureA/C` is bounded display history, `dataTextureB` remains unused.
- Existing `updatedParams` arrays remain exact; metadata changes are additive and truthful.
- VM proof is structural; visual QA requires verified discrete-GPU hardware.
