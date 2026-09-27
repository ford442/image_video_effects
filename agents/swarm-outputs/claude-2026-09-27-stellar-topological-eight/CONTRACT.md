# Stellar / Topological Eight — batch contract (2026-09-27)

Live law: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §7, §9). Bindings: `agents/WGSL_BUILTINS_GENERATIVE.md`.

## Claimed IDs (one agent each — never touch another agent's file)
gen-singularity-forge, gen-stellar-plasma-ouroboros, gen-stellar-web-loom, gen-symbiotic-plasma-reef-matrix,
gen-tectonic-plasma-crucible, gen-topological-phase-weave, gen-vortex-cathedral, gen-wasm-hls-physarum-swarm (RESCUE + upgrade).

Already shipped with `Ideas:` and NOT in scope (in the request list, done 09-15): gen-topological-acoustic-knots,
gen-void-harmonic-cymatic-resonator.
Off-limits ideas (sibling motifs): lensed sky / photon ring (gen-quantum-singularity-forge, done today), pair annihilation +
Schlieren-from-|∇θ| (acoustic-knots), data packets / beads running along cylinders (fungal reactor).

## Per-request floor
Full 13-binding header (0..12, binding 13 only if the file already has it), @workgroup_size(16,16,1), bounds guard;
ACES on display RGB; semantic alpha (not hardcoded 1.0); `dataTextureA` is the only feedback write; exact
`textureLoad(dataTextureC, coord, 0)` (never a sampler on C); audio from `plasmaBuffer[0].xyz`; preserve existing
mouse / held / click-ripple behaviour (do NOT add ripples or springs); naga-clean; exactly 4 named params in the JSON (`updatedParams`).

## Verified runtime facts (checked 2026-09-27 — trust these over the request text and older docs)
- `extraBuffer` is 256 floats re-uploaded WHOLE every frame (`src/renderer/webgpu/audioDepth.ts`): `[0]`=bass, `[1]`=mid, `[2]`=treble,
  `[4]`=historyHead, `[5..132]`=FFT bins, `[133..255]`=ZERO every frame. So "bounded extraBuffer[133..138]" state NEVER persists.
  Do not store state there or build an idea on it. NEVER write `[0..132]` (it clobbers audio and races with other threads).
  Use stateless formulas, or A/C texture history. If HEAD already writes `[133..138]`, replace it with a stateless equivalent and say so.
- `plasmaBuffer[0].xyz` IS uploaded (`frame.ts:171`). Use it for audio. Never `config.y` / `zoom_config.x` as audio.
- `u.ripples[i].w` is always 0. Ripple age is `time - ripple.z`.
- `dataTextureC` is read-only (`texture_2d<f32>`). `textureStore(dataTextureC, …)` is illegal.
- WGSL `pow(x, n)` with x<0 is NaN: clamp bases. `normalize(vec2(0))` is undefined: guard.
- A feedback shader that early-returns when C≈0 never starts (textures are zero-init): needs a seed path.
- `fract(uv.x * resolution.x)` is always 0.5 at texel centres — dead masks.
- When A switches HDR→ACES display, trails fed back from C must decode consistently (acesInverse or store raw).
- The JSON has only `updatedParams` (no `params`), so the dead-slider audit may scan 0 defs: grep `zoom_params` reads by hand.
- Screen-top is uv.y = 0 in these shaders' ray setups (pictures are y-flipped vs 3D up); mouse is already consistent with that. Do not "fix" mouse Y.

## Creative rules
1. FIRST write `card-<id>.md` in this dir (Idea Card per §2 of the live doc: SHADER, IDENTITY, KEEP VERBATIM,
   ADD 2–4 native ideas with why, FORBID, A PACKING). Only then edit WGSL. Start from the proposed card in the plan
   (`/root/.claude/plans/another-set-of-shaders-enumerated-bee.md`) — sharpen it, but stay native to the file.
2. Add 2–4 named visual ideas native to THIS effect; deepen the existing motif. No reimagining, no generic overlay
   (no spring+ripple+IQ palette stamp), no idea borrowed from a sibling in this batch or the off-limits list.
3. Ideas must be visible with audio = 0. Audio may ride along but is not an idea.
4. Saved `updatedParams` (names, defaults, min, max, step, order) stay byte-exact. Four sliders live and each does something distinct.
   If a slider is currently dead, wire it — but at its saved default it must reproduce the old look (check numerically).
5. Header: add `//  Ideas: …` and `//  A packing: …` lines (copy shape from public/shaders/analog-film-degrade.wgsl),
   set/append `Upgraded: 2026-09-27`. JSON: only add feature tags that are true (`upgraded-rgba`, `audio-reactive`, `mouse-driven`); no others.
6. Diff must not be ≥70% header/ACES/boilerplate; tag each numbered idea in a WGSL comment (`// IDEA 1: …`) so a reviewer can find it.
7. Fix any silent bug you find on the read path and say so in the card/report. Bugs already known for your file are listed in your task prompt.
8. Keep per-pixel cost reasonable (raymarchers: do not raise step counts; LIC/god-ray loops ≤ ~2x current cost).

## Gates (run per file, from repo root)
`~/.cargo/bin/naga public/shaders/<id>.wgsl`
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl`
Do NOT run generate_shader_lists / build / Jest / git / audit scripts that rewrite `reports/` — the coordinator does that once at the end.
(The precommit gate may touch `reports/wgsl_precommit_report.json`; that is expected and handled by the coordinator. Never `git checkout` anything.)
No GPU exists here: do not claim the look is verified. Numpy-port a rule if you need to sanity-check dynamics.

## Report back (≤200 words)
Idea Card summary, what was KEPT verbatim, A packing, where each idea lives (line ranges), silent bugs fixed,
gate results, anything you refused to do and why.
