# NOTES — organic-optical-ten (2026-09-27)

Consolidated from NOTES-A.md (leviathan-scales, pulsar, jellyfish-swarm, bioreactor-bloom),
NOTES-B.md (celestial-weave, chromatic-metamorphosis, plasma-loom), NOTES-C.md
(reaction-diffusion, dragonfly, oracle-jelly). Full detail lives in those three files.

## Track A — first pass

| Shader | Kept verbatim | A packing | Ideas landed | Floor fixes | naga |
|---|---|---|---|---|---|
| gen-abyssal-leviathan-scales | hex-grid map(), conveyor timing, scalePalette(), spring cursor, breach loop, camera fly-through, params | display RGBA, unchanged | chromatic dispersion split; molt scar via exact C read; held keel micro-ridging | none needed | PASS |
| gen-bioluminescent-aether-pulsar | core/disk SDF, spring camera orbit, click shockwave, cosine palette, exact C feedback, params | display RGBA, unchanged | spin-locked twin jets; Keplerian shear striping; shockwave-triggered core flare | header rewrite (was missing `Ideas:`) | PASS |
| gen-bioluminescent-aether-jellyfish-swarm | mapJellyfish smin chain, domain repetition, raw mouse repulsion, aequorin glow, params | display RGBA (fixed: exact textureLoad, was filtering) | bell-contraction propulsion; stinger-tip glow; startle flash | real depth (was hardcoded 0); exact C load | PASS |
| gen-bioreactor-bloom | fbm grid/cell hashing, nucleus/membrane/pulse, tendril/bloom functions, poisonCloud, params | display RGBA (fixed: was raw fields, packing lie) | mitosis split event; toxicity necrosis creep; reactivity-scaled bloom pulse | real alpha; real depth; exact C load; simplified non-bug "regex auditor" comment | PASS |
| gen-celestial-weave | fbm lattice, weft/warp fields, star grid/twinkle, constellation lines, palette(), params | display RGBA (fixed: was raw fields, packing lie) | shimmer thread glint; void-depth star parallax; constellation pulse-travel | real alpha; real depth; exact C load; no "mouse-driven" tag added | PASS |
| gen-chromatic-metamorphosis | 4-shape smin weight chain, HSV color field, GGX/Fresnel/AO/grain stack, mouse catalyst, params | display RGBA (new — A was never written) | catalyst stutter-hold; temporal afterimage via now-real C read; per-phase seasonal color lean | added missing dataTextureA write; added missing ACES tonemap; fixed depth trailing 1.0→0.0; full header rewrite | PASS |

## Track B — second pass (existing ideas preserved, new ideas appended)

| Shader | Existing ideas preserved | New ideas appended | Bug/floor fix | naga |
|---|---|---|---|---|
| gen-aetherial-plasma-loom | alternating heddle lanes; plasma shuttle necking | warp thread-memory ghosting (genuine exact C read); weft-catch spark | fixed dead `dataTextureC` binding (was declared, never read — packing lie vs JSON claim); de-duplicated 5 repeated top-level JSON keys | PASS |
| gen-bioluminescent-reaction-diffusion | luciferin quench; excitation flash on B fronts | pointer-wake luciferin-age reset; quorum-sensing ignition flash | none — floor already correct | PASS |
| gen-celestial-quantum-glass-dragonfly | thin-film wing iridescence; quantum glass caustic core; acoustic wing-tip vortex trails | velocity-banked flight roll; vortex-synced wingtip flutter | added missing `Upgraded:` header line; added missing `upgraded-rgba` JSON tag | PASS |
| gen-chromatic-oracle-jelly | pulse-swim contraction/coast; pupil pointer-tracking with blink | tentacle-anchored luminous wake; click-triggered startle contraction; (optional) audio pupil dilation | none — floor already correct | PASS |

## Noted deviations from the literal card wording (all judged in-spirit, not overlay violations)

- **jellyfish-swarm**: `mapJellyfish`/`mapScene` return types widened (f32→vec2, vec2→vec4) to carry tip-proximity and repulsion-magnitude signals without a second geometry pass. Callers only ever consumed `.x`/`.y`, so this is additive, not a rewrite.
- **chromatic-metamorphosis**: pre-ACES clamp ceiling widened 1.25→4.0 so the newly-added ACES tonemap has real HDR headroom to roll off, rather than being applied to an already-clamped-flat signal.
- **dragonfly**: the vortex-synced wingtip flutter re-derives the fog loop's `vortexWave` functional form locally inside `mapWings` (different coordinate scope) rather than reading the fog loop's variable directly — same identity, still native to the wing SDF.
- **oracle-jelly**: the pre-existing click-ripple loop was relocated earlier in `main()` (not duplicated) so the new `startleKick` and the existing `clickOracle` glow share one pass instead of adding a second 50-iteration ripple loop.

## Batch-wide verification (run after all 10 files landed)

- `naga` on all 10: 10/10 PASS.
- `python3 scripts/wgsl_precommit_gate.py --files <10 paths>`: 10/10 PASS, 0 extraBuffer violations.
- `npm run audit:dead-sliders -- --files <10 ids>`: 0 new dead sliders.
- `python3 scripts/audit_extrabuffer.py`: 0 violations among the 10 batch files.
- `node scripts/generate_shader_lists.js` + `node scripts/check_duplicates.js`: clean, 1386 unique definitions, no duplicates.
- `npx react-scripts test --watchAll=false --ci`: 741/748 tests pass; the 6 failing suites are the pre-existing `bridge/*.js` import failures documented in [[project-jest-js-import-failures]] (confirmed unrelated to this batch — same failures exist on clean main).
- `SKIP_WASM_BUILD=1 npm run build`: compiled successfully.
- Real-GPU visual QA: not possible in this Cloud VM (no WebGPU adapter) — not claimed.

## JSON diff scope confirmed

All 10 JSON diffs are limited to: `features[]` (additive only), one `description` line update (plasma-loom, to reflect the now-true afterglow claim), and — for plasma-loom only — removal of 5 duplicated top-level keys that were silently shadowing themselves. No `params` or `updatedParams` arrays were renamed, reordered, or re-defaulted on any of the 10 shaders.
