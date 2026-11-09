# sonnet/batch-27 — fork C notes (double-exposure, heat-haze-mirage, interactive-zoom-blur)

Files touched: `public/shaders/{double-exposure,heat-haze-mirage,interactive-zoom-blur}.wgsl`, `shader_definitions/interactive-mouse/double-exposure.json` (features/tags only), `shader_definitions/distortion/interactive-zoom-blur.json` (features only). `heat-haze-mirage.json` is unchanged (every existing feature/tag is now true; `temporal-persistence` and `per-band-fft` were false before). Saved `params` are byte-exact in all three. No git add/commit, no generate_shader_lists.

Proof level: SwiftShader harness structural proof only (no real GPU, not visual QA). Renders were done with a scratch copy of the harness (`$S/forkC/render2.mjs`, = `render.mjs` + `--mouse-keys "f:x,y,down;..."` for a cursor path, `--dump f,f` for frame PNGs, `--trace 1` for per-frame meanL/max/NaN). Everything else is the stock harness.

Coordinator patch applied: `glideStep` validity check is `st.w >= 0.0 && st.w <= 1.0` in all three (f16 fract(time) rounding to 1.0).

Common to all three: R1 glide. `extraBuffer[133..]` is re-uploaded zeroed every frame, so HEAD's "spring" never persisted and every pixel fell back to the raw cursor. Replaced by a **first-order glide** (not a critically damped spring) in A texel (0,0) = `(glide.xy, 7.0, fract(time))`, rate = HEAD omega (double-exposure 13, heat-haze 3, zoom-blur 10). Visible change: at rest none (glide snaps to raw within 0.003, so identical to HEAD); moving: pivot / heat source / epicentre lags the cursor by about 1/rate s (77 ms, 333 ms, 100 ms). Texel (0,0) is never read as colour (each shader masks it, below); `writeTexture(0,0)` is the real display pixel.

## 1. double-exposure (interactive-mouse)

**Kept verbatim:** 4 params + mixes, pivot-relative transform, fbm domain warp, CA split on exposure 2, screen/overlay mix 0.35, ripple rotation + flash tint, C ghost trails (HEAD weight `mix(0.05,0.25,layerMix)` through post-ACES hist), ACES, semantic alpha, depth blend, `voroPattern`, HEAD's held steps (+0.25 rad rotation, ×1.2 layerMix).
**A packing:** ACES display RGBA; texel (0,0) = glide state. `fast-motion` dropped from banner and JSON features + tags.

| | what | where |
|---|---|---|
| Idea 1 | exposure-2 image circle, **cos⁴ vignetting** (§12.2 A): `cos⁴(atan(r/f)) = (f²/(f²+r²))²` (no trig), r = aspect-corrected distance from the glided pivot, f = 0.55·zoomLevel; strength `mix(0.35,1,cos⁴)` applied to exposure 2 in both blends (screen: `c2·ex2`; overlay: `mix(0.5, c2, ex2)` so its neutral grey is 0.5) | L165-175, blends L179-185 |
| Idea 2 | **shutter-open dwell**: while held, history weight rises (total ≤ 0.84; at default ≈ 0.82). The extra history is read back to scene-referred light with an analytic inverse of the ACES fit (`acesInverse`, L76-84) and EMA-ed there, so the held fixed point equals HEAD's fixed point (no brightness step at press/release; only the time constant changes). Gated by `hist.a > 0.5` (no dwell on an empty C). No new state | L197-205 |
| R1 | pivot glide, rate 13 | L17-29, L109-112, A store L214 |
| R2 | dead `plasmaBuffer[3].z`, `[7].y` → `extraBuffer[5+bin]` (bins 2 and 19) | L31-36, L104-107 |
| R3 | `time·(0.15+mids·0.2)` → `time·0.15 + mids·0.2·sin(time·0.7)` (identical at mids = 0) | L144-146 |
| R4 | C(0,0) masked in `hist` (corner pixel uses its current value; also `histLin`) | L191-195 |

Default look (idle 0.5,0.5, photo, flat depth, 192 px / 30 f; HEAD → new): meanL 0.5789 → 0.5607, stdL 0.1707 → 0.1794 (576 px: 0.5813 → 0.5632, 0.1694 → 0.1782). **Yes, deliberate and visible**: exposure 2 now fades toward the frame edge (porthole), centre unchanged; mean about -3 %.
Identity / identical-to-HEAD proof: with `ex2` forced to 1 and not held, 192 px / 15 f, mids = 0, pixel-diff vs HEAD = exactly the 3 panel copies of pixel (0,0) (the masked corner), for two parameter/cursor sets. So R1-R3 and the rest are HEAD-identical.
Held/dwell checks (192 px, 90 f, press at f31, release f61, 30 fps harness time): meanL idle 0.5582 → held settles 0.570 (HEAD 0.575 → 0.589; same +0.012 step, which is HEAD's `held_bonus`); frame-to-frame step at press +0.0029 (HEAD +0.0128), at release -0.0081 (HEAD -0.0067): no pop introduced. Smear check with Rotation 0.9, Warp 0.7, ripple, held: mean |Δ| between consecutive frames (0..255): HEAD 1.63/1.14, dwell off 1.30/0.87, dwell on 0.58/0.46 (about half). 300-frame held run with audio + Opacity 1.0 at 128 px: meanL 0.623 → 0.634 slowly (content motion), maxRGB 0.796, nan 0. Corner probes: write(0,0) real pixel, dataA(0,0) = (0.5,0.5,7,fract) , (1,0)/(0,1)/(1,1) normal.
Honest limit: at the default rotation speed (0.15 rad/s) the dwell smear is a few pixels, strongest with ripples / Rotation slider / Warp; it is visible as smoother CA fringes and ripple smears, not a dramatic long exposure.
Formula names: cos⁴ vignetting (A), inverse Narkowicz ACES.

## 2. heat-haze-mirage (image)

**Kept verbatim:** 4 params, fbm displacement, gradient bend, TIR fold + `mirrorUV` geometry, caustic runners, horizontal chroma shift, warm tint + glow, held widening, click heat bursts, ACES, semantic alpha, depth relief, A = pre-ACES haze accumulation (HDR, `mix(vec4(col,a), prev, 0.85)`), B diagnostics `(totalDisp, heatFactor, bass)`. Existing title lines kept; banner fields added (`Upgraded: 2026-11-09`, `Ideas:`, `A packing:`).
**A packing:** pre-ACES haze accumulation RGBA (unchanged); texel (0,0) = glide state.

| | what | where |
|---|---|---|
| Idea 1 | **vertical atmospheric dispersion (Cauchy)**: per-channel deflection ∝ (n(λ)-1) = B/λ², so relative to green `(λg/λ)² - 1` = R -0.284, B +0.494 (`cauchyRel`, L45-49); row offset `= cauchyRel · min(|bend|,0.005) · 6` on R/B (blue image up, red down), also on the mirrored fold sample with the sign flipped (3 mirror taps instead of 1) | L164-195 |
| Idea 2 | **scintillation**: highlight texels (luma 0.65..0.95) get gain `1/(1+1.5·div d)`, clamped 0.75..1.3, where `div d` is the divergence of the SAME fbm displacement field (finite differences of `vnoise` at `risingUV`, 2 extra vnoise), scaled by wavy scale, shimmer amplitude and a photosensitivity taper `clamp(8/(riseSpeed·wavyScale),0.4,1)` (rate 3.96 at defaults, taper = 1). Rays focus where the displacement converges. Zero at Heat Intensity 0 | L197-221 |
| Idea 3 | **exposure-integrated shimmer**: `col = mix(col, max(hazeAcc.rgb,0), 0.3·hazeDensity)` before `acesFilm`; `hazeDensity` moved up above it; A keeps HDR `hazeAcc` | L233-240 |
| R1 | heat-source glide, rate 3 (HEAD integrated one 1/60 step from a zeroed state = raw cursor) | L25-36, L104-109, A store L250 |
| R2 | dead `bandBoost` (`plasmaBuffer[1..8]`) → `extraBuffer[5+bin]` for bins {0,1,2,4,7,11,19,32}, direct band→voice order | L38-43, L136-141 |
| R3 | C(0,0) masked in `prev`; plus an empty C (`prev.a ≤ 0.001`, first frame) falls back to the current value so there is no dark ramp-in | L224-231 |

Card deviation (Idea 2): "value noise tied to displacement coordinates" implemented as the divergence of the displacement field's own noise (closest honest physics: scintillation is ray focusing); same coordinates, 2 extra vnoise. Dispersion constants: the card's `(cauchyScale-1)` with A = 1 (deflection ∝ n-1), k = 6 and an `|bend|` cap are my calibration.
Default look (192 px / 30 f; HEAD → new): meanL 0.5483 → 0.5480, stdL 0.1991 → 0.1984 (576: 0.5499 → 0.5500, 0.1969 → 0.1958); maxRGB 0.869 → 0.878. Brightness-neutral; the change is thin vertical colour fringes on horizontal edges in the bend layer (about 1 px at 192, 3 px at 576 at defaults), a ±12 % twinkle on highlights (measured gain range at defaults 0.85..1.20, p1/p99 0.88/1.14; clamps at 0.75/1.3 at extreme sliders), and slight temporal smoothing in dense haze.
Identical-to-HEAD proof: with Idea 1-3 disabled in a scratch copy the PNG is pixel-identical to HEAD (0 differing pixels, two parameter/cursor/ripple sets) → R1-R3 do not change the idle look.
Checks: held + bass fold render, checker and photo; moved cursor (glide probe A(0,0): 0.2116→0.353→0.503→0.668→0.777→0.795 toward 0.8 at 12/16/20/28/45/60 frames, matches rate 3); 240-frame idle and held+audio runs: meanL flat (0.551..0.552 / 0.660..0.667), dataA max 2.0 (HDR), nan 0; mouse -0.1,-0.2 and flat/ramp/none depth, hdr 2.5, all-zero and all-one params: nan 0. Corner probes: write(0,0) a real colour, no 7.0 anywhere in the picture.
Formula names: Cauchy dispersion (F), displacement-field divergence (ray focusing).
Perf (SwiftShader, noisy): 576 px 30.9 → 46.1 ms in the table run, 46.6 → 47.4 ms in an earlier run (2 extra taps, 2 vnoise).

## 3. interactive-zoom-blur (distortion)

**Kept verbatim:** 4 params, Bayer-dithered tap loop `center + dir·(1+t·strength)`, per-channel spreads, depth-occluded taps (Idea 1, occlusion floor + normalisation), radial trail advection (Idea 2), click strength pulses, effectBlend, alpha, depth passthrough. No ACES (card forbids it): `upgraded-rgba` removed from JSON features (it was already untrue).
**A packing:** display RGBA; texel (0,0) = glide state.

| | what | where |
|---|---|---|
| Idea 3 | **whip-pan zoom burst**: `ctr = center + lag·(0.8·t)` per tap (tap = HEAD tap - 0.8·S·t²·lag, a curved quadratic path); `lag = raw - glide`, magnitude clamped 0.25 uv; exactly 0 at rest | L139-144 |
| Idea 4 | **linear-light accumulation**: taps summed as c² (scalar per channel, weights `tapWeight·occl`), normalised by the weighted occlusion sum, `sqrt` per channel before trail/effectBlend | L153-166 |
| R1 | epicentre glide rate 10; lag drives HEAD's `springSpeed` bonus | L18-31, L64-78, A store L189 |
| R2 | dead `fftVoice` (`plasmaBuffer[1..8]`) → `extraBuffer[5+bin]` by ray radius, 8 voices fetched once per pixel (not per tap) | L33-38, L118-124 |
| R3 | C(0,0) masked in `prev` by `prevCoord == (0,0)` (advected coords reach it from pixels beside the corner when the cursor is near the top-left) | L169-176 |

Deviations / choices: (a) HEAD's `min(springSpeed*4, 0.5)` was tuned for a velocity that was always 0 and would saturate at 0.125 uv/s (any drift), so the bonus is `min(springSpeed, 0.5)` (saturates at 0.5 uv/s). (b) The tap weights are now normalised out (`wSum` instead of `occlSum`) so reviving the FFT voices shapes the streak without brightening it (+15 % at full audio in HEAD's formula); at zero audio `wSum == occlSum`.
Gamma-2 look change (deliberate): bright sources (sun core, specular glints, barcode bars) keep their streak brightness along the ray instead of averaging away. Photo with HDR sun/glints (`--hdr 2/3`), strength 0.85, 384 px: meanL 0.4190 → 0.4300, maxRGB 1.9413 → 1.9434; at defaults (192 px, 30 f) meanL 0.4293 → 0.4303, stdL 0.2193 → 0.2195 (576: 0.4322 → 0.4333, 0.2213 → 0.2216), i.e. +0.1 % to +2.6 % mean with strength, highlights visibly streakier, no clipping change.
Identical-to-HEAD proof: with gamma-2 disabled in a scratch copy, pixel diff vs HEAD = 0 for idle, moved+held+depth ramp, and cursor at (0,0) (rest ⇒ lag = 0 ⇒ HEAD's radial streaks; mask is a no-op there since effectBlend ≈ 0 near the cursor).
Cursor jump 0.1,0.9 → 0.9,0.1 in one frame, strength 1.0 (256 px, 40 f): the burst sweeps across with curved streaks for about 0.3 s then settles to HEAD's picture (frame 38 = steady); meanL moves smoothly 0.425 → 0.374 → 0.393 (HEAD jumps straight to 0.389); bounded by the 0.25 clamp. 240-frame run with path + audio + held: meanL 0.40..0.42 (HEAD 0.40..0.42), nan 0, dataA max (except the glide texel) 1.
Timing (SwiftShader, 576 px, Quality 1.0 = 35 taps, strength 0.9, depth ramp, 3 alternating rounds, 14 f): HEAD 400.7 / 423.4 / 471.3 ms, new 421.3 / 400.8 / 439.3 ms → mean 431.8 vs 420.5 (0.97×, within noise; the scalar accumulators offset the extra centre maths). Below the 1.2× budget.
Formula names: gamma-2 linear-light accumulation (no §12.2 row); whip-pan = per-tap ray centre shift by the glide lag.

## Gates (final files)
- `node scripts/verify-naga-wasm.mjs --files` (3 files): 3 valid, 0 invalid.
- `python3 scripts/wgsl_precommit_gate.py --files` (3 files): passed 3/3, extraBuffer violations 0, pasted headers 0 (the `naga` CLI step is skipped, as on this VM).
- `python3 scripts/audit_dead_sliders.py --files double-exposure heat-haze-mirage interactive-zoom-blur`: 0 dead sliders. `audit_extrabuffer.py`: pass (no extraBuffer writes remain in these files; they only read `[5+bin]` guarded by `arrayLength`).
- Renders (HEAD vs new, same params/cursor/audio): 192 px and 576 px idle; moved / held cursor; `--audio 0.5,0.4,0.3`; photo + checker/grid sources; depth ramp / flat / none; ≥60-frame sequences (240-300 for long runs); all `nan 0`, dataA nan 0. Table (192 px, 30 f, defaults, mouse 0.5,0.5): `$S/forkC/out/table.txt`.
- Side effect to know about: running the audit scripts with `--files` overwrote `reports/dead_sliders_audit.*` and `reports/extrabuffer_write_audit.*`; I restored those four from HEAD (`git show HEAD:<file> >`). `reports/wgsl_precommit_report.json` was already modified before I started and every gate run rewrites it; I left it.

## Open items for the coordinator
1. **heat-haze-mirage geometry is vertically inverted in HEAD (not touched: card says do not touch the fold geometry).** `uv.y = 0` is the top row, but `heatBase = smoothstep(1,0,uv.y)`, `pathLen`, the caustic mask and the fold mask `smoothstep(0.58,0,uv.y)` are all strongest at the TOP (the comment says bottom), and `risingUV = uv.y·wavy - time·rise` scrolls DOWN the screen. At default the fold never triggers (`|bend|·48 ≈ 0.09` vs critical 0.55); it only shows with bass + held or high Heat Intensity. A faithful "inferior mirage" fix is `1 - uv.y` in those four places and `+ time·rise`. My Idea 1 acts in screen space (blue up, red down) wherever `bend` is, so it is correct either way.
2. JSON top-level `description` strings (heat-haze "spring-damped heat nozzle [133..137]", double-exposure "spring-damper transform pivot dynamics") are now stale; outside the allowed fields (`features`/`tags`/`x-meta`), so not edited. Features `spring-damper-pointer` (heat-haze) and `spring-cursor` (double-exposure) were kept because the glide is real, though it is first-order, not a spring.
3. double-exposure: HEAD's instant +0.25 rad rotation step and ×1.2 layerMix on press/release are unchanged (they are HEAD's; the dwell makes the press step smoother and the release step is HEAD's snap). Could be eased with the same envelope later if wanted.
4. heat-haze scintillation rate follows the shimmer rate (riseSpeed × wavyScale cycles/s); the taper starts at 8 cycles/s. A real-GPU look at extreme sliders (Heat 1.0, Wave Scale 1.0, bass loud) is still needed.
5. No real-GPU visual QA was done; the PNGs are SwiftShader structural proof only.
