# Batch 47 briefs — 2026-08-13 (tracker #407–414) — FAST MOTION CONTINUATION

Batch 47 takes the next smallest clean all-category cohort and adds distinct
continuous fast-motion structures, held-pointer response, and capped click
fronts while preserving each shader's saved-control and feedback contracts.

| # | Shader | Lines | Upgrade focus |
|---|--------|-------|---------------|
| 407 | `motion-heatmap` | 124→153 | Advected thermal state, heat runners, click fronts |
| 408 | `cross-conv-mouse-bilateral` | 125→141 | Bilateral sheen packet and smoothing fronts |
| 409 | `cyber-focus` | 125→149 | Stable block motion, held aperture, scanner packet, clarity rings |
| 410 | `data-moshing-diffusion` | 125→146 | Advected offset state and displacement streams |
| 411 | `engraving-stipple` | 125→140 | Traveling hatching, line runners, engraved rings |
| 412 | `interactive-kuwahara` | 125→142 | Live hardness, held wet runners, click clarity |
| 413 | `molten-glass` | 125→147 | Rising thermal state, heat packets, safe refraction |
| 414 | `neon-pulse-dissolve` | 125→153 | Smooth luminous noise, scan runner, correct audio |

## Shared contract

- Canonical bindings, 16x16x1 workgroups, invocation guards, and real audio.
- Every saved source `params` entry is preserved exactly and mirrored by an indexed `updatedParams` entry; Cross Convolution intentionally remains a three-control shader.
- Mouse position/down, capped click history, and each available audio band are used without persistent `extraBuffer` writes.
- A remains packed state for Motion Heatmap, Data Moshing Diffusion, and Molten Glass; the other five keep their established display role. B remains unused except for Neon Pulse Dissolve's existing diagnostic packing.
- State/history reads are exact and bounded where required; fast motion is continuous rather than frame-hash strobing.
- Scientific language remains descriptive: Molten Glass is a stylized visual, not a physical simulation.
- Cloud-VM proof is structural; visual and performance acceptance require a discrete GPU.
