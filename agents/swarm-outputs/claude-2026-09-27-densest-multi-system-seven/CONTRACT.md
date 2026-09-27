# Densest Multi-System Seven — batch contract (2026-09-27)

Live law: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §7, §9). Bindings: `agents/WGSL_BUILTINS_GENERATIVE.md`.

## Claimed IDs (one agent each — never touch another agent's file)
gen-resonant-quantum-obsidian-scarab-engine, gen-resonant-quantum-plasma-dragon-eye, gen-sentient-ferro-silicate-swarm,
gen-sonoluminescent-chrono-geode-matrix, gen-spectral-ferrofluid, gen-superfluid-quantum-foam,
gen-symbiotic-bismuth-crystal-dragon-core.

Already shipped with `Ideas:` and NOT in scope (in the request list but done 09-13/09-15):
gen-sentient-quantum-chrono-leviathan-moth, gen-symbiotic-chrono-mycelium-engine, gen-stellar-acoustic-resonance-manifold.

"Densest multi-system": these files already stack several systems (raymarch + KIFS + plasma + feedback + particles).
The upgrade is to make the systems *couple* or to add one missing layer of structure — not to pile on an eighth system.
Prefer ideas that fuse two existing subsystems of THIS file over bolting on a new one.

Sibling-overlap rules inside this batch:
- gen-sentient-ferro-silicate-swarm and gen-spectral-ferrofluid are both ferrofluid-flavoured. spectral-ferrofluid owns
  magnetic-fluid surface ideas (spike lattice, field lines, dipoles); ferro-silicate-swarm owns swarm/particle/silicate
  ideas. Also avoid the already-shipped gen-quantum-entangled-ferrofluid-engine's ideas (grep its `Ideas:` line).
- gen-resonant-quantum-plasma-dragon-eye and gen-symbiotic-bismuth-crystal-dragon-core are both "dragon": the eye owns
  iris/pupil/cornea ideas; the core owns bismuth hopper/oxide/crystal ideas. Avoid shipped bismuth siblings' ideas
  (grep `Ideas:` in public/shaders/*bismuth*.wgsl).
- Catalog saturation (checked): shipped bismuth files already use hopper terraces, oxide thin-film, twin-boundary seams,
  terrace-lip glints, flux lines. bismuth-dragon-core must NOT repeat those as its ideas — find what is native to the
  dragon/core/symbiosis part of THIS file. Shipped entangled-ferrofluid already owns "Rosensweig spike lattice" and
  |psi|^2 filaments/contours — spectral-ferrofluid must pick different ferro ideas.
- gen-superfluid-quantum-foam: avoid gen-quantum-foam-alpha's ideas (upgraded today; grep its `Ideas:` line).

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
