# COORDINATOR REVIEW — sonnet/batch-38 (liquid / fractal / galaxy / aurora / kaleido / neon ten)

Reviewed against `BRIEFS.md` (cards written before any WGSL), `NOTES-fork{A..E}.md`, and the diffs. Everything here is **structural + SwiftShader evidence. No real-GPU visual QA has been done**, and none is claimed.

## Result at a glance

| Shader | Pass | Ideas landed (card → file) | Deviation from card | Idle re-time ×HEAD (256 px) |
|---|---|---|---|---|
| kimi-liquid-glass | pass, with a note | Cauchy dispersion; signed-focus caustic | Idea 4 is **ripple-local only** (0 % at idle / held / audio; 1.3 % @192, 5.4 % @576 with fresh ripples). Fringe ≈1.5× HEAD, not ±30 % (`DISP_K` 130 restores HEAD) | 1.17 |
| kaleido-scope | pass | mirror loss per bounce; tumbling object cell; seam rescue | none; default ≈5–10 % darker | 1.15 |
| radiating-haze | pass, **weak** | source-hue halo gather; outward-advected persistence; ring-frequency rescue | Ideas are ≈0.6 % of frame each (8 % of the pointer disc); all changes 3.3–4.0 %. Trail weight 0.3 → 0.4 | 1.15 |
| gen-abyssal-geode-matrix | pass | orbit-trap veins; Beer–Lambert; step-count AO + 4 rescues | **Rescue 5 added** (gravity well anchored at z = 0, left behind by the camera after ~10 s) — touches `map()`'s well block the card said to keep | 1.21 idle / **1.31 audio** |
| gen-flame-fractal-attractor | pass, **default look changes** | log-density + vibrancy; blackbody cooling | Card premise was wrong: HEAD is white from frame 1 (99.1 % px ≥ 0.98). Idea 4 extended with ember persistence (tint-only was 0.00 % visible) | 0.98 |
| reaction-diffusion | pass, **partial** | photo-driven kill map; autocatalytic front glow; 2 rescues | Card Idea 1 (9-point Laplacian) **replaced**: ≤ 1.1 % of pixels. HEAD chemistry was dead (U floor) | 1.01 |
| gen-audio-reactive-spiral-galaxy | pass | differential rotation; density-wave colour sequence + 2 rescues | none | 1.05 / 1.06 audio |
| liquid-oil | pass | angle-dependent thin-film; gravity drainage; pow rescue | numpy stability run at k = 0.45, shipped k = 0.15 checked on SwiftShader only | 1.06 |
| gen-audio-reactive-aurora-ribbons | pass | asymmetric profile; altitude emission colour; fold limb-brightening | none | 1.03 / 1.07 audio |
| neon-edge-glow | pass | ring-gather spill glow; positive-column striations; pow rescue | gather cut 8 → **4 taps** after the idle re-time (1.41 → 1.21×); the §12.2F "soft inverse-square" row claim was dropped; 45° edges get ≈1.4× the spill of axis edges | 1.21 |

Re-time method: interleaved HEAD/new, min-of-drained-frames, 6 rounds, median of per-round ratios, machine load 2–3 (`agents`-gitignored harness; table in the scratchpad). Rounds still spread ±0.2–0.3 at this frame size; read each figure as ±0.05–0.1.

## What the deviations mean (read these before merging)

1. **Flame attractor changes its default look completely.** HEAD rendered a saturated white wall (the committed thumbnail is 100 % white); the orbit map is contractive so late iterations add a pixel-independent plateau. After the log-density display the idle frame is a low-contrast salmon/magenta field and with audio a swirling flame. This is a rescue, not a "same picture, richer" upgrade, and it changes `A`'s numeric domain: A now stores log-density display-linear HDR (≤ 8) instead of raw density-linear HDR. C is read only as that same colour history, so the loop is consistent, and the JSON `feedbackPacking` says so. A silent frame still has little structure; fixing it would mean touching the accumulators the card froze.
2. **Reaction-diffusion was dead at HEAD** (U floored at ≥ 0.75, V = 1 absorbing: frozen black frame after ~15 s; numpy port and SwiftShader agree). The rescue removes the floor and shifts the kill range by +0.005 (same span and role, saved params/ranges byte-exact). Pre-existing presets will land on a kill rate 0.005 higher than before. The sim is alive but cycles with ~20–25 % flat phases in the numpy run. The photo-driven kill map is weak (3–7 %) and at the darkest pixels reaches the flat-active edge of the pattern band.
3. **Abyssal geode was black at silence** (`ao = 1 − 100/100 = 0`; emissive = cyan·bass + magenta·mids = 0) and raw-HDR white with audio. The lit cavern is the biggest visible change in the batch; Rescue 5 (gravity well) is real (held vs free cursor changed 85 % of pixels at t ≈ 0 and exactly 0.00 % at t ≈ 20 s at HEAD).
4. **Haze ideas are small by the numbers.** The ring-frequency rescue (15 → 80 rad/uv: HEAD fitted 0.37 of a wavelength in the aura disc, so no ring was ever resolved) is the largest part of its visible change. Raising the idea visibility further needs a whole-image glow or a neutral-rule change, both on the card's FORBID list, so it was not done. Whether this counts as an upgrade is the owner's call.
5. **Kimi Idea 4 is only visible during click ripples** (the wide-stencil curvature is gated by a window around live rings; the un-gated version drew the seed-cell tile grid over the glass, found by looking at the 576 on/off diff). The card's physics is right and kept; the default-slider "several percent" target is not met for this idea.
6. **Neon spill has a diagonal bias** (4 axis taps: a 45° edge gets ≈1.4× the integrated spill of an axis edge over a shorter reach, 22.5° ≈ 1.27×) and a hard-edged box pool; thin 4-px lines show two detached stripes beside the tube. Striations are tile-local, so diagonal edges can jump up to half a band at tile boundaries. All three are visible in the 5× crops (`forkE/bias_crop_*.png` in the scratchpad), none at normal zoom.

## Floor checks (all ten)

- Saved `params` byte-exact against HEAD in all ten definitions (checked programmatically). Description growth ≤ +72 chars (limit ~80). `x-meta.upgrade.params` added additively where missing; no new schema keys (`feedbackPacking` already existed on the flame definition).
- Bindings from `#include "_prelude.wgsl"` everywhere; `radiating-haze` + `reaction-diffusion` migrated header-only first and their ids removed from `prelude_migration.json` `pending` (no `Upgraded:` bump for the migration itself).
- A packing stated and consistent with how C is read: kimi / oil / RD / haze raw (no ACES on stored fields); flame + galaxy + aurora raw HDR history, ACES on `writeTexture` only; abyssal / kaleido / neon ACES display RGBA.
- Exact `textureLoad` for history everywhere; the filtering-sampler-on-`rgba32float` defect (galaxy, aurora) fixed; `pow(negative, 2.0)` replaced by squares in kimi, oil, neon (invisible on SwiftShader — real-GPU benefit unverified).
- No spring / ripple / IQ-palette overlay added to any file that did not already own it; `extraBuffer` untouched.

## §12.7 formula accounting (no row on more than one file)

Cauchy dispersion (kimi) · fold count as material (kaleido) · energy-conserving bloom (haze) · orbit trap, Beer–Lambert, step-count AO (abyssal) · blackbody (flame) · thin-film phase, shallow-water continuity (oil). **Unused:** isotropic 9-point Laplacian (RD, replaced), soft inverse-square (neon, dropped). Everything else is native to its own file.

## Gates (final tree)

| Gate | Result |
|---|---|
| `npm run verify:shaders:fix` | all 11 shader gates pass (extraBuffer 0 new, dead sliders 0 new, workgroup 0, catalog drift 0, naga-wasm) |
| `npm run verify:toolchain-foundation` (after build) | 13/13 |
| `npm run test:ci` | 1943 pass / 1 fail / 1 skipped. The failure is `src/components/graphLab/WgslDraftSection.test.tsx` (CodeMirror lint-mark timing), **7/7 when run alone**; it did not touch any file in this batch |
| `npm run build` | ok |
| per-shader precommit + naga-wasm | pass (forks), shader gates re-run by the coordinator |
| `npm run upgrades:record -- --ids=<ten>` | 8 changed + 2 new baselines (the two first-pass files had no ledger entry) |

Side effects reverted before commit: `README.md` catalog counts (main's drift), both `shader-id-aliases.json` date bumps, every `reports/*` file except `shader-upgrade-ledger.json`. Kept because they are real generated output of this batch: the five `public/shader-lists/*.json` files (only the ten ids' entries differ — checked) and `public/shader-search-index.json` (description, hash and embedding for exactly the 8 ids whose descriptions changed).

## Open items for the owner

1. **Real-GPU look.** Ideas were verified by SwiftShader pixel differences and the contact sheets only. Default-look changes to eyeball: abyssal (black/white → lit cavern), flame (white → salmon/flame), galaxy (blob → arms), aurora, kaleido (−5–10 % luma), reaction-diffusion (kill +0.005), haze (rings + trail 0.4).
2. Abyssal costs 1.31× with audio at 256 px (1.21× idle); that is at the 1.3× cap on SwiftShader and has not been timed on a GPU.
3. Galaxy `arm_tightness` is dead at silence (it enters only as `bass·p1·0.15`) — HEAD behaviour, card said keep. The silent default is HEAD's tight spiral; open arms need bass. `orbit = time·rate` still snaps the pattern when mids / spin change (HEAD behaviour).
4. Kaleido: ~90 % of the frame at default zoom is border-clamped colour because `hypR` pushes samples past the clamp beyond r ≈ 0.17 (HEAD behaviour, left alone). The seam rescue hides the atan2 seam as a mirror junction; it does not remove it. Ring Offset only shows on the thin boundary lines (0.1 %).
5. Haze persistence drift assumes 60 fps. Flame ember rise is `round(res.y/96)` px per frame (2 at 192 px, 11 at 1080 p) — frame-rate dependent like HEAD.
6. Thumbnails for all ten are now stale in the ledger; refresh on a GPU machine (Shader Scanner → *Changed since last thumbnail*).
