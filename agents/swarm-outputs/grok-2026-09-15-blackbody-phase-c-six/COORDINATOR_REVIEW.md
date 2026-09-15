# Coordinator review — blackbody Phase-C leftover six (2026-09-15)

Contract: `docs/SHADER_UPGRADE_BATCH.md`. Cards in BRIEFS.md written before WGSL.

Planck + the shared circular ember loop is the floor look, not the upgrade. No file received a new glow ring, extraBuffer spring, or IQ palette.

| ID | Card | Ideas pointable | KEEP VERBATIM | Overlay? | A packing | Params | Naga |
|---|---|---|---|---|---|---|---|
| thermal-vision-blackbody | yes | NUC bars + C.a lag | yes | no | raw thermal + T | exact | pass |
| chroma-kinetic-blackbody | yes | λ split + luma-delta | yes | no | display RGBA | exact | pass |
| energy-shield-blackbody | yes | cell strikes + edge current | yes | no | raw trail A.r | exact | pass |
| stellar-plasma-blackbody | yes | ∇f filaments + warp C | yes | no | raw thermal + T | exact | pass |
| sim-heat-haze-blackbody | yes | Schlieren + plume shear | yes | no | raw T in A.r | exact | pass |
| encaustic-wax-blackbody | yes | cooling skin + iron ridges | yes | no | display RGBA | exact | pass |

No new extraBuffer springs. Stellar audio lie (`u.config.yzw`) replaced with `plasmaBuffer[0].xyz`. Energy-shield C is exact load. Encaustic depth is scene depth.

Skipped: already-carded blackbody siblings; later four radial/BH (`warp-drive`, `hyper-space-jump`, `gamma-ray-burst`, `gen-singularity-forge`); `crt-clear-zone`; liquid-small; tropism mycelium; physarum agents.

**Pass 6/6.** Real-GPU visual QA remains external (no WebGPU adapter in this VM).
