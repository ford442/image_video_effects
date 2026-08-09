# Batch 40 briefs — 2026-08-09 (tracker #356–363) — FAST MOTION ENCORE

Eight smallest clean, unclaimed, single-pass generative shaders selected after
deferring the parser-invalid `gen-ethereal-quantum-holographic-fractal-coral`.
Every target entered the batch with four saved controls; its existing `params`
and `updatedParams` entries are immutable preset contracts.

| # | Shader | Baseline lines | Focus |
|---|--------|----------------|-------|
| 356 | `gen-gravitational-ferrofluid-singularity-engine` | 211 | Rotating magnetic domains, spike fronts, droplets and horizon trails |
| 357 | `gen-abyssal-leviathan-scales` | 216 | Conveyor scales, racing fissures and breach wakes |
| 358 | `gen-abyssal-silicate-geode-weaver` | 221 | Cavity warp-flight, gyroid runners and shard waves |
| 359 | `gen-neuro-kinetic-liquid-gold-lotus` | 221 | Direct controls, petal torque and blossom shocks |
| 360 | `gen-4d-projection-dream-weavers` | 222 | Hyperslice transport and lattice afterimages |
| 361 | `gen-prismatic-fractal-dunes` | 224 | Dune conveyance, sand streaks and ballistic geysers |
| 362 | `gen-sentient-liquid-neon-fractal-heart` | 225 | Artery pulses, contraction shocks and plasma trails |
| 363 | `gen-micro-cosmos` | 231 | Helical currents, organism wakes and microbe blooms |

## Batch contract

- At least two closed-form or history-advected fast-motion techniques per shader.
- Canonical 13 bindings, exact `Uniforms` layout, bounds guards, and `@workgroup_size(16, 16, 1)`.
- `config=[time,rippleCount,resW,resH]`; ripple loops cap with `min(u32(u.config.y), 50u)`.
- Audio reads `plasmaBuffer[0].xyz`; normalized mouse UV is neither divided by resolution nor vertically mirrored.
- Presentation, bounded A history, and generated near-is-one depth are written every frame; B remains unused.
- No persistent `extraBuffer` writes and no additional raymarch pass.
- Existing `params` and `updatedParams` entries stay exact; metadata is additive and truthful.
- VM validation is structural. Live animation and performance acceptance requires a verified discrete GPU.
