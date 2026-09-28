# Split-Gen Eight II — batch contract (2026-09-28)

Live law: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §7, §9). Bindings: `agents/WGSL_BUILTINS_GENERATIVE.md`, `docs/BINDING_CONTRACT.md`.

## Claimed IDs (one agent each — never touch another agent's file)
Generative: gen-cybernetic-plasma-orchid-nexus, gen-hyperdimensional-plasma-loom, gen-cybernetic-aether-moth-chrysalis,
gen-neon-plasma-chrono-bloom
Non-generative: crt-tv (retro-glitch), silk-flow-advection (image), anamorphic-caustic-flare (visual-effects),
gemstone-fractures (distortion)

Selection: no `^//  Ideas:` line, no upgrade marker in the header, not named in any 2026-09-2x batch. Every candidate was
read in full. Rejected after reading: gen-kinetic-bioluminescent-obsidian-coral-reactor (non-canonical 880 B Uniforms
struct vs 848 B host buffer — rescue, not upgrade), log-polar-droste (JSON runs the -remap/-grade multipass pair; the
named file is dead), nebula-gyroid (no gyroid in the code — rewrite), light-leaks (code is a halftone ink effect — rewrite).

Previous batch (split-gen-eight) is uncommitted in the same tree: do not touch its 8 shaders/JSONs.

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
