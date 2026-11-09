# sonnet/batch-27 — fork B notes (cyber-magnifier, multi-fractal-compositor-lens, interactive-fisheye)

Files touched: `public/shaders/{cyber-magnifier,multi-fractal-compositor-lens,interactive-fisheye}.wgsl`,
`shader_definitions/interactive-mouse/cyber-magnifier.json` (features only), `shader_definitions/advanced-hybrid/multi-fractal-compositor-lens.json`
(features + one false `chunks_used` entry), this file. `interactive-fisheye.json` unchanged (every feature/tag is still true; params byte-exact in all three).
No git add/commit, no generate_shader_lists, no npm/build/Vitest. Running `wgsl_precommit_gate.py` rewrites `reports/wgsl_precommit_report.json` (already dirty before I started; not mine to keep).

All pictures below are **SwiftShader structural proof only** (harness, no real GPU). No claim of visual QA on a real GPU.

## Harness used
Stock harness (`.../scratchpad/harness/render.mjs`) holds mouse/params constant and stores A as rgba32float. For the glide, the fisheye sim and the zoom-wrap
series I used a patched copy, `.../scratchpad/forkB/render2.mjs` (same engine emulation + `--path` mouse keyframes `frac,x,y,down;...`, `--dt` per-frame time step,
`--f16 1` = dataTextureA/B/C as **rgba16float** like the real default tiers, `--trace N` per-N-frame min/max/NaN of A.h/A.v, `--snaps f1,f2` extra PNGs, `--fdiff 1`
frame-to-frame mean |Δ|). `r.sh` = `node render2.mjs`. Tables below are `meanL / stdL` of the clamped output (the PNG), NaN count 0 in every run listed.

---------------------------------------------------------------------------------------------------------------------------------

## 1. cyber-magnifier (interactive-mouse)

**Kept verbatim:** all of HEAD — params, A(0,0) glide state with marker 7 and its `*0.16` per-frame step (untouched), texel snap + grid, Sobel trace, rangefinder arc, border,
click flares + magnification pulse, hue-preserving clamp, vignette, alpha, A = (inLens, border, sweep, alpha) masks. No ACES added (card forbids it).

**A packing:** unchanged — masks, texel (0,0) = (glide.xy, 7, 1).

**Ideas (numbered 4 and 5 in the file: 1–3 are HEAD's earlier passes):**
- Idea 4 — **Brown–Conrady radial loupe distortion** (§12.2B) `cyber-magnifier.wgsl:91-105`. `r = dist/radius`, `s = 1 + k1 r² + k2 r⁴`, `k1 = −0.10(mag−1)`, `k2 = −0.03(mag−1)`
  (both negative: barrel roll-off, monotone so no fold-over), applied as `(uv−m)/(mag·s)+m` so gUV, Sobel taps, texel grid and CA all follow. Identity at mag 1 (verified: byte-identical
  PNG vs HEAD at magnification slider 0, flat depth), clamp `s ≥ 0.4`, faded by `inLens` (outside the lens maps exactly as HEAD).
  Default (mag 2.5): rim magnification 2.5 → ~2.0 (s(1)=0.805).
  **Deviation from the card:** the distortion is also faded out with `pixAmt` (`1 − smoothstep(0.1, 0.5, pixAmt)`, gone by ~2.9×). Left on, the digital-zoom regime (KEEP VERBATIM: texel snap + grid)
  turned into a patchwork of 2–4 px blocks and moiré; glass distortion belongs to the optical regime, a pixel zoom is exact. `pixAmt` itself is hoisted (line 99), its formula unchanged.
- Idea 5 — **autofocus defocus keyed to the rangefinder** `:133-153`. `centreDepth` (moved up from the rangefinder, line 137, same value the arc reads) is the focal plane;
  `coc = clamp((|depth(gUV) − centreDepth| − 0.015)·8, 0, 1)·(1 − pixAmt)·inLens`; lens colour blends to a 5-point (centre + 4-tap cross) blur by CoC, tap radius ≤ 1.8 % of frame height on screen.
  Flat depth ⇒ CoC 0 (inert, byte-identical); a pixel-view loupe is never defocused. `depthG` is reused for the depth write (line ~200).

**Rescues:** none needed (glide already real; `plasmaBuffer[0].xyz` only).
**Default-look change:** yes, inside the lens only (rim rolls off; defocus only on non-flat depth). Harness meanL/stdL HEAD → new (192, default params 0.5,0.4,0.5,0.3, 12 frames):

| scene | HEAD | new |
|---|---|---|
| idle, flat depth | 0.4074 / 0.2428 | 0.4083 / 0.2431 |
| idle, ramp depth | 0.4074 / 0.2428 | 0.4081 / 0.2430 |
| idle 576, ramp | 0.4091 / 0.2421 | 0.4102 / 0.2426 |
| held (0.3,0.62) + audio 0.5,0.4,0.3, ramp | 0.3783 / 0.1921 | 0.3800 / 0.1954 |
| magnification slider 1 (pixel view), ramp | 0.4211 / 0.2438 | 0.4211 / 0.2438 (identical) |
| click pulse (ripple age 0.1), ramp | 0.4089 / 0.2425 | 0.4096 / 0.2426 |

**Formulae:** Brown–Conrady two-term radial; thin-lens circle of confusion (|Δdepth| form).
**JSON:** dropped `upgraded-rgba` (header + JSON): there is no ACES on this display RGB and the card forbids adding one; features now mouse-driven, audio-reactive, depth-aware.
**Gates:** Naga (wasm) valid; precommit gate pass (bindgroup, workgroup, extraBuffer 0, pasted header 0); dead-slider audit PASS (all four sliders consumed).
**Renders:** 192 + 576, flat + ramp depth, idle / held cursor + audio / click pulse / mag 0, 0.5, 0.6, 0.75, 1 sweep (hand-off glass → digital zoom looked clean at 0.6–0.75).
Command e.g. `r.sh public/shaders/cyber-magnifier.wgsl out.png --params 0.5,0.4,0.5,0.3 --size 576 --frames 6 --tEnd 0.5 --depth ramp` (HEAD: `.../scratchpad/head/cyber-magnifier.wgsl`).
**Open:** the defocus is subtle on the harness' linear depth ramp (depth is read at the magnified position, so a ramp spans only ~1/mag of the lens); real depth maps will vary faster. Constants (0.015 dead-band, ×8, 1.8 %) are SwiftShader-eyeballed.

---------------------------------------------------------------------------------------------------------------------------------

## 3. multi-fractal-compositor-lens (advanced-hybrid)

**Kept verbatim:** 4 params + mixes; point-lens form (`mass·d/(d²+ε)·0.01`); ripple masses; 4-layer tunnel (layerZoom fract, held spin, flow noise, pingPong); depth-weighted composite;
CA mix 0.7; ring/core colours; C persistence 0.08; ACES on display RGB; alpha formula; `zoom_center` = raw cursor.
**A packing:** ACES display RGBA (as HEAD) in every texel except (0,0) = (glide.x, glide.y, 7, fract(time)); C(0,0) masked in the persistence read (`:236-238`).

**Ideas:**
- Idea 1 — **Einstein arcs from the point-lens magnification** `:128-140, 178-187, 199-224`. `xE = θE²/|θ|²` with `θE² = lensMass·0.01` (the file's own constant), `μ = 1/|1−xE²|` clamped 1..3,
  `μt = 1/(1−xE)` clamped ≤ 6. Brightness `× (1 + (μ−1)·g)` and a 3-tap TANGENTIAL smear (offset `θE·|μt|·0.06`, taken before the layer zoom so the on-screen extent is layer-independent; also applied to the two CA taps
  because they carry 70 % of R/B) blended by `arcMask = smoothstep(1.5, 3.5, |μt|)`. **Deviation from the card:** the brightness excess is attenuated, `g = 0.25 + 0.5·ring_glow` (peak ×2.0 at the default slider, ×1.5 at 0, ×2.5 at 1)
  instead of the literal ×3: the literal ×3 on a pale photo whites out the whole band under ACES, and with ring_glow = 0 a hard white ring still remained. Ring Glow already owns "how strong the Einstein ring reads", so it modulates the arcs.
- Idea 2 — **foreground bypass** `:120-126`: `bentUV = uv + (bentUV − uv)·(1 − smoothstep(0.55, 0.8, depth(uv)))`, applied to the cursor lens and the ripple masses. Flat/zero depth ⇒ factor 1 (inert, verified: flat and ramp renders agree except where depth > 0.55).

**Rescues:**
- R1 glide, LENS mouse only (`:45-60, 88-90, 236-247`): first-order glide replacing a dead critically-damped spring (HEAD's `extraBuffer[133..138]` is re-uploaded zeroed every frame ⇒ the init flag read 0 ⇒ every pixel used the raw cursor).
  rate 10 (HEAD stiffness 42). At rest: no change. Moving: lens lags ~0.1 s (checked with a cursor path, A(0,0) probe = (0.75, 0.5, 7, fract(t))). `glideStep` uses the coordinator's `st.w <= 1.0` fix.
- R2 aspect-correct deflection + ring on the real critical curve (`:32-43, 98-103, 226-229`). `gravitationalBend` now takes `aspect` (identical at aspect 1); ring radius `θE = sqrt(lensMass·0.01)` in aspect-corrected distance.
  **Default-look number correction:** the card says 0.203 → 0.166; the actual default (`lens_mass` 0.3 → lensMass 1.85) goes **0.1666 → 0.1360** (HEAD `sqrt(m·0.015)` vs `sqrt(m·0.01)`, ring 22 % too wide in HEAD). The 0.001 softening ε is not folded in (moves the exact critical curve to sqrt(θE²−ε), −2.7 % at default, −11 % at the minimum mass; the ring band is 0.06 wide so it is invisible).
- R3 zoom-phase pop (`:149-156, 190`): layer weight × `max(sin²(π·phase), 0.02)`. Time series t = 2.0 … 4.5 s (dt 0.02, 128 px, default params, `--fdiff 1`): frame-to-frame mean |Δ| at the layer wraps
  (t = 2.24 / 2.36 / 3.08 / 4.00 / 4.46): HEAD **0.0237 / 0.0094 / 0.0141 / 0.0411 / 0.0271** (median 0.0022) → new **0.0015 / 0.0015 / 0.0017 / 0.0030 / 0.0090** (median 0.0020). Residual bump at 4.46 is ~4× median (HEAD 12×); a floor of 0.005 would cut it to 0.0066 but the card says 0.02, kept.
- C(0,0) masked in `prevC`.

**Default-look change:** yes — ring ~18 % smaller and crisper, brighter arc band, layer fades; picture still the same effect (checked at 192/576 and 384×216/576×324; ring is a circle on 16:9). meanL / stdL HEAD → new (default params 0.3,0.5,0.5,0; 20 frames):

| scene | HEAD | new |
|---|---|---|
| 192 idle, flat | 0.6442 / 0.1156 | 0.6492 / 0.1194 |
| 192 idle, ramp | 0.6443 / 0.1155 | 0.6476 / 0.1178 |
| 576 idle, flat | 0.6445 / 0.1141 | 0.6493 / 0.1184 |
| 576 idle, ramp | 0.6445 / 0.1141 | 0.6475 / 0.1171 |
| 384×216 flat | 0.6401 / 0.1128 | 0.6397 / 0.1144 |
| 576×324 ramp | 0.6401 / 0.1124 | 0.6388 / 0.1132 |
| mass .5, ring .7, chroma .4, held (0.3,0.6), audio 0.5,0.4,0.3 | 0.5888 / 0.1679 | 0.5940 / 0.1759 |
| click ripples (2) at t≈2.2 | 0.6308 / 0.1185 | 0.6438 / 0.1373 |
| lens_mass 1, ring 1 | 0.6643 / 0.1300 | 0.6846 / 0.1362 |

**Formulae:** point-lens (Schwarzschild) magnification μ, tangential stretch μt, Einstein radius θE (the file's own physics; no §12.2 row used).
**JSON:** removed the false `mandelbrot`, `julia` features and the false `palette (...)` `chunks_used` entry; `upgraded-rgba` kept (ACES on display RGB, card implemented), `audio-reactive` (bass → mass, mids → ring, treble → CA).
**Gates:** Naga valid; precommit gate pass (extraBuffer violations 0 now that the dead spring is gone); dead-slider audit PASS.
**Renders:** 192 + 576 + two non-square, flat + ramp, idle / held + audio / ripples / mass 0 and 1, checker source (smear visible as soft tangential edges around the ring), cursor path (glide), zoom-wrap time series.
Command e.g. `r.sh public/shaders/multi-fractal-compositor-lens.wgsl o.png --params 0.3,0.5,0.5,0 --size 128 --frames 126 --t0 2.0 --dt 0.02 --fdiff 1`.
**Open:** (a) HEAD's CA taps sample the UNLENSED photo (`uv ± chroma`), so 70 % of R and B bypasses the lens and the "gravitational lens" is visible mostly through G; KEEP VERBATIM says CA mix 0.7, so I did not change the tap position (that would be a big look change) — worth its own pass. (b) The tangential smear is subtle on the photo source, clear on the checker source. (c) Brightening attenuation (above) is a card deviation.

---------------------------------------------------------------------------------------------------------------------------------

## 9. interactive-fisheye — "Fluid Lens Dynamics" (interactive-mouse)

**Kept verbatim:** 4 params and roles; `droplet_shape` + stretch; per-pixel spring to `target_h + capillary`; refraction from the sim gradient (80 % sim) and the 1-texel 5-point Laplacian caustics (both earlier ideas, same numbers);
click splash displacement; 1.06 / 0.94 chroma split; spec / Fresnel / slick colouring; ACES on `writeTexture` only; depth relief; semantic alpha = source alpha.
**A packing:** RAW sim `[h, v, nx, ny]` (unchanged); texel (0,0) = cursor-lag tracker `(glide.x, glide.y, 7, fract(time))` and every sim read of C goes through `simLoad()` (`:42-47`) which masks (0,0) to h = v = 0 (self, 4 neighbours, 8 wave-stencil taps).

**Ideas:**
- Idea 3 — **neighbour-coupled capillary waves: damped wave equation + isotropic 9-point Laplacian** (§12.2D) `:49-101, 156-186`. `accel += (κ/dt²)·lap9`, `v` clamped ±12, stencil weights 0.2 / 0.05 / −1 (×10/3), 8 exact C loads, borders clamped.
  Three honest deviations from the card, all forced by measurements (SwiftShader, rgba16float A):
  1. **The Laplacian is taken of the deviation `h − rest`, not of `h`.** `rest = max(target_h + capillary, 0)` (what the spring already pulls toward; `rest_height()` re-evaluates the analytic droplet at the stencil texels). Laplacian of `h` smooths the droplet's razor-sharp `sqrt` edge into a wide meniscus: A's lens radius grew ~0.28 → 0.45 (+60 %) and the picture became a different effect (wide dark meniscus ring, comet-tail refraction everywhere). With the deviation the equilibrium droplet is exactly HEAD's and only transients (overshoot after a move, rings launched by the capillary forcing, splashes) propagate and ring down.
  2. **Stencil spacing = 1.5 % of frame height (`wb` texels), plus a soft dead-band `LAP_CORE`.** On rgba16float, h rounds to ~5e-4…1e-3 and a 1-texel Laplacian of anything smooth (droplet ~2e-4/texel² at 576 px) is below that floor: the 1-texel force made the droplet sparkle (steady frame-to-frame |Δ| 0.0079 at 192 and 0.0233 at 576 vs HEAD+R2 0.0016 / 0.0017). With `wb` spacing the flicker is 0.0022 / 0.0026 f16 and 0.0015 f32 (HEAD+R2 0.0016 / 0.0017).
  3. **c² is scaled by `spring_k/6.86`** (capillary: c² ∝ surface tension / mass; 1.0 at the defaults, 0 at Surface Tension 0 so "no tension ⇒ no droplet" still holds exactly as HEAD, ≤ 2× in the stiffest corner).
  **κ chosen:** `κ = min((WAVE_SPEED·dt/(wb·px))²·gain, 0.25)` with `WAVE_SPEED` = 0.03 screen heights/s ⇒ κ ≈ 1e-3 at the defaults (independent of resolution), hard cap 0.25 (CFL 9-pt: κ ≤ ~0.75; forced test on f16 with WAVE_SPEED 5: stable at κ = 0.25 / 0.5 / 0.75, v pinned at the ±12 clamp (unstable) at 1.1 ⇒ ≥ 3× margin). Not higher than 0.03 because the painted capillary forcing runs at ω = 6, k = 48 and the dispersion ω² = ω0² + c²k² resonates with it (c = 0.08 gave ±0.3 centre rings, ~3× HEAD's).
  Caustics keep HEAD's 1-texel 5-point `lap` (so Idea 2 is unchanged).
- Idea 4 — **Snell refraction** (§12.2F) `:234-250`. η = 1/1.33, `bend = cos_t − η cos_i`, lateral run `bend/(η + bend cos_i)`, depth = `h·0.12/(1−η)` so a weak slope displaces exactly HEAD's `0.12·h·normal.xy` (calibration), non-linear at the steep meniscus (up to ~3.5× per unit normal.xy). Length-capped to `SNELL_CAP·h` = 0.16·h (HEAD's own max is 0.12·h; an earlier cap of 0.25·h made the rim tear too hard). `sqrt` guarded; **air → water has η < 1 so total internal reflection cannot occur** — the clamp is a numeric guard only. Direction kept as HEAD (displacement along +normal.xy, i.e. a minifying/fisheye rim); a physically-signed convex-drop refraction would magnify instead — kept HEAD's sign so the effect stays "interactive-fisheye".

**Rescues:**
- R1 (lag only) `:24-47, 137-142, 277-282`: first-order glide of the raw cursor in A(0,0) (rate 8; `st.w <= 1.0` fix applied), droplet stays at the RAW cursor, `pointer_vel = (raw − glide)·rate` replaces the click-pair velocity (`ripples[rc−1/−2]`); `has_ptr` guard for mouse < 0. Mid-drag renders show the droplet elongated along the drag, round at rest (HEAD: never stretched without ≥ 2 clicks). A(0,0) probe after a drag: (0.7998, 0.5, 7, 0.784).
- R2 (coordinator) `:263-267`: `spec *= smoothstep(0.02, 0.25, new_h)`. Fresnel already ∝ new_h (no leak). Background is now the plain photo + ACES.

**Default-look change:** **yes, deliberate (R2: HEAD washed the whole frame +0.6 / +1.4 held with white)** plus subtle waves/Snell. meanL / stdL (default params 0.5,0.35,0.45,0.35, A = rgba16float, 120 frames dt 0.016):

| scene | HEAD | HEAD + R2 only | new |
|---|---|---|---|
| 192 idle | 0.7412 / 0.1210 | 0.5056 / 0.2094 | 0.5000 / 0.2073 |
| 192 idle, f32 A | 0.7479 / 0.1147 | 0.5123 / 0.2134 | 0.5050 / 0.2104 |
| 192 held | 0.8535 / 0.1069 | 0.5068 / 0.2119 | 0.5015 / 0.2099 |
| 192 cursor (0.3,0.6) | 0.6998 / 0.1448 | 0.5229 / 0.1996 | 0.5229 / 0.1991 |
| 192 audio 0.5,0.4,0.3 | 0.7253 / 0.1362 | 0.5144 / 0.2128 | 0.5106 / 0.2112 |
| 192 ramp depth | 0.7012 / 0.1538 | 0.5067 / 0.2117 | 0.4988 / 0.2094 |
| 576 idle | 0.7406 / 0.1216 | 0.5052 / 0.2063 | 0.5014 / 0.2053 |

⇒ waves + Snell move meanL by −0.005…−0.008 and stdL by −0.002 relative to HEAD+R2 (the picture is HEAD's droplet + faint outward rings + a slightly harder rim); R2 alone is the big change.

**Stability (≥ 300 frames, rgba16float A, every run NaN-free, h ∈ [0, 2], v within HEAD's range):** 400 frames each at 192, params (ST, visc, mass) at all 8 cube corners {0,1}³ × {idle, moving + held + 3 click ripples + bass 1}; plus 576 (ST 1 / visc 0 / mass 0 moving; default idle; ST 0 / visc 1 / mass 1), 1080 (ST 1 / visc 0 / mass 0 moving). Worst case ST 1, visc 0, mass 0, moving: h ∈ [0, 2.00], v ∈ [−10.7, 9.2] (HEAD same scenario: [−10.4, 8.5]; the h = 2 is HEAD's own clamp). ST = 0 corners: h ≡ 0 (as HEAD). 600-frame default idle at κ 0.25/0.5/0.75 forced: stable.
**Gates:** Naga valid; precommit gate pass; dead-slider audit PASS (all four sliders still consumed); `audit_extrabuffer.py` PASS (no extraBuffer use).
**Renders (192 + 576, f16 + f32, idle / held / cursor / audio / ramp / grid source / drag path / 300-frame extremes).** Key commands:
```
r.sh public/shaders/interactive-fisheye.wgsl o.png --params 0.5,0.35,0.45,0.35 --size 192 --frames 120 --dt 0.016 --f16 1 --mouse 0.5,0.5,0 --data-png A.png
r.sh public/shaders/interactive-fisheye.wgsl o.png --params 1,0,0,0.35 --size 192 --frames 400 --dt 0.016 --f16 1 --trace 50 --audio 1,0.6,0.6 \
   --path "0,0.2,0.3,0;0.2,0.8,0.7,1;0.4,0.2,0.7,1;0.6,0.8,0.3,0;0.8,0.5,0.5,1;1,0.5,0.5,1" --ripples "0.3,0.3,2.5;0.7,0.7,3.5;0.5,0.5,4.5"
r.sh public/shaders/interactive-fisheye.wgsl o.png --params 0.5,0.35,0.45,0.35 --size 192 --frames 300 --dt 0.016 --f16 1 --path "0,0.2,0.5,0;0.3,0.2,0.5,0;0.6,0.8,0.5,0;1,0.8,0.5,0" --snaps 120,135,150,300 --probe "0,0"
```
**Open items / things I am unsure about:**
- **HEAD's own f16 problem, not fixed:** with A = rgba16float the refraction gradient (1-texel central difference of h, ÷ 2 px) and the 1-texel caustic Laplacian are noise-dominated (HEAD at 576 f16 shows terraces/sparkle inside the droplet; clean at f32). I added nothing to it and left `grad` / `lap` exactly as HEAD; a wide-baseline gradient + wide-stencil `lap` (same `wb` machinery) would fix it. Needs a real-GPU look to decide.
- Waves are subtle by design (c = 0.03): rings are visible at the droplet edge, around a held droplet and after a drag, not a strong splash. Constants `WAVE_SPEED`, `LAP_CORE`, `WAVE_STENCIL`, `SNELL_CAP` are SwiftShader-eyeballed.
- Snell sign (see above) and cap are judgement calls.
- Texel (0,0) as the lag tracker costs the pixel's own sim state: its display pixel is computed with h = v = 0 history (one pixel in a corner).
