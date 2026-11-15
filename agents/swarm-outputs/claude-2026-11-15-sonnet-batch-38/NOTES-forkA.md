# NOTES — fork A (kimi-liquid-glass, liquid-oil) — batch-38, 2026-11-15

Worktree `/root/iv-sonnet-batch-38`. No commits. Edited only: `public/shaders/kimi_liquid_glass.wgsl`, `public/shaders/liquid-oil.wgsl`,
`shader_definitions/liquid-effects/kimi-liquid-glass.json`, `shader_definitions/liquid-effects/liquid-oil.json`.
All numbers: SwiftShader WebGPU via a scratch COPY of `agents/mr.mjs` (adds edge source, ripple injection, min-of-drained-frame timing), saved-default
sliders passed explicitly (kimi 0.5,0.5,0.5,0.5; oil 0.5,0.4,0.5,0.3), `pct` = % of pixels with max-channel |Δ|>0.02 against the same file with
the idea's constant zeroed. **No real-GPU claim of any kind.**

---------------------------------------------------------------------------------------------------------------------------------

## 1. kimi-liquid-glass  (`kimi_liquid_glass.wgsl`)

**KEEP VERBATIM held.** Both new ideas zeroed (`DISP_K` path replaced by HEAD's fixed ±delta, `CONVERGE_EXTRA = FOCUS_GAIN = DIVERGE_SHADE = 0`) gives
Δ = 0.0000 against HEAD at 256 px / 120 frames, idle and with two live ripples + held pointer + audio (the TIR flank, rising seed bubbles, the
height/velocity/thickness solver and the saved param slots are untouched). **A packing: raw, unchanged** (R=height, G=velocity, B=thickness,
A=coverage); ACES stays on `writeTexture` only. Params in the JSON are byte-exact.

### Rescue 1 — `pow(negative, 2.0)` in the click ring (L78–80): CONFIRMED at HEAD by reading
HEAD: `pow((dist - age*(…)) * (36+detail*18), 2.0)` — the base is negative behind the ring front, `pow(x<0, 2.0)` is undefined in WGSL
(NaN on some GPUs). Now `ringArg * ringArg`. SwiftShader evaluates the old form to the same value, so there is **no visible change here**
(both-off ≡ HEAD Δ = 0 even with ripples); the fix is for other drivers and cannot be shown on this VM.

### Idea 3 — Cauchy dispersion (§12.2F), L99–116
n(λ) = A + B/λ² with λ = 650/550/450 nm; the R and B channels sample the photo at the first-order Snell shift `−dn/n²` along the surface normal,
amplitude `dispAmp = 0.001 + detail·0.006 + treble·0.0025` times `DISP_K`. Replaces HEAD's symmetric ±delta, so the fringe is now **non-linear
and asymmetric** (blue fans out more than red) — HEAD had R/B mirror images.
Measured (i3off→new, 180 frames):

| source | size | idle | held | click | audio |
|---|---|---|---|---|---|
| smooth gradient | 192 | 0.72% | 0.75% | 1.27% | 1.29% |
| smooth gradient | 576 | 1.32% | 0.88% | 2.16% | 2.78% |
| strong edges (checker/lines) | 192 | 8.28% | 12.05% | 11.98% | 11.73% |

The effect is a fringe on photo edges, so it is content-dependent: ~1% on a smooth photo, 8–12% when the source has contrast edges (that is
what a real photo has). Edges source at 576 was not re-measured.
**Default-look change:** `DISP_K = 200` is ~1.5× HEAD's fringe magnitude (130 reproduces HEAD's mean ≈0.0011 uv shift). The card asked for ±30% of HEAD's fringe;
that conflicted with the rule-11 visibility target, so I chose 1.5× and flag it (I did not keep a measurement of the ±30% variant). Set `DISP_K = 130` to restore HEAD's amplitude.

### Idea 4 — signed-focus caustic (native: energy accounting), L55–64, L73–82, L118–135
HEAD's caustic used `|laplacian|`: a dishing surface glowed as brightly as a focusing one. Now: converging curvature (`lapWide < 0`) adds a brighter
caustic line (`CONVERGE_EXTRA`) and gains light in the transmitted photo; diverging curvature (`lapWide > 0`) dims the photo (`FOCUS_GAIN` =
`DIVERGE_SHADE` = 0.28, so mean luma is neutral). HEAD's `|laplacian|` term stays as is.
**What I found while measuring — and had to change:** the first version drove this from the 1-px laplacian. Rendering the on/off diff at 576 showed
the whole "visibility" (2–13%) was the **hashed seed-cell grid**: `velocity` is restored toward `seedHeight` every frame, so the ±0.0175 step
pattern of `hash21(cells)` is persistent, and its thin tile-edge laplacian dominates everything at saved defaults. The idea was drawing a faint tile
grid over the glass. Fixes, in order: (a) a wide stencil (R = res/96 px, normalised to 192-px px² so gain is resolution-free) — still lit the seed
edges as ~12-px bands; (b) subtracting the force-balance term — this turned out to measure the *modal forcing*, not curvature (saturated the whole
frame, +4% luma), rejected; (c) **gating by `driven`** — a broad Gaussian band around each live click ring (L82). Kept (a)+(c).
Consequence, stated plainly: **Idea 4 is click-ripple-local.** At saved defaults, with no ripple, the glass has no curvature other than the seed
grid (the held pointer bump is ~0.01 high, below the ±0.0175 seed steps), so the effect is exactly 0% idle / held / audio — by construction.
Measured with two fresh ripples (ages 0.45 s and 0.70 s at the last frame), i4off→new:

| size | % of frame | % inside r<0.25 of a ripple | max \|Δ\| | meanL |
|---|---|---|---|---|
| 192 | 1.31% (0.53% > 0.05) | 4.0% | 0.096 | 0.5204→0.5205 |
| 576 | 5.41% (1.23% > 0.05) | 16.4% | 0.086 | 0.5062→0.5060 |

idle / held / audio at 192 and 576: 0.00%. It is a concentric bright/dim ring pair around each ripple (viewed in `f_new_click_576.png`, diff in
`diff_f_i4_576.png`). Below the rule-11 target for a frame-global idea at 192; it is a ripple-local idea and I say so rather than hide it.
It was not replaced, because the card's idea is the right physics and the only honest alternative (curvature of the idle surface) is the seed grid.

### Whole file vs HEAD (default look), smooth source, 180 frames
| | idle | held | meanL HEAD→new idle / held |
|---|---|---|---|
| 192 | 0.72% (0.0018 mean) | 0.75% | 0.5095→0.5097 / 0.5191→0.5192 |
| 576 | 1.32% | 0.88% | 0.4993→0.4994 / 0.5068→0.5068 |

### Other checks
* A16 (`rgba16float` state) 60 frames, edges + 2 ripples + held + audio: nan = 0, meanL 0.431. 60-frame f32 run, same setup: nan = 0, meanL 0.431.
* Slider sweep min→max, one ripple, edges source (192, 40 frames): s0 52% / s1 27% / s2 33% / s3 43% of pixels changed → all four live.
* frameMs 256 px, interleaved HEAD/new, min-of-drained-frames, 10 rounds, **under sibling-fork load**: median ratio **1.13**, best-case-minima ratio
  1.23 (7.4→9.1 ms). Cap 1.3. Rounds ranged 0.87–1.42; the coordinator should re-time alone. (Idea 4 adds 4 `textureLoad` taps; Idea 3 adds one extra photo sample's worth of math.)
* Gates (final file): `wgsl_precommit_gate` pass, `verify-naga-wasm` pass, `audit:dead-sliders` 0 new, `audit:extrabuffer` 0 new, no pasted prelude.
* JSON: `x-meta.upgrade.params` added (copied from the saved params), feature tag `chromatic-dispersion` added, description untouched, params untouched.

### §12.2 rows used
§12.2F (Cauchy dispersion) for Idea 3, as named in the file header. Idea 4 is native (not a §12.2 row): energy accounting — a converging surface focuses, a diverging one starves.

---------------------------------------------------------------------------------------------------------------------------------

## 2. liquid-oil  (`liquid-oil.wgsl`)

**A packing: raw, unchanged** (R=film height, G=vertical response, B=shear, A=coverage); ACES on `writeTexture` only. Params byte-exact.
HEAD's two ideas (displacement wake, shear-aligned streaks) are untouched.

### Rescue 1 — `pow(negative, 2.0)` in the click ring (L76–78): CONFIRMED by reading, same pattern as kimi; now `ringArg*ringArg`. No visible change on SwiftShader.

### Idea 3 — angle-dependent thin-film phase (§12.2F), L120–129
Phase now carries `cos θ_t` from Snell inside the film (n = 1.47, `FILM_N`) using the incidence cosine the Fresnel term already computes, and the
channel cycle ratios are the true 650/550/450 nm ones (1 : 1.1818 : 1.4444). Flat film at normal incidence (cosT = 1) keeps HEAD's thickness phase,
so hue now drifts across curved film instead of being angle-blind. The (0, 0.2, 0.43) offsets are HEAD's stand-in for spectral response, kept.
### Idea 4 — gravity drainage with h³ flux (§12.2D shallow-water continuity), L83–90
Lubrication-theory flux F = h³; upwind along screen-down: `dh = −k·(h³ − h_above³)`, `k = DRAIN_K·(1 − 0.7·viscosity)`, `DRAIN_K = 0.15`
(CFL 3h²k ≤ 1 at h ≤ 0.75 → k ≤ 0.59). Thick wake rims slump into slow teardrops; thin film is almost still; mass is conserved up to the existing height clamp.
`oil_sim.py` (numpy port of the solver, 128², 300 frames) was run first, at a stronger k = 0.45 than shipped (0.15): all finite, mass conserved
(idle 0.2288→0.2289, drag 0.2711→0.2724), and the thick crests slump — drag-wake peak 0.677→0.455, height std 0.121→0.095 at viscosity 0.5 (same
direction at viscosity 0 and 1). I then lowered k to 0.15 so the effect reads as a slow sag, not a flattening; the shipped value was not re-run
in numpy, only on SwiftShader.

Measured (smooth source, i-off→new). The oil solver is chaotic, so a 180-frame diff against an idea-off run is inflated by trajectory divergence;
the **40-frame** numbers are the direct effect, 180-frame shown for completeness:

| case | size | frames | Idea 3 thin-film | Idea 4 drainage | whole file vs HEAD |
|---|---|---|---|---|---|
| idle | 192 | 40 | 4.15% | 7.78% (1.89% > 0.05) | 12.13% |
| drag | 192 | 40 | 7.30% | 8.28% | 15.57% |
| click | 192 | 40 | 4.23% | 7.81% | 12.16% |
| audio | 192 | 40 | 8.25% | 10.30% | 18.44% |
| idle | 576 | 40 | 2.85% | 2.11% (0.37% > 0.05) | 5.00% |
| drag | 576 | 40 | 6.20% | 2.20% | 8.28% |
| click | 576 | 40 | 2.90% | 2.13% | 5.05% |
| audio | 576 | 40 | 6.36% | 2.95% | 9.25% |
| idle | 192 | 180 | 11.67% | 40.4% | 41.0% |
| drag | 192 | 180 | 19.08% | 55.1% | 56.1% |
| click | 192 | 180 | 15.25% | 44.5% | 45.2% |
| audio | 192 | 180 | 19.17% | 48.0% | 49.1% |
| idle | 576 | 180 | 7.65% | 9.28% (0.86% > 0.05) | 14.67% |
| drag | 576 | 180 | 13.02% | 20.82% (3.32% > 0.05) | 26.20% |
| click | 576 | 180 | 8.60% | 11.17% | 16.85% |
| audio | 576 | 180 | 13.83% | 13.82% | 23.09% |

The drainage diff at 192/180f is organic flow (viewed: `diff_oil_i4_idle.png`, no tile grid — unlike kimi, drainage acts on the film, not a static seed
pattern). Idea 3 is below 0.05 everywhere (pct>0.05 = 0.00%): it is a hue drift, not a brightness change — that is what it should be.
**Default-look change:** meanL HEAD→new 0.4602→0.4595 idle (−0.1%), held-drag 0.4391→0.4346 (−1.0%, drainage pulls the wake rim down) — the
film visibly sags and the interference hue drifts across slopes. Both are the point of the cards, but they are default-look changes the owner should know about.

### Other checks
* 60-frame run and A16: nan = 0 (oil, both).
* Slider sweep: all four live (viscosity, turbulence, ripple strength, colour shift).
* frameMs 256 px, 10 rounds, interleaved, under sibling load: median ratio **1.07**, best-case minima 0.89 (11.7→10.4 ms). Cap 1.3.
* Gates: `wgsl_precommit_gate` pass, `verify-naga-wasm` pass, `audit:dead-sliders` 0 new, `audit:extrabuffer` 0 new.
* JSON: `x-meta.upgrade.params` added, feature tag `gravity-drainage` added, description untouched.

### §12.2 rows used
§12.2F (thin-film phase, angle-dependent) for Idea 3; §12.2D (shallow-water continuity, lubrication drainage) for Idea 4 — as named in the file header.

---------------------------------------------------------------------------------------------------------------------------------

## 3. Open items / what I could not verify
* **kimi Idea 4 is ripple-local** (0% at idle/held/audio, 1.3% / 5.4% of frame at 192 / 576 with fresh ripples). Faint seed-tile edges can still
  appear *inside* the ripple-driven band (≲ 0.03 in the diff); they vanish when the ripple expires. A visible-at-idle replacement would have to
  act on the seed grid itself — a HEAD behaviour I deliberately did not touch.
* **kimi Idea 3 deviates from the card's ±30%** (1.5× HEAD fringe, flagged above) and is content-dependent (≈1% smooth, 8–12% edges at 192; edges at 576 not measured).
* **Resolution shrinks kimi's curvature support** (1-px curvature of a fixed-UV feature falls as 1/res²); the wide stencil is normalised to a 192-px render to compensate.
* **oil's 180-frame percentages are chaos-inflated**; trust the 40-frame column for the direct effect.
* Timing is SwiftShader under five forks' load; do not quote 1.13× / 1.07× as performance. The coordinator re-times alone.
* The audit scripts (`audit:dead-sliders`, `audit:extrabuffer`, `wgsl_precommit_gate`) rewrite `reports/*` in the shared worktree; I restored the reports
  I dirtied, but any fork running them re-dirties them — `git checkout -- reports/` before the merge commit.
* No real-GPU verification. Nothing committed.
