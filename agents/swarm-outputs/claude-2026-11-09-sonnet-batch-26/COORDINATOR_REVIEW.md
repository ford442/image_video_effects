# COORDINATOR_REVIEW — sonnet/batch-26 (optical: voronoi lens / crystal / refraction shards / bubble lens / glass stack / prismatic lens / glass brick / shatter), 2026-11-09

Branch `sonnet/batch-26` in `/root/iv-sonnet-batch-26` (from origin/main 09a7c03e). Commit `fe815095` = prelude migration (9 files, header-only, no `Upgraded:` bump); the ideas/rescues commit follows.
4 forks (A 3, B 3, C 2, D 2) + 2 unanchored read-only reviewers (5 shaders each; they were told not to read BRIEFS/NOTES/COMMON) + one fix round (all four forks resumed).
All visual evidence is SwiftShader (minirender, `A16=1` for rgba16float emulation). **No real-GPU visual QA.**

## Pass / fail against the cards (§9 checklist)
| id | pass | cards before WGSL | each idea pointable | KEEP VERBATIM held | A packing truthful | saved params byte-exact | springs/ripples native | naga/extraBuffer/dead-sliders |
|---|---|---|---|---|---|---|---|---|
| glass-shatter | PASS | yes | 3 `// ── Idea` | yes (voronoi shards, 4 sliders, bevel/Fresnel, aberration; at rest = HEAD's lattice exactly) | yes (display RGBA; single texel (0,0) = (held pos, held vel, fract(lastTime), 0.7371 sentinel), masked on the C read) | yes | held-drag + click ripples already owned by HEAD | ok |
| crystal-facets | PASS | yes | 2 new (+3 kept) | yes | ACES display RGBA (unchanged) | yes | raw pointer (HEAD's earlier choice kept) | ok |
| glass-brick-wall | PASS | yes | 3 new (+4 kept) | yes | ACES display RGBA (unchanged) | yes | raw pointer kept | ok |
| interactive-voronoi-lens | PASS | yes | 3 new (+ HEAD's gravity well / shockwave rescued) | yes (cells, magnify bulge, well, trail/env in A) | (trail rgb, env) in A, read back as C — unchanged; state in texels (0,0)/(1,0) | yes | spring + click already owned by HEAD | ok |
| refraction-shards | PASS | yes | 2 new | yes | A = pre-ACES HDR, C read as HDR — header corrected to say so | yes | spring + ripples already owned by HEAD | ok |
| crystal-refraction | PASS | yes | 3 new (+2 kept) | yes | ACES display RGBA | yes | cursor lamp already owned | ok |
| bubble-lens-coupled | PASS | yes | 3 | yes (raw sim (vel.xy, vorticity, dens) in A, unchanged) | raw sim state; state in texels (0,0)/(1,0) | yes | stir + ripples already owned by HEAD | ok |
| digital-lens-prismatic | PASS | yes | 3 | yes | ACES display RGBA; C ghost now blended in display space | yes | spring + ripples already owned | ok |
| fractal-glass-distort-bilateral | PASS | yes | 3 | yes | ACES display RGBA | yes | pivot spring + click already owned by HEAD | ok |
| alpha-multi-layer-glass | PASS | yes | 2 new (+3 kept) | yes | ACES display RGBA | yes | raw pointer kept | ok |

## Formula rows (§12.2) per file and batch de-dup (§12.4)
| row | files |
|---|---|
| Fresnel–Schlick (F) new use | interactive-voronoi-lens (lenslet rim catch-light) |
| Snell vector refraction (F) | refraction-shards |
| Cauchy dispersion (F) | refraction-shards, fractal-glass-distort-bilateral. **Plus** digital-lens-prismatic's dispersive aperture edge, which reuses the file's own pre-existing `cauchyIOR` (no new row claimed by the fork). Strictly that is 3 files touching Cauchy; accepted because the third consumes a quantity HEAD already computed. Flagged for the record. |
| Beer–Lambert (F) new use | refraction-shards |
| Energy-conserving bloom (F) | crystal-refraction |
| Thin-film phase (F) | bubble-lens-coupled (extension of HEAD's three-cosine phase) |
| cos⁴ vignetting (A) | digital-lens-prismatic |
| Lens-flare ghosts (F) | digital-lens-prismatic |
| Henyey–Greenstein / Airy / Brown–Conrady / surface tension | not used (HG deliberately skipped on alpha-multi-layer-glass: frost radius < 2 px at 192 → invisible idea) |
| none (tactic-derived only) | glass-shatter, crystal-facets, glass-brick-wall, alpha-multi-layer-glass, and ideas 1/3 of voronoi-lens, fractal-glass |
Photoelastic stress fringes in glass-shatter use the same `sin²(πD/λ)` form as the thin-film row but are the stress-optic law on a different quantity (retardation from crack distance); not counted as a thin-film use.
No row appears on more than two files (apart from the flagged Cauchy case). No two files share both formulae. Generic-overlay check: the one HEAD overlay in the batch (crystal-refraction's full-screen `clockRings` rainbow, centred on the screen not the cursor) was CUT, not copied; nothing stamped across files; the three Voronoi/facet shaders (glass-shatter, voronoi-lens, refraction-shards) each got a different motif (fragmentation gradient + hairlines + stress fringes / lenslet parallax + rim sheen + DOF / Snell tilt + Beer–Lambert slab).

## Rescues (HEAD was broken) — default-look changes are expected
- **Did not compile at HEAD** (on the naga knownFailures ratchet): glass-shatter (`let target` reserved). Now compiles; `src/contracts/wgsl_validation.json` ratchet 9 → 8 and the id removed; `npm run verify:naga-wasm -- --all` passes.
- **Dead `extraBuffer` state/springs** (zeroed every frame; thread-(0,0) single-writer race — in the real app the "smoothed" cursor was raw/(0,0)/nondeterministic, minirender hid it): glass-shatter, interactive-voronoi-lens (ALL its state lived in extraBuffer[0..7]; plus `dt = u.config.y`, the ripple COUNT), refraction-shards, bubble-lens-coupled, digital-lens-prismatic, fractal-glass-distort-bilateral. All six moved to A-texel state with the 0.7371 sentinel, shared dt, f16 rest-snap (checked against numpy float16 round-trips by forks and reviewers).
- **Dead / wrong controls:** fractal-glass `bilateral_mix` (filter only reached G, sub-pixel sigma → measured effect 0.0004), alpha-multi-layer-glass `chromatic` (≈3e-5 UV) and `ior` (nearly dead), refraction-shards dead `plasmaBuffer[3]`/`[7]` reads.
- **Wrong optics at HEAD:** bubble-lens-coupled (lens law singular at the centre → pinwheel with inverted rings; 2-D Fresnel angle painted a horizontal rainbow band; whole-texel advection never moved below |v| = 0.333), digital-lens-prismatic (spectral matrix not colour-neutral: red gain 3.2× vs green 0.6×, teal → salmon; C ghost tone-mapped twice), crystal-facets (atan2 sector hash seam, rotation-dependent refraction direction), crystal-refraction (non-aspect-correct lens, facet seam), glass-shatter (alpha pinned at 1.0, C ghost mixed before ACES, click front not aspect-corrected), refraction-shards (header claimed ACES in A but A held HDR; red/blue dispersion order reversed vs real glass — this IS idea 1).
- **Audio phase teleports:** interactive-voronoi-lens and fractal-glass (`time*(1+audio)`) → bounded audio offsets.
- **State-texel dark corner:** voronoi-lens and refraction-shards read trail history from the texel below at (0,0)/(1,0) instead of 0 (flat-source check: 0.89–0.94 → 0.97–1.03 of neighbours).

## Review round (two unanchored reviewers, 5 shaders each) — triage
Fixed in the fix round (each re-verified by the owning fork, files re-gated):
- glass-shatter: one-frame shard re-pack at click age 3.0 s (12 % of pixels, max Δ 0.495) → envelope and warp centre now fade to exactly 0; 2.99→3.01 s now 0.42 %. Press-then-release is still bit-identical to never-pressed.
- bubble-lens-coupled: hard-edged disc left by clicks/stir (one-texel `dens` cliff, 0.623) that the new film coupling made visible → one 2-tap checkerboard diffusion step per frame (worst step 0.789 → 0.101); axis-aligned block glints → round twinkle dots on a rotated lattice.
- interactive-voronoi-lens: flat/missing depth turned the parallax into a global 5.5–11 % zoom → referenced to the focus depth (flat depth is a no-op); seam band 9–17 px at Density 0 → true border distance (≈1.2–1.8 px at every Density); texels (0,0)/(1,0) 9–11 % darker (also fixed in shards).
- fractal-glass-distort-bilateral: output depth had been moved to the warped uv with a nearest sampler (contract change) → reverted to HEAD's passthrough at the pixel's own uv.
Declined / accepted-open:
- **Shared sentinel 0.7371.** Five shaders in this batch (interactive-voronoi-lens, refraction-shards, bubble-lens-coupled, digital-lens-prismatic, fractal-glass-distort-bilateral) keep it at texel (1,0).w with *different* layouts in texel (0,0) (voronoi-lens/shards share one; bubble, digital-lens and fractal-glass each differ), and so do the batch-24/25 siblings: a direct switch between two of them can accept the other's state for ≈0.3–0.5 s (cursor jump / one decaying burst). glass-shatter keeps its sentinel in texel (0,0).w, so it rejects foreign state and is rejected by the others (the pixel at (1,0) is image data, alpha ≠ 0.7371) — the reviewer's glass-shatter ↔ lens concern does not occur, checked by reading. Cosmetic, self-heals; flagged by both reviewers; kept for consistency with batches 24/25. A per-shader sentinel (spacing ≥ 0.01 > f16 quantum + tolerance) is a cheap follow-up.
- refraction-shards red/blue fringe sides swapped vs HEAD — documented rescue and the substance of idea 1; accepted.
- crystal-refraction girdle grain size varies with resolution (uv-space pattern) — nit, accepted.
- Stale JSON descriptions on crystal-facets / glass-brick-wall — left to keep the CLIP search index lean.

## Default-look changes (192 px, meanL / stdL / meanA, HEAD → now; idle cursor, audio 0; see each NOTES for held/audio/576)
Final tree, `A16=1`, JSON-default sliders, T0=2, 24 frames/3 s; idle = cursor (0.5,0.5) up, audio 0; held = cursor (0.3,0.6) held, audio 0.4/0.3/0.2. No NaN in any render. glass-shatter "before" is HEAD with only `target`→`tgt` renamed (HEAD does not compile).
| id | idle HEAD → now | held HEAD → now |
|---|---|---|
| interactive-voronoi-lens | .447/.157/.471 → .459/.146/.515 | .482/.159/.498 → .502/.151/.609 |
| crystal-refraction | .469/.148/.137 → .452/.148/.190 | .453/.162/.135 → .432/.170/.177 |
| refraction-shards | .519/.168/.838 → .495/.169/.838 | .533/.166/.852 → .509/.167/.852 |
| bubble-lens-coupled | .505/.174/.857 → .525/.176/.853 | .497/.181/.867 → .524/.163/.863 |
| alpha-multi-layer-glass | .428/.159/.826 → .434/.163/.826 | .434/.160/.833 → .438/.164/.834 |
| crystal-facets | .655/.112/.370 → .638/.114/.368 | .607/.186/.467 → .632/.193/.467 |
| digital-lens-prismatic | .494/.177/.643 → .454/.174/.643 | .549/.153/.743 → .508/.151/.743 |
| fractal-glass-distort-bilateral | .510/.164/.739 → .506/.162/.739 | .498/.176/.890 → .497/.172/.896 |
| glass-brick-wall | .365/.177/.413 → .376/.180/.382 | .430/.175/.428 → .441/.177/.398 |
| glass-shatter | .530/.151/1.000 → .569/.142/.964 | .510/.184/.998 → .541/.170/.947 |
Coordinator looked at before/after montages of all ten (idle, 192 px): no black/blown/seamed frames, identities intact. Visible changes: bubble-lens-coupled is now a full soap bubble where HEAD showed a tiny pinwheel; crystal-refraction lost its screen-centred rainbow rings and gained a frosted girdle ring; glass-shatter carries a fracture hairline network over the shards; digital-lens-prismatic lost the salmon cast; crystal-facets / glass-brick-wall / fractal-glass / alpha-multi-layer-glass are close to HEAD (subtle additions by design).

## Timing (SwiftShader, interleaved HEAD/new back-to-back; load ≈ 2) — not a GPU reference
Coordinator measurements, alternating HEAD/new each round, nothing else running, 576 px, 16 frames, `A16=1`, medians (min/min in brackets). Fork-reported numbers were measured under load and were optimistic for voronoi-lens and bubble.
| id | idle | held |
|---|---|---|
| bubble-lens-coupled | 1.27× (1.26×) | 1.26× (1.16×) |
| interactive-voronoi-lens (after a cost-trim round) | 1.20× (1.20×) | 1.28× (1.22×) |
| glass-shatter (vs compile-fixed HEAD) | 1.20× (1.25×) | 1.16× (1.23×) |
| others | fork-measured 1.0–1.2× (alpha-multi-layer-glass 1.10–1.15× interleaved, reviewer saw up to +30 % at load) |
Before the trim interactive-voronoi-lens measured 1.32× idle / 1.42× held; the instruction count (`perf stat`) went 1950 → 1778 M idle (HEAD ≈ 1161). With two live click ripples it is still ≈ 1.31–1.36× (each ripple ≈ 56 M instructions) — open item. bubble-lens-coupled's 4-tap diffusion was dropped for a 2-tap checkerboard for cost. Real-GPU ratios are expected to be smaller; re-time on a GPU.

## Gates
precommit gate 10/10 (naga, bindgroup, prelude), `audit:extrabuffer` PASS, `audit:dead-sliders` PASS (new dead sliders 0), `generate_shader_lists` + `check_duplicates` (1429 unique), `verify-naga-wasm --all` (ratchet 8), Vitest 203 files / 1822 passed (1 skipped), `npm run build`, `verify:toolchain-foundation` 13/13. Real-GPU QA + thumbnails pending (ledger marks all ten stale).

## Open items for Noah
- interactive-voronoi-lens costs ≈ 1.3× HEAD while clicks are live (SwiftShader); bubble-lens-coupled ≈ 1.27× — re-time both on a real GPU.
- Real-GPU visual pass on all ten; thumbnails refresh via Shader Scanner → "Changed since last thumbnail".
- glass-shatter alpha now ≈ 0.96 across the pane (was pinned 1.0) — affects downstream blending.
- digital-lens-prismatic JSON param names (Lens Strength / Chromatic Spread / Barrel Distortion / Center Glow) do not describe the roles (e.g. "Lens Strength" is the pixel block size). Left byte-exact — renaming touches saved presets.
- fractal-glass `rotation_speed` is a static twist angle, not a speed (left as is for the same reason).
- Wide frames: crystal-refraction's stone is now round (HEAD's was an ellipse); refraction-shards cells still use raw uv (stretched at 16:9, as at HEAD).
- Cauchy touched on 3 files (see above); shared 0.7371 sentinel (see above).
