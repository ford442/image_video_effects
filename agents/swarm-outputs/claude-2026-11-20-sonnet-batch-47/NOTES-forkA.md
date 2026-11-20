# NOTES — fork A (interactive-rgb-split, chromatic-swirl)

Cards + mechanism interrogation: `BRIEFS-forkA.md` (written before any WGSL edit). Both files second pass. VM = SwiftShader,
no real GPU: structural + software-render evidence only, **no visual-QA claim**. Box load average was 25–30 on 8 cores the
whole time, so every timing below is a median over interleaved rounds, not a single reading.

## interactive-rgb-split

**ADD** (findable by `// ── Idea n` comments)
1. **Brown–Conrady radial growth (§12.2B)** — radial mode only: `smoothOffset = (uv − mouse)·amount·(1 + 0.6 r² + 0.25 r⁴)`,
   r = the existing aspect-corrected `dist`. Lateral colour is zero under the pointer and grows superlinearly outward,
   like an uncorrected lens. Directional mode (prism) unchanged.
2. **Spectral band smear** (tactic 1, kernel deepening) — `bandSample()`: each channel integrates its band with 3 taps at
   `s·(1−0.22)`, `s`, `s·(1+0.22)`, weights 1-2-1. Band centres stay HEAD's 1.15 / 0.70 / 1.35, so the centroid of each
   channel (the split geometry) is unchanged; the three hard ghost images become a continuous gradient. Width follows
   `|field|`, so it closes where the split closes.

**KEEP VERBATIM:** 4 params and roles; `field = smoothOffset + rippleOffset + jitter`; the existing Ideas (1.15/0.70/1.35
scales, lateral-vs-longitudinal `longW` mix); `splitMix`, `spectralTint`, depth blend, Schlick edge, vignette, ACES.
**A packing:** display RGBA (unchanged; nothing reads C). **Rescues:** none (no HEAD defect found). Hygiene: the duplicate
depth tap at the end reuses `depth` (zero pixel change, −1 tap).
**JSON:** `description` appended (visible behaviour changed); `params` byte-exact; `features` unchanged (no new claim).
**Header:** `Upgraded: 2026-09-08, 2026-11-20`; `Ideas:` extended; `Features:` unchanged.

**Diff vs HEAD (SwiftShader, 320 px, raw RGB panel):** quiet by design on soft imagery — default params
(0.5/0.5/radial/0) on the smooth synthetic photo: 0.4 % of pixels differ >2/255. On hard edges (`SRC=tex`, strength 1,
falloff 0.3): radial 54.8 % >2/255 (20.8 % >8/255), directional 32.3 % (6.1 %). Strength 1 / falloff 0.2 / pointer off
centre + audio + 2 ripples: 25.1 % (3.4 %). NaN 0 everywhere, alpha mean ≈ HEAD (0.162→0.164 default; 0.273→0.301 with audio+ripples).
**Timing (`mr_perf`, 256 px, 150 frames, 5 interleaved rounds):** median **1.27×** HEAD (rounds 1.32, 1.20, 1.27, 1.10,
1.31); a 2-tap variant measured ≈1.1× (rounds 1.10, 1.21, 1.00, 1.06, 1.66, noisy) but gives a two-step comb on hard edges,
so the 1-2-1 3-tap was kept (taps 6→11: 9 band + base + 1 depth vs HEAD 3 + base + 2 depth). Earlier 384 px / 30-frame
runs were unusable (HEAD itself varied 20–107 ms between rounds); the 2-tap comb is from reasoning, not rendered.

## chromatic-swirl

**ADD**
1. **Cauchy radial lateral colour (§12.2F)** — per-channel radial scale `s_c = 1 + 0.25·aberration·(1/λ_c² − 1/λ_G²)`, λ in
   µm from the file's own `WAVELENGTH_RED/GREEN/BLUE` (previously used only for absorption); applied to the offset vector
   before the existing per-channel swirl rotation, so it composes with the angular split. R samples nearer the pointer
   (larger image), B farther (smaller). Strength rides the existing `aberration` slider (+ treble term HEAD already adds).
2. **Rayleigh in-scatter of the absorbed light (§12.2F)** — `inScatter = (1 − T)·(0.18·L)·t_c`, `T = (alphaR,G,B)` (HEAD's
   Beer–Lambert transmittance), `L` = luminance of the un-attenuated sample, `t_c = (λ_G/λ_c)⁴` normalised to luminance 1.
   The medium now returns ≤ ω = 0.18 of what it extinguishes, blue-weighted, so a thick core is a dim indigo haze instead
   of dead black. `swirlGlow` kept.

**KEEP VERBATIM:** 4 params and roles; `angle` law (percent², spin when `animate`>0.5, ×2 on mouse-down); `extraTwist`;
`angR/G/B = base·(1 + 2.8a / 1 / 1 − 2.2a)`; `calculateChannelAlpha`; `finalAlpha`; warm/cool grade; `swirlGlow`; depth;
ACES; A = telemetry (dist/radius, angle/12, aberration, alpha). **A packing:** HEAD telemetry kept (nobody reads C).
**Rescues:** none. **JSON:** untouched (no `description` key exists to append to; `params` byte-exact; `x-meta.upgrade.params` already aligned).
**Header:** `Upgraded: 2026-09-08, 2026-11-20`; `Ideas:` extended.

**Diff vs HEAD (320 px, `SRC=img`):** default 95.7 % >2/255, 64.2 % >8/255 (dominated by the in-scatter lifting every
pixel a little: mean output luma 0.155→0.188); animate + audio 99.7 % / 94.2 %; mouse-down + strength 0.7 + audio 100 % / 95.7 %
(HEAD's black disc becomes a navy haze with the spiral visible; mean luma 0.045→0.093). Alpha mean identical to HEAD in
all three (0.592 / 0.37 / 0.203) — `finalAlpha` is untouched. NaN 0.
**Timing:** ≈ **0.97×** HEAD (rounds 0.99, 0.81, 1.00, 0.97, 0.92) — no new taps; the added maths is constant-foldable.

## Gates (each file) — 2/2
`wgsl_precommit_gate.py` 2/2 · `verify-naga-wasm.mjs --files` 2/2 · `audit_dead_sliders.py --files` 0 new · `audit_extrabuffer.py` PASS
(neither file touches extraBuffer). No `fwidth`, no unguarded `pow` (Rayleigh base is a ratio of positive constants),
nothing negative into ACES (`1 − T ≥ 0`).

## For the coordinator / open decisions
- chromatic-swirl changes **every pixel** a little at defaults (in-scatter) and visibly changes the extreme case (black core → haze). ω = 0.18 is a literal; lower it if the dead-black core is considered identity.
- rgb-split is 1.27× HEAD median at the cap's edge on a loaded box; the 2-tap variant (≈1.1×) is the fallback if it matters.
- Not verified: real-GPU look, the fringe gradient on real photographs.
