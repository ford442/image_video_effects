# Batch 43 briefs — 2026-08-10 (tracker #373–380) — FAST MOTION ENCORE

The first post-queue-closeout all-category cohort uses the pre-gated eight
smallest clean, unclaimed, single-pass shaders. Every source `params` array is
an immutable saved-preset contract; indexed `updatedParams` entries mirror it.

| # | Shader | Category | Baseline lines | Focus |
|---|--------|----------|----------------|-------|
| 373 | `neon-quantum-lattice` | geometric | 122 | Phason conveyance, vertex runners, dephasing fronts |
| 374 | `neon-strings` | interactive-mouse | 122 | Pluck packets, harmonic streaks, click impulses |
| 375 | `kimi_chromatic_warp` | interactive-mouse | 123 | Prismatic conveyor, radial runners, shock rings |
| 376 | `sine-wave` | distortion | 123 | Fast packets, crest streaks, click wave fronts |
| 377 | `slime-mold-on-video` | simulation | 123 | Velocity advection, chemotactic packets, food fronts |
| 378 | `thermal-touch-blackbody` | advanced-hybrid | 123 | Buoyant heat streaks, click fronts, safe palette |
| 379 | `vhs-jog` | interactive-mouse | 123 | Head-switch rolls, tape streaks, tape-slip events |
| 380 | `alpha-luminance-history` | visual-effects | 124 | Directional advection, diffusion, traveling light rings |

## Batch contract

- At least two shader-specific closed-form or history-advected fast-motion techniques per shader; no time-hash strobing.
- Canonical 13 bindings, bounds guards, and `@workgroup_size(16, 16, 1)`.
- `config=[time,rippleCount,resW,resH]`; every ripple loop caps at 50.
- Real `plasmaBuffer[0].xyz` audio; normalized mouse coordinates remain in engine space.
- Exact clamped `textureLoad` for rgba32float history, bounded trail energy, and no `extraBuffer` access.
- Preserve A packing, leave B unused, and keep depth passthrough where the source does not generate depth.
- Preserve source `params` exactly; add only indexed `updatedParams` and truthful metadata.
- Cloud-VM proof is structural. Visual and performance acceptance require verified discrete-GPU hardware.
