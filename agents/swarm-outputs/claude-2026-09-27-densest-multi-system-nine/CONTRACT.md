# Densest Multi-System Nine — batch contract (2026-09-27)

Live law: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §7, §9). Bindings: `agents/WGSL_BUILTINS_GENERATIVE.md`.

## Claimed IDs (one agent each — never touch another agent's file)
gen-abyssal-quantum-leviathan-skeleton, gen-astral-plasma-accretion-forge, gen-astro-mechanical-quantum-furnace-engine,
gen-audiovisual-mandelbulb-raymarcher, gen-auroral-ferrofluid-monolith, gen-bismuth-singularity-loom-engine,
gen-chromodynamic-plasma-collider, gen-cosmic-clockwork-dyson-sphere, gen-4d-projection-dream-weavers.

Already shipped with `Ideas:` and NOT in scope (in the request list but done 2026-09-15, both ideas verified in body):
gen-chronos-biomechanical-void-leviathan.

"Densest multi-system": these files already stack several systems (raymarch + KIFS + plasma + feedback + particles).
The upgrade is to make the systems *couple* or to add one missing layer of structure — not to pile on a new system.
Prefer ideas that fuse two existing subsystems of THIS file over bolting on a new one.

Your draft Idea Card is already in `card-<id>.md` in this dir (written by the coordinator from a full read of HEAD).
Refine it (you may swap an idea if it is infeasible — say why), then implement. Do not drop the listed bug fixes
without explaining why.

Sibling-overlap rules inside this batch:
- furnace-engine and dyson-sphere are both brass-gear + plasma-core. furnace OWNS gear motion (meshing counter-rotation)
  and refraction through the core. dyson OWNS Voronoi plasma conduits, Beer-Lambert transmittance, core-as-light-source.
  Neither may take the other's ideas.
- accretion-forge and plasma-collider and bismuth-loom all have plasma/gravity. accretion owns dust absorption, Keplerian
  shear, gravitational redshift of temperature. bismuth-loom owns time dilation of its twist/palette and singularity shadow.
  collider owns beam/bunch/ring ideas and dispersion.
- abyssal-leviathan must avoid chronos-leviathan's "vertebral phase-lag undulation; auroral vortex wake" and
  leviathan-moth's "peristaltic armor segments; frozen-time wing lamellae".
- Catalog saturation (checked — also grep `^//  Ideas:` in siblings yourself):
  * bismuth: hopper terraces, oxide thin-film/zoning, twin seams, terrace-lip glints, containment flux lines, escapement
    flash, riser film, spring-eased singularity lens, photon-ring oil sheen (ferro-singularity).
  * ferro: Rosensweig lattice, Taylor cones, dipole chains, labyrinth fingering, Earnshaw wobble, chrome reflects core beam,
    Archimedean flux spirals, Cotton-Mouton, meniscus mounds.
  * aurora: curtain folds, green-line shimmer, 557.7/630/427.8 nm bands, Birkeland tubes, substorm flashes.
  * accretion/black hole: relativistic beaming crescent, phononic spiral waves, photon-sphere subrings, click lensing.
  * clockwork: Keplerian astrolabe gearing, over-under shuttle, gear-tooth sparks, inter-gear mesh line, dead-beat
    escapement, ruby jewel bearings.
  * 4D: W-slice ghost frame, W-cell hive lattice, face-crossing caustics, temporal birefringence, cell-face corridor glow.
  * rain matrix: streak-history zoom blur.

## Per-request floor
Full 13-binding header (0..12, binding 13 only if the file already has it), @workgroup_size(16,16,1), bounds guard;
ACES on display RGB; semantic alpha (not hardcoded 1.0); dataTextureA is the only feedback write; exact
`textureLoad(dataTextureC, coord, 0)`; audio from `plasmaBuffer[0].xyz`; preserve existing mouse / held / click-ripple;
naga-clean; exactly 4 named params in the JSON.

## Verified runtime facts (checked 2026-09-27 — trust these over older docs)
- `plasmaBuffer[0].xyz` IS now uploaded (`src/renderer/webgpu/frame.ts:171`). Use it for audio. Never `config.y` /
  `zoom_config.x` as audio.
- `extraBuffer[133..255]` is **zeroed every frame** (`writeExtraBuffer` uploads the whole 256-float scratch). So
  "bounded extraBuffer[133..138]" state NEVER persists. Do not store state there and do not build an idea on it.
  Use stateless formulas, or A/C texture history. If HEAD already writes [133..138], leave it and note it; never [0..132].
- `u.ripples[i].w` is always 0 (engine padding). Ripple age is `time - ripple.z`; strength must not scale by `.w`.
- `dataTextureC` is read-only (`texture_2d<f32>`). `textureStore(dataTextureC, …)` is illegal.
- WGSL `pow(x, n)` with x<0 is NaN: clamp bases with `max(…, 0.0)`.
- A feedback shader that early-returns when C≈0 never starts (textures are zero-init): needs a seed path.
- `fract(uv.x * resolution.x)` is always 0.5 at texel centres — dead masks. Use `fract(f32(coord.x)/N)`.
- When A switches HDR→ACES display, trails fed back from C must decode consistently (acesInverse or store raw).
  Several files in THIS batch store ACES colour in A and then re-blend C as HDR and ACES it again (double tone-map): fix it.
- Depth convention: near = 1.0, miss/far = 0.0 (write real hit depth, not passthrough or a constant).

## Creative rules
1. FIRST write `card-<id>.md` in this dir (Idea Card per §2 of the live doc: SHADER, IDENTITY, KEEP VERBATIM,
   ADD 2–4 native ideas with why, FORBID, A PACKING). Only then edit WGSL.
2. Add 2–4 named visual ideas native to THIS effect; deepen the existing motif. No reimagining, no generic overlay
   (no spring+ripple+IQ palette stamp), no idea borrowed from a sibling file in this batch (or the already-shipped siblings above).
3. Ideas must be visible with audio = 0. Audio may ride along but is not an idea.
4. Saved `params` (ids, names, defaults, min/max/step, mapping) stay byte-exact. Align `updatedParams` additively only.
   Four sliders live and each does something *distinct*. If a slider is currently dead, wire it — but at its saved
   default it must reproduce the old look (check numerically).
5. Header: add `//  Ideas: …` and `//  A packing: …` lines (copy shape from public/shaders/analog-film-degrade.wgsl),
   set `Upgraded: 2026-09-27`. Only add JSON features tags (`upgraded-rgba`, `audio-reactive`, `mouse-driven`) that are true.
6. Diff must not be ≥70% header/ACES/boilerplate; each numbered idea must be findable in the WGSL (tag it in a comment).
7. Fix any silent bug you find on the read path (pow NaN, zero-C, ripple.w, dead mask) and say so in the card/notes.

## Gates (run per file, from repo root)
`~/.cargo/bin/naga public/shaders/<id>.wgsl`
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`
`python3 scripts/audit_dead_sliders.py` (check "scanned N" > 0; else grep zoom_params reads by hand)
Do NOT run generate_shader_lists / build / Jest / git — the coordinator does that once at the end.
No GPU exists here: do not claim the look is verified. Numpy-port a rule if you need to sanity-check dynamics.

## Report back (≤200 words)
Idea Card summary, what was KEPT verbatim, A packing, where each idea lives (line ranges), silent bugs fixed,
gate results, anything you refused to do and why.
