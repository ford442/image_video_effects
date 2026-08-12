# Batch 44 briefs — 2026-08-10 (tracker #381–388) — FAST MOTION ENCORE

This all-category cohort is the eight smallest pre-gated, unclaimed,
single-pass shaders after excluding `rainbow-vector-field`, whose metadata and
source identify it as Pass 1 of a multipass pair. Every source `params` array
is an immutable saved-preset contract; indexed `updatedParams` mirror it.

| # | Shader | Category | Baseline lines | Focus |
|---|--------|----------|----------------|-------|
| 381 | `lenia` | artistic | 110 | State conveyor, growth packets, inoculation fronts |
| 382 | `reaction-diffusion` | artistic | 114 | Chemical advection, feed packets, seed fronts |
| 383 | `video-echo-chamber` | image | 124 | Orbit echoes, chromatic streaks, click echoes |
| 384 | `ion-stream` | artistic | 124 | Helical packets, magnetic wakes, ion fronts |
| 385 | `chroma-depth-tunnel` | interactive-mouse | 124 | Axial flight, spectral runners, shock rings |
| 386 | `mercury-temporal-mirror` | image | 124 | Liquid shear, capillary packets, impact fronts |
| 387 | `viscous-drag` | liquid-effects | 124 | Advected jets, vortex packets, pressure fronts |
| 388 | `rain-lens-wipe` | interactive-mouse | 125 | Falling drops, water streaks, wipe fronts |

## Batch contract

- At least two shader-specific closed-form or history-advected fast-motion techniques per shader; no frame-hash strobing.
- Canonical 13 bindings, invocation bounds guards, and `@workgroup_size(16, 16, 1)`.
- `config=[time,rippleCount,resW,resH]`, `zoom_config=[time,mouseX,mouseY,mouseDown]`, and ripple loops capped at 50.
- Real `plasmaBuffer[0].xyz` audio and live indexed controls 0–3.
- Exact clamped `textureLoad` for rgba32float history; no `extraBuffer` writes.
- Preserve A packing, leave B unused, and keep depth passthrough unless the baseline generates depth.
- Preserve source `params` byte-for-byte; add only indexed `updatedParams` and truthful metadata.
- Cloud-VM proof is structural. Visual and performance acceptance require verified discrete-GPU hardware.
