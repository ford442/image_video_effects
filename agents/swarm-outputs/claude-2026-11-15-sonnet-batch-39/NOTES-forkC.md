# NOTES — fork C (gen-fractal-flame-classic, gen-iris-bloom-fractal) — batch-39, 2026-11-15

Worktree `/root/iv-sonnet-batch-39`. No git operations. Edited only: `public/shaders/gen-fractal-flame-classic.wgsl`, `public/shaders/gen-iris-bloom-fractal.wgsl`, `shader_definitions/generative/gen-fractal-flame-classic.json`, `shader_definitions/generative/gen-iris-bloom-fractal.json`.
All numbers: SwiftShader WebGPU, saved-default sliders passed explicitly (flame 0.55,0.5,0.5,0.3; iris 0.55,0.65,0.45,0.3). `pct` = % of pixels whose max-channel |Δ| > 0.02 between the final file and a scratch copy of it with ONE idea zeroed (rgba32float writeTexture compare, 192 and 576 agree to ±0.2 %). Click cases used a scratch copy of the harness that injects ripples (`forkC/mr_rip.mjs` in the scratchpad; `agents/mr.mjs` untouched). Ratio timings are paired (see below), not run-to-run. **No real-GPU claim of any kind.**

---------------------------------------------------------------------------------------------------------------------------------

## 1. gen-fractal-flame-classic  (card 5)

**KEEP VERBATIM — held, with one stated exception.** Variation set and the `pick`-band blend (swirl / horseshoe / polar / spherical / julia), the affine step, log-density compression + per-channel vibrancy (2026-10-10 Idea 1), julia branch flip (Idea 2), click flame fronts, held centre shift, ACES on writeTexture only, A = raw HDR display RGBA (C read as the same colour history), the 4 saved params and roles, alpha semantics, depth. **Exception (deviation from the card's "keep the HEAD constants"):** the trap ring width (12 → 24 /unit r, audio term 8 → 16) and the centre-glow decay (4.5 → 9) were tightened as part of Rescue 1; accumulators keep their roles. `hueMoment` now holds a colour-index moment (Σ w·f·c) instead of Σ f·i.
**A packing: raw HDR display RGBA — unchanged.** Numeric domain: `hdrColor` is now much lower on average (meanL 0.55 → 0.36 at idle), so an old A/C left over from HEAD is not an issue (C is only the 5 % colour echo). JSON `feedbackPacking` ("A/C = raw HDR display RGBA history") is still true; not edited.

### Rescue 1 — orbit plateau: CONFIRMED at HEAD (render + numpy port), fixed
- HEAD render, 256 px, 4 s: idle meanL 0.548 / **stdL 0.011**, audio 0.578 / 0.011 — a flat orange wall with ±1 % swirl structure.
- Numpy port of the loop (reproduces HEAD: meanL 0.608 / stdL 0.015 at 192): accumulated density is 0.505 ± 0.050 — a 10 % relative spread. Per iteration the pixel-independent part dominates because every orbit lands in the same compact attractor; the log-density display then maps it all into the saturated red channel. The orbit is not a clean fixed-point plateau (some iterations are flung far by `z/r²` / horseshoe), but each iteration still contributes ≈ 0.02 to *every* pixel.
- Rejected on the way (numpy, final-luma std): black point alone with HEAD widths 0.044–0.055 (red channel saturates through ACES, std of `(r+g+b)/3` stays ≈ 0.05); narrower traps alone 0.019–0.069; |Δz|-gated accumulation 0.023.
- **Shipped:** (a) trap ring 12 → 24, centre 4.5 → 9 (rarer hits, contrast), (b) black point `PLATEAU = 0.006` per unit of accumulated weight `wsum = Σ 1/(1+0.025 i)` — ≈ the 1st–10th percentile of density-per-weight at 31–48 iterations and the 10th–30th at 12 iterations (numpy over iterations 12..48 × variationMix 0..1), so a pixel is only black where its orbit really missed everything, (c) `DENS_GAIN = 1.5` restores exposure; `alpha` coefficient 0.46 → 0.8 (HEAD's was calibrated to the plateau flame; without it meanA fell 0.74 → 0.30).
- Result (192 px, SwiftShader): idle **meanL 0.363 / stdL 0.163** (HEAD 0.548 / 0.013), audio 0.401 / 0.129, meanA 0.524 / 0.418. Card target stdL ≥ 0.10 met. Held cursor and audio each change 91 % / 99.9 % of pixels vs idle.
- Slider sweep (192 px; run before the trig trim + alpha change, meanL within ±0.01 since): iterations 0 → 1: 0.199/0.106 → 0.543/0.161; variationMix 0 → 1: 0.343/**0.034** → 0.331/0.111; flameZoom 0 → 1: 0.376/0.170 → 0.361/0.156; paletteCycle 0 → 1: 0.379/0.157 → 0.400/0.203 (spectral/violet). All four sliders change the picture. **`variationMix = 0` (pure swirl) is a smooth orange swirl (stdL 0.034)** — a swirl-only orbit has no fold structure; not a defect of the rescue but a low-contrast corner.

### Idea 3 — colour-index averaging (native; the flame's own colouring), shader L83-96, L124-135
`c ← (c + c_v)/2` per iteration, where each variation owns a colour coordinate that is a function of what it did (swirl rotation r²/2π, horseshoe fold `0.5 + xy/r²`, polar angle, spherical `r/(1+r)`, julia branch `0.5+0.5·julia.y/√r`), blended with the *same* weights (`variationMix`, `wPolar`, `wSph`, `wJul`) that blend the variations. The density-weighted mean colour index (`hueMoment/density`) now picks the point on a warm flame gradient (deep red ← classicWarm at 0.5 → gold; `classicWarm` is the mid-point, so a flat index reproduces HEAD's tint) and drives the spectral hue at `paletteCycle`. HEAD's hue term (`Σ f·i / (12·density)·0.002`) was ≈ 0.08 and nearly constant.
Visibility (idea zeroed = `ciMean = 0.5`): **75.5 % / 75.6 %** of pixels (192 / 576 idle), 95.7 % / 95.6 % with audio; mean |Δ| 0.024 idle / 0.033 audio.

### Idea 4 — two-layer tint, "final-transform bloom" (native), shader L136-144
The ring-trap share and the centre-glow share of the one density now carry different tints: `coreFrac = smoothstep(0.30, 0.75, coreAcc/density) · smoothstep(0.05, 0.45, denseTot)` mixes the tint toward a white-hot `coreTint (1.3, 0.95, 0.55)`; ring share keeps warm-gradient/spectral. One extra scalar accumulator (`coreAcc`). Card said "ring = classicWarm→spectral, core = white-hot" — implemented as a per-pixel fraction, not two separate density sums (the log-density is still of the total).
Visibility (idea zeroed = `coreFrac = 0`): **63.4 % / 63.4 %** (192 / 576 idle), 49.3 % / 49.4 % with audio; mean |Δ| 0.069 idle. This is the idea that gives the picture its white-hot filaments.

§12.2 rows: none (both ideas native). No blackbody / orbit-trap / Beer–Lambert (reserved for other files).

### Cost
Added per iteration: ~4 mult/div + 1 `fract` (no new transcendentals — `sin 2θ`, `sin(θ/2+b)` and `1−e^{−r}` were replaced by `xy/r²`, `julia.y/√r`, `r/(1+r)` after a first version used trig), 2 accumulators (`coreAcc`, `wsum`); display adds two `smoothstep`s. Paired timing (both pipelines in one page, alternating frames, 192 px, min of drained frames; machine load average 30–40 from sibling forks): idle min-ratio **1.16, 1.07, 1.01**, audio **1.08**. Run-to-run timing was useless at this load (ratios 0.44 – 2.34), so the earlier per-process attempt is discarded. Coordinator should re-time alone.

### Gates
`wgsl_precommit_gate` pass; `verify-naga-wasm --files` pass; `audit:dead-sliders` 0 new; `audit:extrabuffer` no new finding (file does not touch extraBuffer). `A16=1`, 120 frames, held cursor + audio: nan 0, meanL 0.454 / stdL 0.145 (no white-out, no drift). Saved `params` byte-identical to HEAD (checked programmatically). Description +69 chars (131 → 200). `x-meta.upgrade.params` already present. Click case: ripple fronts still draw (1.5 % of pixels differ with two live ripples, same thin ring as HEAD).

### Open items
- **Atan2 seam (HEAD, not touched):** a horizontal straight seam across the left half (the negative-x axis) from the `polar` (`θ/π`) and `julia` variations' branch cut. It was ±1 % at HEAD's flat wall and is now visible against the higher contrast (visible in the 192 and 576 renders). Fixing it means changing the polar/julia variations (card: keep verbatim) — owner's call.
- Default look changes completely (flat orange wall → dark lanes with orange filaments and white-hot cores; meanL 0.55 → 0.36); real-GPU look needed. `Iterations` slider top end (48 its) washes toward white (meanL 0.54) because exposure still grows with iteration count — as at HEAD.
- `variationMix = 0` low-contrast (above).

---------------------------------------------------------------------------------------------------------------------------------

## 2. gen-iris-bloom-fractal  (card 6, third pass)

**KEEP VERBATIM — held.** Whole file: petal layer loop (+ Idea 2 stroma parallax), irisMask / pupil / veins / limbal / collarette zigzag / Fuchs crypts / tension rings, click bloom, palette, history mix `0.27 + 0.012·bloomDepth`, ACES, depth, 4 saved params and roles. Earlier four Ideas stay on the `Ideas:` line. Only code motion: the click loop moved above the aperture computation (same maths) so the reflex can read it.
**A packing: raw HDR display RGBA — unchanged.**
HEAD render idle: meanL 0.363 / stdL 0.226 / meanA 0.524. New idle: **0.354 / 0.222 / 0.525**; with one click at age 1 s: 0.367 / 0.213 / 0.535. No HEAD defect found (the card listed none).

### Idea 5 — pupillary hippus + click light reflex (native), L36-56
`hippus = 1 + 0.05 sin(0.47t+0.3) + 0.032 sin(1.13t+1.9) + 0.02 sin(1.87t+4.1)` (0.075 / 0.18 / 0.30 Hz, ≈ ±10 %), and `reflex = max over live clicks of smoothstep(0,0.2,age)·exp(−max(age−0.2,0)·1.1)`, `aperture *= hippus · (1 − 0.26 reflex)`. `aperture` is the radius every layer uses, so the whole bloom breathes. HEAD's `(1 + bass·0.08)` kept (psychosensory dilation is real, so I did **not** reverse its sign as the card first suggested — the click is the light flash).
Visibility (idea zeroed = `hippus = 1`, `reflex = 0`): idle **48.3 % / 48.2 %** (192 / 576; 16.5 % above 0.05), with a click at age 1 s **66.8 % / 66.8 %** (42 % above 0.05; A alpha changes on 55 % of pixels).

### Idea 6 — contraction furrows (native), L87-97, applied L112-113
2.6 periods of a wobbling (`3θ`, `7θ`) groove from `furIn = min(1.5·aperture, 0.36)` to the limbus: `raw *= 1 − 0.5·groove·band·depth` and a warm lip `+(0.55,0.36,0.2)·lip·0.22·band·depth`; `depth = mix(0.45, 1, smoothstep(0.1, 0.3, aperture))` so a dilated pupil shows them deeper. First version started at `2.15·aperture` (= 0.41 at the default aperture, a band 0.08 wide) and was invisible; fixed after looking at the 576 render.
Visibility (idea zeroed): **22.4 % / 22.3 %** idle, 25.8 % / 25.7 % with a click.

### Idea 7 — corneal catchlight (native), L98-103, applied L116
Rounded-window SDF highlight at screen `(−0.075, −0.085)` (upper left of the default pupil), fixed in screen space (the iris moves under it when the held pointer shifts it), clipped to the eye disc, `catchlight·2.4` HDR, and `catchlight·0.9` added to `coverage` so the highlight is opaque (otherwise it sits on α ≈ 0.03 over the pupil). First version (grey square, 0.9) read as an artifact; brightened and rounded.
Visibility: **0.50 % / 0.51 %** of the frame (≈ 0.7 % of the eye disc) — by design a small local highlight, below the "several percent" target; kept because it is cheap and reads as an eye. Drop it if the owner prefers.

§12.2 rows: none (all native).

### Cost / gates
Paired timing at 192 px (load 30–40): idle min-ratios 0.87, 0.77, 1.24, audio 1.12 — within noise of 1.0; the shader is ~15–25 ms at that size, so noise dominates. Added work: 3 `sin` for hippus, ~2 `cos` for the groove/lip (4th powers by squaring, no `pow`), one rounded-box SDF. `wgsl_precommit_gate` pass, `verify-naga-wasm --files` pass, `audit:dead-sliders` 0 new, `audit:extrabuffer` clean. `A16=1`, 120 frames, held + audio: nan 0, meanL 0.421 / stdL 0.265. Slider sweep (192 px): all four sliders change the picture (petalCount, bloomDepth: structure; aperture 0 → 1: meanL 0.367/0.189 → 0.255/0.255; colorCycle: hue only, identical luma). Saved `params` byte-identical. Description +49 chars (135 → 184).

### Open items
- The reflex is global (any click, anywhere, constricts the pupil) — a flash, not a pointer-located effect.
- The ghost of the previous pupil edge persists a few frames through the existing history mix (`0.27+0.012·depth`) when the pupil snaps on a click; looks like pupil-edge smear, not seen as a defect, but only SwiftShader-checked.
- Catchlight is small (0.5 % of frame).

---------------------------------------------------------------------------------------------------------------------------------

## Scratch artefacts (not in the repo)
`/tmp/claude-0/-root-image-video-effects/1e2b4f73-719d-4020-abc4-bf82730a8edd/scratchpad/forkC/` — numpy ports (`flame2.py` … `flame7.py`), renders (`fl_*`, `ir_*`, `*_sweep.png`, `fl_ideas.png`), harness copies (`mr_rip.mjs` ripple injection, `mr_perf.mjs`, `mr_pair.mjs` paired timing), variant WGSL with one idea zeroed (`var/`).

- Hygiene, no visual change: HEAD's `crypts = pow(0.5+0.5cos(..), 16)` got a `max(.., 0.0)` guard (a rounding-negative base is undefined for `pow`); render Δ = 0.
