# Split-Gen Eight — batch contract (2026-09-28)

Live law: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §7, §9). Bindings: `agents/WGSL_BUILTINS_GENERATIVE.md`, `docs/BINDING_CONTRACT.md`.

## Claimed IDs (one agent each — never touch another agent's file)
Generative: morphogenic-resonance, aurora-borealis-loom, volumetric-cloud-nebula, gen-image-pyro
Non-generative: film-gate-weave (retro-glitch), scanline-drift (retro-glitch), glass-brick-distortion (distortion),
paper-cutout (interactive-mouse)

Selection: no `^//  Ideas:` line, no other upgrade marker in the header (Batch 5x/6x, Visualist, Algorithmist, vN,
`A.`/`B.` blocks), no claim in any 2026-09-2x batch. Every candidate was read in full; julia-warp, circular-pixelate,
stipple-engraving, holographic_interference, plasma-jet-stream, sand-dunes were rejected (already idea-bearing).

Ideas were checked against all 654 catalog `Ideas:` lines. Rejected as saturated before writing cards: over-under
interlacing / shuttle (3 loom files), auroral ray striations / altitude emission / curtain folds / lower border
(4 aurora files), dust lanes / reddening / ionizing star / globules / ionization fronts (gen_kimi_nebula), mitosis
(3 files), burst-lit smoke (gen-fireworks-smoke-bloom), head-switch skew (vhs-tracking), paper fibre (3 files).

## Per-file floor (hygiene, not the upgrade)
Canonical 13 bindings, @workgroup_size(16,16,1), bounds guard; ACES on display RGB; semantic alpha; dataTextureA is the
only feedback write (keep HEAD's documented packing); exact `textureLoad(dataTextureC, coord, 0)`; audio only from
`plasmaBuffer[0].xyz`; saved `params` byte-exact; naga-clean.

## Verified runtime facts (trust over older docs)
- `plasmaBuffer[0].xyz` = bass/mid/treble is uploaded. `plasmaBuffer[1..]` reads ZERO — any per-bin/per-layer read is dead.
- `extraBuffer[133..255]` is zeroed every frame: springs there never persist. HEAD springs in files 5–8 are harmless
  no-ops — leave them, add none, never build an idea on extraBuffer state.
- `u.ripples[i].w` is always 0. Ripple age = `time - ripple.z`.
- `zoom_config.yz` = mouse in canvas UV 0..1, y=0 TOP. `zoom_config.w` > 0.5 = held.
- Screen y=0 is the top. "Up" in a y-up scene means flipping pixel y.
- `pow(x,n)` with x<0 is NaN. WGSL float `%` keeps sign.
- `fract(uv.x*res.x)` at texel centres is constant 0.5 — dead mask; use integer coords.
- Real-GPU visual QA is external; the Cloud VM has no WebGPU. Do not claim looks.
