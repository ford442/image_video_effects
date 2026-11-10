# COORDINATOR_REVIEW — sonnet/batch-36 (glitch / spectral / distortion / neon-warp ten)

Written at first push (PR #1670). Cards: `BRIEFS.md` (committed before any idea edit). Fork notes: `NOTES-fork{A,B,C,D}.md`. Three unanchored reviewers (they saw the cards, not the forks' notes) measured visibility and read the diffs; reviewer C (neon-warp, hybrid-fractal-feedback) had not reported when this was written.

## Gates (all ten, SwiftShader / structural only)
precommit 10/10 · `verify-naga-wasm --files` 10/10 valid · audit:dead-sliders 0 · audit:extrabuffer 0 · `verify:toolchain-foundation` 13/13 · `npm run build` ok · `npm run test:ci` 1821 passed / 1 failed (`shader search index > covers every entry with an embedding`, 1426 vs 1417 — already failing on origin/main, not from this batch). Saved `params` byte-exact on all ten (script-checked against HEAD). JSON `description` growth ≤ +63 chars. **No real-GPU visual QA.**

## Per shader
| Shader | Cards implemented | Reviewer findings → state |
|---|---|---|
| block-distort-interactive | chroma-from-tile-centre; elastic recoil | Reviewer A: ACES re-graded the photo (meanL 0.29→0.37) and the `10+alpha` sentinel collided with glitch-reveal's → **fixed** (no ACES; HEAD's additive light kept with a 0.8 tanh shoulder; cursor-away output bit-identical to HEAD; marker `40+alpha`; foreign C 10.7 and 0.7371 ignored). `aces-tone-map`/`upgraded-rgba` tags dropped. Idea 1 is photo-dependent (7.9 % of frame on a colourful photo, ~0.1–0.3 % on low-chroma); recoil decay is per frame and is a wake, not a spring. |
| glitch-reveal | staggered block re-key; sheared head-switch tear | Clean. Default feel changes from freeze + 2 Hz flash to continuous churn (10–22 %/frame) — disclosed in header. Shear is a mean-preserving 0.4–1.6× ramp, not the card's ±½. |
| circular-pixelate | PSF footprint integration; cat's-eye vignetting | Clean. Idea 3 weights are uniform (not aperture-weighted as carded). Radius=1 coverage loss fixed after review (`catRoom` fade). |
| blueprint-reveal-guided | pen hairlines (NMS + depth-step weight); tone hatching | Reviewer A: dim lines, grid shifted by ACES, hatch inverted → **fixed** (grid + lines after ACES, p99 1.00; hatch dark = dense; alpha clamped; header tag). The flat-depth 80 % blend to a 7×7 guided mean is HEAD behaviour, kept and disclosed. Depth-outline weight is still modest. |
| rgb-ripple-distortion | Cauchy dispersion; deep-water ripple dispersion | Reviewer B: **OPEN** — `sepGain = 0.5+5w` makes the default R/B split 3× HEAD's (HEAD's was < 1 px, i.e. effectively dead; card said keep HEAD magnitude) — declared as a rescue, needs a real-GPU eyeball; rest is now an exact pass-through (idle meanL +29 %), ripples read as slightly dark discs; the train raises stress (saturated blobs at ~0.4 s). |
| rgb-distance-split | longitudinal CA; secondary spectrum | Reviewer B: **OPEN** — header/description claim "red and blue on the same side (purple fringe)"; measured offsets are R +1.3 / B −0.7, i.e. opposite sides (lopsided, not purple). 2-tap defocus shows discrete ghost copies at the largest radius. |
| spectral-vortex | Lamb–Oseen pointer vortex; luma-preserving hue spin | Reviewer B: **OPEN** — YIQ spin runs the opposite way to HEAD's HSV spin (`ang` sign); Lamb–Oseen uses rc 0.12 (card 0.06–0.08), far field 1.8–6× HEAD — footprint change not stated in header. Spring removal verified output-identical to HEAD. |
| data-scanner-gabor | Gabor energy (quadrature); orientation needles | Reviewer B: **OPEN** — over smooth content the bar is *darker* than the dimmed surround (flat 0.6 source: bar 0.245 vs outside 0.36; HEAD 0.693) from the `color*0.18` floor + un-normalised energy weighting; needles are 0.8 % of frame on smooth content at 576; `atan2(V.y, V.x)` unguarded at E=0. ~2× faster than HEAD. |
| neon-warp | Gladstone–Dale refraction (idea 4); Planck-cooling afterglow (idea 5) | Fork D measured 15.7 % / 25.3 %. Afterglow became a per-pixel heat memory in `A.a = 10 + mem` (declared packing change). **Reviewer C pending** — the 10..11.5 band is the same one glitch-reveal uses; check foreign-C handling. |
| hybrid-fractal-feedback | smooth iteration + orbit-trap veins; video-feedback transform | Fork D measured 72 % / 65 %; A-texel spring revived. **1.38× HEAD at 576 px** (target 1.3×; dropping the trap or one nearest history load reaches 1.2×). **Reviewer C pending.** Default look is a large intended change (aspect fix, ACES on the fractal term, feedback transform). |

## Row budget
Cauchy-family dispersion: rgb-ripple-distortion (Cauchy) + rgb-distance-split (secondary spectrum). Deep-water: rgb-ripple only. Block quantization: block-distort-interactive only. Sync-pulse timing: glitch-reveal only. Orbit trap / smooth iteration: hybrid-fractal-feedback only. No row on more than two files.

## Open before "ready"
The OPEN rows above, reviewer C's report, a quiet-machine re-time, and a real-GPU look. Fixes go in as follow-up commits to this PR.
