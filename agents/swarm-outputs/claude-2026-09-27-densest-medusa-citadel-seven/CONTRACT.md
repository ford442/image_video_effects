# Densest Medusa→Citadel Seven — batch contract (2026-09-27)

Live law: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §7, §9). Bindings: `agents/WGSL_BUILTINS_GENERATIVE.md`.

## Claimed IDs (one agent each — never touch another agent's file)
gen-abyssal-plasma-void-medusa, gen-astral-silk-chrono-weaver-arachnid, gen-astro-kinetic-chrono-orrery,
gen-bioluminescent-chrono-plasma-astro-owl, gen-bioluminescent-cyber-aether-void-seahorse,
gen-bioluminescent-neural-lattice-weaver, gen-bismuth-crystal-citadel.

Already shipped with `Ideas:` 2026-09-15 and NOT in scope (in the request list; ideas verified in body):
gen-celestial-clockwork-plasma-loom, gen-celestial-yggdrasil-matrix, gen-chronomorphic-glass-tesseract.

"Densest multi-system": fuse two existing subsystems of THIS file rather than bolting on a new system.
Most of these files are BROKEN AT HEAD (see each card's FIX list). Fixes are the floor, not ideas — but they come first,
because an idea on a blank frame is invisible.

Your draft Idea Card is already in `card-<id>.md` in this dir (written by the coordinator from a full read of HEAD).
Refine it (you may swap an idea if infeasible — say why), then implement. Do not drop listed fixes without explaining why.
Line numbers in cards are HEAD line numbers — re-read the file yourself; the audit may be wrong in details.

Catalog saturation (grep `^//  Ideas:` in public/shaders yourself before finalising) — FORBIDDEN idea names:
  * jellyfish: jet-propulsion contraction wave, radial/ring canals, gonads, lappets, marine snow, nematocyst pulse beads /
    stinger dots, Stokes-shift afterglow, bell contraction wave, crenulated oral disc.
  * web/silk: plucked-thread standing waves, dew beads, silk afterglow via C history, agate banding, thread thin-film,
    thread-tension sheen, over-under interlacing.
  * orrery/black hole: Keplerian rete/astrolabe gearing, Doppler/relativistic beaming crescent, photon ring/subrings,
    Keplerian shear streaks, dust-lane absorption, gravitational redshift, lensed far-side halo.
  * owl/feather: barbule thin-film, ocellus eye-spots, primary-feather slots, beak shear glint, flap ghost, auroral
    feather-current lanes, cyber-iris aperture, tapetum eyeshine, corneal Purkinje catchlight, dilator stroma.
  * seahorse/fin: tail-fin Karman wake; trap-coloured silhouette halo (exists — seahorse may FIX its false halo claim but
    it is not an idea).
  * neural: action-potential runners, saltatory/Ranvier, synapse flash at nodes, integrate-and-fire, refractory afterglow,
    axon runner fronts, dendrite web, vesicle release, aequorin/GFP; lattice: Bragg colour, line-defect waveguides,
    dual-lattice vertex glow, triple-junction glow; staggered domino row delay; photoelastic stress fringes.
  * bismuth: hopper terraces (any form), oxide thin-film/tarnish/zoning, twin seams, terrace-lip glints/emissive,
    riser rainbow film, containment flux lines, escapement flash, photon-ring oil sheen, self-assembling sectors,
    gravitational time dilation, singularity shadow.
  * generic: thin-film anything, spring cursor, IQ-palette stamp, screen-space ripple rings as an "idea".

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
