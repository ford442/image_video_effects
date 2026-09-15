# Coordinator review — radial / BH blackbody leftover four (2026-09-15)

Contract: `docs/SHADER_UPGRADE_BATCH.md`. Cards in BRIEFS.md written before WGSL.

Planck + the shared circular ember / mouse-heat loop is the floor look, not
the upgrade. No file received a new glow ring, extraBuffer spring, or IQ
palette.

| ID | Card | Ideas pointable | KEEP VERBATIM | Overlay? | A packing | Params | Naga |
|---|---|---|---|---|---|---|---|
| warp-drive-blackbody | yes | bubble wall + bow/wake Doppler | yes (dual-use .z/.w) | no | raw HDR + T | exact | pass |
| hyper-space-jump-blackbody | yes | Lorentz stretch + beaming | yes | no | pre-ACES + vignette α | exact | pass |
| gamma-ray-burst-blackbody | yes | bipolar lobes + C afterglow | yes (dual-use .x/.y) | no | raw RGB + energy | exact | pass |
| gen-singularity-forge-blackbody | yes | Keplerian Doppler + photon ring | yes (config.y kept) | no | ACES display RGBA | exact | pass |

No new extraBuffer springs. Singularity audio lie (`u.config.y`) replaced with
`plasmaBuffer[0].xyz`. Hyper-space depth is scene depth. Gamma C is exact load.
Gamma alpha is semantic.

Skipped: already-carded blackbody siblings; idea-rich warp/BH parents
(`warp_drive`, `hyper-space-jump`, `gamma-ray-burst`, `black-hole`,
`gravity-well`, `gen-stardust-nebula`); `crt-clear-zone`; liquid-small;
tropism mycelium; physarum agents.

**Pass 4/4.** Real-GPU visual QA remains external (no WebGPU adapter in this VM).
