# NOTES — fork B (kaleido-scope-grokcf1, liquid-chrome-ripple, molten-glass)

HEAD = 8577b989 (copies in the batch scratchpad `head/`). All three are second-pass files: earlier ideas kept, new ones numbered **Idea 3 / Idea 4** in the WGSL (each file already had Idea 1/2), appended to the existing `Ideas:` line. Evidence: SwiftShader via `agents/mr.mjs` with `SRC=img`; ripple injection through a scratch copy `scratchpad/forkB/mr_rip.mjs` (never edited `agents/mr.mjs`). Scratch/PNGs/RAWs: `/tmp/claude-0/-root-image-video-effects/22d46372-8ddf-4eab-b7b0-82c649a0b58c/scratchpad/forkB/`.

> **REVIEW ROUND (2026-11-15, after the independent review) supersedes the first-round tuning and numbers below wherever they differ — see the section at the end. Changed: molten INCAND_GAIN 2.2→0.5 + cracks gated by heat; kaleido bounce capped at 4 + field stop starts at 0.75; liquid-chrome CAP_AMP 0.35→0.25 + wider/dimmer environment bands.**

**Method.** Every idea sits behind a single scratch-only switch (const or expression replaced by `scratchpad/forkB/variant.py`). Final files carry no switches. Checks: (a) idea-off build vs new → % pixels with max-channel |Δ| > 0.02; (b) **regression: all ideas off ≡ HEAD, bit-exact (0.00 % pixels, max Δ 0) for all three files**, idle and held, so refactors changed nothing by themselves.

JSON: **no change** to any of the three definitions (features already truthful: kaleido `upgraded-rgba` is now true because ACES is in the WGSL; descriptions left alone to avoid search-index churn; molten's pre-existing `fast-motion` tag left as found). Saved params byte-exact (untouched). No `plasmaBuffer[1..]`, no extraBuffer use, no new state.

---

## 1. kaleido-scope-grokcf1 (`public/shaders/kaleido-scope-grokcf1.wgsl`)

KEEP VERBATIM held: yes — fold/spin, inner counter-rotating wedge, seamBeat, prism/reflect, grout/conveyor/packets, A-texel (0,0) state (`stateOut`, spring, env — code untouched), trail decay 0.88, 4 params. A packing: display RGBA + state texel (unchanged); ACES only on the new-this-frame emissive term, never re-applied through C.

| | what | where | visible at default sliders (% px > 0.02 / mean |Δ|) |
|---|---|---|---|
| Idea 3 | mirror-bounce attenuation + cool cast: half-wedge index → reflections `min(j, 2n−j)` **capped at 4**, `exp(log((0.92,0.945,0.96))·min(bounces,4))` on the photo base (native, energy accounting) | L79–90, applied ~L125–131 | *(final, 576 idle default)* 78.3 % / .045; at segments=1: 92.0 % / .080. First-round (uncapped) was 75–76 % |
| Idea 4 | eyepiece barrel `r' = r(1+0.14 r²)` on the object-sample radius only (overlays stay on `radius`) + soft field stop `1−0.45·smoothstep(0.75,1,frameR)` (frame-centred, **now corners only**) — §12.2B Brown–Conrady | L104–110, ~L125–131 | *(final, 576 idle default)* barrel 41.8 % · stop 8.7 % (corners; was 35 %). At segments=1: barrel 17.4 %, stop 8.5 % |
| Rescue 1 | iris ring was `distance(uv, rp.xy)` (uv units → elliptical on wide frames) → aspect-corrected | L143 | **confirmed by code only**: the harness frame is square and `config.y`=0, so no render proof |
| Rescue 2 | HEAD tagged `upgraded-rgba` with **no ACES** (grep = 0 at HEAD) → `acesToneMap(max(emissive,0))` on the added overlay terms only | L154–157 | 36.5 % of pixels at 576 default (40.9 % at segments=1) — deliberate default-look change |

- Idea 3 deviation from card: none. Idea 4: card said "on the radial coordinate of the object sample" — done exactly so (not on the screen coordinate, so seams stay straight and the pointer stays on the kaleido centre).
- Default look (first round, superseded): 192 idle meanL/stdL 0.409/0.101 → 0.370/0.108 (≈ −10 %). **Final (576 idle, saved defaults): 0.412 → 0.391 (−5.1 %); segments=1: 0.417 → 0.365 (−12.5 %).**
- Spring/state: 60-frame held run with `A16=1`: kaleido centre settles at the same pixel as HEAD (looked at both PNGs); `nan` 0 on f32 and A16.
- Sliders (min/max each, 192): segments 0/1, rotation 0/1, zoom 0/1, offset 0→1 all change 98–100 % of pixels vs default, `nan` 0. Audio (0.8/0.5/0.9) nan 0.
- A note on rotation: when Rotation ≠ 0.5 the unattenuated (0-bounce) wedge rotates with `spin` — by design (the object wedge rotates with the mirrors) but worth an eyeball.
- Cost (interleaved ×6, 256 px, held; load-noisy — HEAD alone varied 51–70 ms): median new/HEAD **1.06**, min ratio 0.88.

## 2. liquid-chrome-ripple (`public/shaders/liquid-chrome-ripple.wgsl`)

KEEP VERBATIM held: yes — waveHeight composition, click loop, normal/refraction/dispersion, Schlick, key/fill specs, caustic + thinFilm, crest/trough, advected history, 4 params, A = HDR display history, ACES on writeTexture only. Refactor: `sheet` computed once and reused (was computed twice) — bit-identical (see regression).

| | what | where | visible at default sliders |
|---|---|---|---|
| Idea 3 | capillary dispersion (§12.2D deep-water dispersion): 2nd ring at 2× wavenumber, ω×2.828 (ω∝k^1.5), amplitude **0.25** (was 0.35), envelope = swell² (also on click rings, with analytic slope) | L26–30 (pointer ring, **works at idle**), L87–92 (click) | *(final, 576)* idle 41.7 % / .030 · held 41.0 % / .029 (first round at 0.35: 55 % / 54 %). Click case (first round, 0.35) (ripple at (0.7,0.3), cursor parked far, t_end−t_click=1.0 s, 192): 8.9 % of the r=0.3 disc around the click (29.7 % frame-wide incl. the pointer ring) — click contribution is modest |
| Idea 4 | studio-horizon environment: reflection vector → ground / horizon band / sky + one soft box, tinted by the existing thinFilm, weight `metalness·0.6`, mixed over HEAD's environment (native: what chrome mirrors) | L129–140 | *(final, 576)* idle 98.7 % / .092 · held 96.9 % / .084. **At metal=0 it vanishes exactly** (idea-3-off build ≡ HEAD, 0.00 %) |

- First version of Idea 4 washed the photo out (meanL 0.613 → 0.691) — retuned darker (sky 0.15/0.21/0.31, weight 0.6) → meanL/stdL idle 0.613/0.084 → 0.630/0.089; held 0.623/0.102 → 0.633/0.102. Still a mild cream shift at default metal 0.8; eyeball on a real GPU.
- Cost trim: capillary envelope reuses `swell` (no second `exp` per tap). Median new/HEAD **1.04** (min ratio 0.96); before the trim a quiet pair measured 1.29.
- Sliders 0/1 for flow, distort, metal, freq: all change 82–100 % of pixels, `nan` 0. 60-frame held run and audio run nan 0. No rescues on the card; none needed.

## 3. molten-glass (`public/shaders/molten-glass.wgsl`)

KEEP VERBATIM held: yes — whole heat solver (advect / decay / mouse inject / click fronts / convectionPacket), refraction, Fresnel + thickness + Beer–Lambert, gloss, crust + drip, 4 params, A = raw heat in A.r. ACES only on writeTexture. Ideas are **pointer-local**; heat region = pixels with heat > 0.03 (measured with a mask build that writes `heat` to the output).

| | what | where | % of heat region > 0.02 (heat region = % of frame; frame-wide %) |
|---|---|---|---|
| Idea 3 | incandescence (§12.2F blackbody): red→orange→yellow-white ramp from `heat`, `smoothstep(0.3,1)^1.5 × (0.55+bass·0.2) × 0.5` (gain was 2.2) added before ACES | L148–154 | *(first round, gain 2.2; final numbers in the review section)* idle 192 (held-boost 0.35): 43.3 % (3.8 %; 1.6 %) · held 192: 73.4 % (5.3 %; 3.9 %) · held60 192: 55.9 % (8.4 %; 4.7 %) · held 576: 77.1 % (3.2 %; 2.5 %) · held60 576: 65.8 % (4.6 %; 3.1 %). Bass 0.8 changes 93 % of the heat region |
| Idea 4 | cooling craquelure (native): Voronoi-edge cracks (13 cells/frame height), dark core + warm rim, inside `crackZone = max(crust·3, cooled skirt heat∈[0.03,0.6]) × smoothstep(0,0.05,heat)`; static in screen space (no strobing); computed only where the zone > 0.02 | L156–179 | held 192: 18.3 % (frame 1.0 %) · held60 192: 26.3 % (frame 2.3 %) · held 576: 9.7 % (frame 0.3 %) · held60 576: 16.1 % (frame 0.8 %) |

- **Deviation from card (Idea 4):** card said cracks "inside `crust`". At the default cooling rate HEAD's `crust` peaks ≈ 0.15 (`smoothstep(0,0.12, Δheat)·(1−heat)` with Δheat ≈ cooling 0.03), so cracks gated by it alone were invisible. I gate on `max(crust·3, cooled-skirt band)`. First cut (22 cells, thin) measured 5–11 % of the heat region → enlarged cells (13) and widened the profile.
- Idea 4 is thin by nature (lines): frame-wide 0.3–2.3 %, rises with run length as the cooled tail grows. Coordinator may want to judge it on a real GPU.
- Default look (192): idle meanL/stdL 0.491/0.173 → 0.494/0.175; held 0.490/0.174 → 0.499/0.181; held60 0.489/0.174 → 0.498/0.181. Core glows cream-white (ACES shoulder), outer band orange.
- Sliders: all four change the picture (pointer-local: refraction 0→.5 only 1.3 % of the frame, same locality as HEAD). `nan` 0 incl. cooling=0 / radius=1 60-frame extreme.
- Cost: median new/HEAD **1.12**, min ratio 1.29 (the shader is tiny; harness time is mostly overhead; HEAD alone 21–42 ms).

---

## Gates (all three)
`wgsl_precommit_gate.py --files …` 3/3 pass (extraBuffer violations 0, pasted headers 0); `verify-naga-wasm.mjs --files …` 3 valid / 0 invalid; `audit:dead-sliders -- --files …` new dead 0; `audit:extrabuffer` PASS (2 pre-existing baseline entries, not these files). Those audits regenerate `reports/*` — coordinator discards (I did not touch them by hand).

## Open items / not verified
- No real-GPU look; SwiftShader + synthetic photo only. Timings are load-noisy (other forks were rendering); the coordinator re-times alone.
- Kaleido default is ~10 % darker/cooler and the overlays are ACES-lifted; liquid-chrome default is slightly creamier. Both deliberate, both worth one real-GPU look.
- Kaleido Rescue 1 (aspect ring) and the liquid-chrome click-ring contribution are verified by code/low-visibility render only.
- Kaleido `dt = 0.016` fixed spring step left as is (no free A channel for a timestamp).
- Row budget: Brown–Conrady (kaleido), deep-water dispersion (liquid-chrome), blackbody (molten) — one file each; bounce attenuation, studio environment, craquelure are native.

---

## REVIEW ROUND — reviewer findings reproduced at 576 px, saved defaults (2026-11-15)

Everything-off ≡ HEAD re-verified after the changes: **0.00 % pixels differ** — kaleido (576, default and segments=1), liquid-chrome (576, idle and held), molten (576, reviewer path). Gates re-run: precommit 3/3, naga-wasm 3 valid, dead sliders 0 new, extraBuffer PASS (baseline entries only).

| # | finding | reproduced? | change | result (576, saved defaults) |
|---|---|---|---|---|
| 1 | molten incandescence flattens hot plateau | **yes**: reviewer path `MPATH 0.25,0.35→0.6,0.6` held, P=0.5,0.5,0.5,0.2, 60 frames. heat>0.95: HEAD mean 0.667 / std 0.062, NEW 0.878 / 0.013 | `INCAND_GAIN` 2.2 → **0.5** (swept 0.5/0.8/1.1; ramp unchanged) | heat>0.95 mean 0.752 / std 0.039 (HEAD 0.667 / 0.062). Idea 3 vs idea-off: **49.9 % of the heat region** (7.2 % of frame), 3.6 % of frame. Bass 0.8: plateau 0.771 / 0.039 (HEAD 0.667 / 0.071) — not re-flattened. Frame meanL/stdL HEAD 0.491/0.175 → 0.493/0.177 |
| 2 | kaleido bounce 2× the card (half-wedge index) | **yes**: default HEAD 0.412 → 0.372 (−9.7 %; bounce alone −7.5 %); segments=1 HEAD 0.417 → 0.329 (−21 %; bounce alone −18 %). (Reviewer saw −14 % / −29 % on their photo.) The code counts mirrors every half-wedge (up to n), the card said wedge index `min(k, n−k)` (up to n/2) | bounces **capped at 4** (kept bases 0.92/0.945/0.96 so the cast stays visible: far side ≈ (0.72, 0.80, 0.85)); field stop `smoothstep(0.55→0.75, 1)` so it is corners only | default **0.412 → 0.391 (−5.1 %)**; segments=1 0.417 → 0.365 (−12.5 %). Idea 3 changes 78.3 % of pixels (92 % at segments=1); barrel 41.8 %; stop 8.7 % (corners). Grid of 18 cap/base/stop combos run at 192 to pick it |
| 3 | molten cracks drawn on bare photo (`crust·3` ≠ 0 at heat 0) | **partly**: with the reviewer path only 4 px at heat==0 were > 0.02 vs HEAD (max Δ 0.118) and 205 px at 0<heat<0.05 (max 0.152) — real but small here | crack zone × `smoothstep(0, 0.05, heat)` | heat==0: **0 px** differ from HEAD; 0<heat<0.05: 71 px (max 0.119). Idea 4 vs idea-off: 27.3 % of the heat region (2.0 % of frame) |
| 4 | liquid-chrome shimmer higher than HEAD | **yes**: consecutive frames 16 ms apart, held, 576: HEAD mean Δ 0.0207 / 1.69 % px > 0.1; NEW 0.0267 / 3.93 % (reviewer: 0.023 vs 0.0295). Split: idea 4 alone 0.0249 / 2.61 %, idea 3 adds the rest | `CAP_AMP` 0.35 → **0.25** (reviewer's suggestion → 0.0251 / 3.06 %, not enough) **and** wider environment bands (horizon variance 0.012 → 0.03, soft box 0.018 → 0.04) and dimmer (0.55 → 0.42, 0.65 → 0.5) | **0.0221 / 2.01 %** (HEAD 0.0207 / 1.69 %). Capillary idea at idle still 41.7 % of pixels (held 41.0 %); idea 4 98.7 % / 96.9 %. meanL/stdL idle HEAD 0.614/0.084 → 0.636/0.084; held 0.624/0.102 → 0.639/0.099 |

Not reproduced: nothing outright; finding 3 reproduced only at a handful of pixels in my harness (the reviewer's render may have a longer-cooled tail).

Interleaved timing after the changes (6 HEAD/new pairs per shader, 256 px, held cursor, load-noisy): see the line appended below by the timing run.

**Interleaved timing, final code (6 HEAD/new pairs per shader, 256 px, held cursor, load-noisy; HEAD alone varies up to 2.5×):** kaleido median new/HEAD **1.05** (min ratio 1.12) · liquid-chrome median **1.13** (min 1.24) · molten-glass median **1.17** (min 1.10). All under the 1.3× cap; the coordinator re-times alone.
