# NOTES — Fork C (sonnet/batch-26): bubble-lens-coupled, digital-lens-prismatic

All visual evidence is SwiftShader (`agents/mr.mjs` / scratch `forkC/mrc.mjs`, A16=1 = real rgba16float A/C). **No real-GPU visual QA.** Real-app extraBuffer behaviour was emulated with `ZEROX=1` (extraBuffer re-zeroed every frame, which is what the app does); stock minirender keeps it persistent and made HEAD's springs look alive.
Files touched: `public/shaders/bubble-lens-coupled.wgsl`, `public/shaders/digital-lens-prismatic.wgsl`, `shader_definitions/advanced-hybrid/{bubble-lens-coupled,digital-lens-prismatic}.json` (features only), this file + `BRIEFS-forkC.md`. Nothing committed. Running `audit:dead-sliders` / `audit:extrabuffer` / the precommit gate rewrote `reports/*` (coordinator: revert).

---------------------------------------------------------------------------------------------------
## bubble-lens-coupled  (1st pass; 256 lines after the review fix round)

**Kept verbatim:** 4 params + roles (x Radius, y Magnification, z FilmThickness, w Viscosity; JSON ids x/y/z/w untouched); solver family (vel.xy + dens advected from exact C, viscosity decay `mix(0.92,0.99,w)`, cursor stir `(rawMouse−mouse)·40` + vortex term, click ripple bursts `exp(−1.5·age)`, edge damping, clamps ±0.5 / 0..2); ior = 1.3+dens·0.2+mids·0.1 → Schlick F0; amber fluid tint; `highlight`; alpha = film absorption / fresnel / dens (semantic, 0.2..1 inside, 1 outside); outside warp `vel·dens·0.005`; ACES on the display colour; depth passthrough. Cursor spring constants 42 / 12.96 (critically damped) are HEAD's.
**A packing:** raw fluid state, unchanged: `(vel.xy, z = vel.x − vel.y, dens)`. `z` is a legacy "vorticity" diagnostic that was never read (not a curl) — kept as documented, not promoted. NEW: texel (0,0) = `(cursor.xy, cursor vel.xy)`, texel (1,0) = `(fract(lastTime), 0, 0, 0.7371)` are STATE. `fieldAt()` masks both texels out of every field read; an invalid sentinel (first frame, inherited C from another shader, late start) makes every thread read the field as rest. C is read as the field, not as colour.

### Ideas (each findable by its `// ── Idea n` comment)
1. **Drained, angle-aware soap-film interference** — §12.2F *Thin-film phase* (extension of HEAD's three-cosine `phase`/`interference`), `bubble-lens-coupled.wgsl:190`. Thickness d(nm) = FilmThickness·190·(0.45+1.1·drain) + 170·dens + treble·40 (drain = bottom-heavy: top thin, can go black), cosθt from Snell at the film (n 1.33), reflectance `soapFilm()` = sin²(2π n d cosθt / λ) at 650/550/450 nm, reflecting a soft top-lit room + a small window highlight; the reflected light is TAKEN from the transmitted photo (`sample·(1−0.5·refl) + film·room·refl·2`). HEAD's film weight was `fresnel·0.55` ≈ 1 % in the body; now the colour is visible across the whole body and bands shift toward the rim. FilmThickness keeps its role (and still drives alpha absorption).
2. **Stir wake seeds the film** — tactic 3 (promote an intermediate), `:125`. `dens += min(|mouseVel|,3)·influence·0.05`: the cursor lag velocity (which already stirred `vel`) now also thickens the film under the bubble; the flow (now actually advecting, R4) carries it away as a swirling colour wake. HEAD only injected `dens` on clicks. Visible as the arch of swirled colour trailing the cursor.
3. **Flow-dented, drag-stretched wall** — tactic 3 / physics (drop shape mode l = 2), `:156`. Wall radius = R + soft-capped (`tanh`, ±0.4 R) [radial component of the C velocity sampled where the pixel's ray meets the rim ·0.09 + 0.45·min(lag,0.2)·(2cos²−1)]: clicks push the wall out where the burst hits it, dragging the bubble stretches it along the pull toward the cursor and squashes it across (0 at rest). Replaces `|vel|·0.06·sin(3θ+2t)` (a phase-locked wobble keyed to the velocity at the PIXEL, not at the wall).
Formula rows (§12.2): Thin-film phase (F) only. No D-row used (vorticity confinement considered and dropped: the lens only samples the field 2 % deep, it would be invisible). Cauchy/Fresnel/Beer-Lambert rows: none claimed (Fresnel already existed; now fed a real angle).
Ablation, 576 px, stir path (0.3,0.4)→(0.7,0.5)→(0.45,0.7), 90 frames, last frame, changed pixels >4/255 (>16/255): wake 4.3 % (2.4 %), dented/stretched wall 13.8 % (9.1 %) — idle cursor: both 0 (idea 2 and the stretch need motion; the film/Fresnel/lens rescues are what change idle).

### Rescues (HEAD was broken) — default look changes, as expected
- **R1 lens law**: `displacement = dir·(1−f²)(mag−1)·R·(1−f)` is ∝ R·direction, not ∝ distance: sample radius r' = R[f − (1−f)²(1+f)(mag−1)] = −R at the centre for the default mag 2 and negative (inverted image) for f < ≈0.45 → a pinwheel singularity + concentric inverted rings (`bub_head_576_idle.png`). Now a continuous magnifier: sample = mouse + (uv−mouse)/Z, Z = 1+(mag−1)(1−f²): `mag`× at the centre, 1 at the wall (no seam).
- **R2 Fresnel from a 2-D polar angle** (`dot(normalize(−toMouse),(0,1))`): Fresnel ≡ 1 along the horizontal diameter (rainbow band + opaque alpha bar), F0 elsewhere, no rim. Now cosθ = sqrt(1−f²).
- **R3 dead cursor spring** (extraBuffer[133..138], single writer (0,0), re-zeroed every frame → `mouse` ≈ raw → `mouseVel ≈ 0`: cursor stirring dead; only clicks moved the fluid). A-texel spring (rest-snap verified: settles at (0.6974, 0.5975) for target (0.7, 0.6), the half-pixel offset is the centroid measurement).
- **R4 advection truncated to whole texels** (`i32(prevVel·3)`, |v| ≤ 0.5 → exactly 0 below |v| = 0.333): bilinear back-trace (4 exact loads, skipped when the trace is < 0.02 texel). (+ one 2-tap diffusion step, see *Review fix round*.)
- **R5 inherited / first-frame C** read as fluid: sentinel-gated reset. SEEDC=50,50,50,50 over 4 frames: HEAD meanL 0.496 / meanA 0.886 vs clean 0.505 / 0.857 (amber wash + warp); new 0.525 / 0.853 = identical to clean (also with SEEDC 0.5).
- **R6** `normalize(toMouse)` at the exact centre pixel (odd canvas, idle cursor on a pixel centre) → `toMouse / max(dist, 1e-4)`.
- **R7** sparkle `pow(hash12(uv·300 + time·2),20)·influence·dens·3` was per-pixel and per-frame (strobing, resolution-dependent; only alive after a click) and would have become salt noise once the wake makes `dens` non-zero → glints, gated off when `influence·dens` ≈ 0 (first smooth value noise `smoothstep(0.62,0.95,vnoise)`; replaced by round dots in the *Review fix round*, because value-noise maxima sit on lattice points and read as 6–10 px axis-aligned rectangles).

### Default-look change (A16 minirender, 192 px, 24 frames from T0=2; HEAD from `base/*.log`)
| scenario | meanL | stdL | meanA |
|---|---|---|---|
| idle (0.5,0.5), audio 0 — HEAD | 0.505 | 0.174 | 0.857 |
| idle — new | 0.525 | 0.176 | 0.853 |
| held (0.3,0.6), audio .4/.3/.2 — HEAD | 0.497 | 0.181 | 0.867 |
| held — new | 0.524 | 0.163 | 0.863 |
576 px idle: HEAD .505/.174/.856 → .525/.177/.853; 576 held off-centre: .507/.170/.867 → .534/.159/.863. The statistics barely move; the picture does (clean bubble instead of a pinwheel — see `bub_head_576_idle.png` vs `fin_bub_576_idle.png`). Slider extremes 0,0,0,0 / 1,1,1,1 with audio 1: nan 0.
Stability (superseded by *Review fix round*): 900 frames (15 s) of a zig-zag cursor + 5 clicks, `ZEROX=1`: finite, max dens 0.62, mean dens 0.009. T0 = 59.95 (fract(time) wrap): identical stats to a clean start.
Timing (SwiftShader, 512 px, 90 frames, min of 4 alternating HEAD/new, load 4–5): HEAD 41 ms vs new 45 ms ≈ **1.10×** (before hoisting the rim/dent/sparkle work behind branches it was 1.31×) — superseded by the *Review fix round* timing (diffusion added). Machine was shared with the other forks.

### Open items
- Real-GPU look not checked; the film gain (`refl·2.0`, `0.14` floor) and the stir wake gain (0.05) were tuned by eye on SwiftShader against a synthetic photo.
- A.z is still the fake `vel.x−vel.y` (unread).
- The mode-2 stretch caps at ±0.4 R (lag ≥ 0.2 uv); a very fast flick makes a long pill. Arguably right for a bubble; flag if it reads as too much.

---------------------------------------------------------------------------------------------------
## digital-lens-prismatic  (1st pass; 228 lines)

**Kept verbatim:** 4 params + roles — **x block size, y lens radius, z grid-line opacity, w Cauchy B** (the code and the JSON `description`/`mapping` fields agree; the JSON NAMES `Lens Strength / Chromatic Spread / Barrel Distortion / Center Glow` do not describe them, left byte-exact); `floor(uv·blocks)` quantization; the 6-band Cauchy loop (wavelengths 420–680, `cauchyIOR(…,1.5,B)`, `refractThroughSurface`, absorption `exp(−0.8(6−i)0.12)`, `spectralSat`, bass/mids/treble modulators); the green tint hue; grid lines; hex overlay; rim glow; ripple pulse; held squeeze; alpha `0.55+mask·0.35+ripple·0.1+held·0.1` (semantic); ACES; 7 % C ghost; depth passthrough. Spring constants 45 / 13.416 are HEAD's.
**A packing:** ACES display RGBA (unchanged; the 7 % C ghost is now mixed in display space). NEW: texel (0,0) = `(cursor.xy, cursor vel.xy)`, texel (1,0) = `(fract(lastTime), 0, 0, 0.7371)` are STATE; the C read of those texels is masked; the C ghost is skipped while the sentinel is invalid.

### Ideas
1. **Natural cos⁴ vignetting** — §12.2A *cos⁴ vignetting* (lens), `digital-lens-prismatic.wgsl:165`: I = 1/(1+(0.45·r/R)²)² → 69 % at the aperture edge, applied to the lens image only. Ablation (576 idle): 27.7 % of pixels change >4/255, 16.2 % >16/255.
2. **Lens-flare ghost chain** — §12.2F *Lens-flare ghosts* (this file only in the batch), `:185`: two minified secondary images of the BRIGHT parts of the scene (bright-pass luma 0.62→0.90): upright ×0.62 and inverted ×0.5 about the optical axis = the cursor, sampled at block centres (they stay in the lens' pixel grid), coating-tinted (magenta / teal), weighted toward the aperture (`smoothstep(0.1,0.85,r/R)`), stretched horizontally by the held squeeze (anamorphic). Content-dependent: on the synthetic photo (few highlights) 6.9 % of pixels change >4/255, 1.7 % >16/255; a real photo with highlights shows more.
3. **Dispersive aperture edge** — tactic 2 (lateral CA also sizes the aperture), `:112`: each colour channel's blend radius follows its own Cauchy index from the file's existing `cauchyIOR` (R smaller, B larger, green = HEAD's mask exactly), so the silhouette carries a rainbow fringe that widens with the Cauchy-B slider. 11.1 % / 5.0 % of pixels. No new §12.2 Cauchy row is claimed (it extends the file's own dispersion to the aperture); flagged in case the coordinator counts it toward the Cauchy budget.
Formula rows: cos⁴ (A), lens-flare ghosts (F). No Brown–Conrady, Airy, Snell, thin-film.

### Rescues
- **R1 dead spring** (extraBuffer[133..138], thread (0,0) → lens centre raw/(0,0)/racy in the app) → A-texel spring + rest-snap (settles exactly at the target: centroid (0.7000, 0.6000)).
- **R2 spectral rebuild not colour-neutral** — computed from the file's own weights: out = M·in with M = [[3.21,.36,.15],[.36,.61,.12],[.15,.12,.93]] (red gain 3.2×, green 0.6×). Flat 0.6 grey → (0.77, 0.64, 0.60) vs 0.66 outside; teal (0.4,0.7,0.6) → salmon (0.81,0.62,0.54): a hue flip. Fix: multiply the band sum by the exact inverse of that matrix (`SPECTRAL_INV`, constants documented in the file; recompute if wavelengths/absorption change) so a uniform colour round-trips exactly while per-band offsets remain as red/cyan fringes (small negative lobes clamped). Consequences handled: ×1.18 make-up gain (HEAD's roll-off `x/(1+0.28x)` was taming the 3.2× overshoot) and the green `tint` mix 0.35 → **0.10** (same hue; at 0.35 against a neutral rebuild the lens became a green phosphor — HEAD's 0.35 only looked mild because it cancelled the red gain). Measured on the photo (interior r<0.6R, 576 px): reference (lens off, ACES) R/G 1.036, B/G 0.998, luma 0.566; HEAD R/G 1.280, B/G 0.919, luma 0.600; new R/G 0.957, B/G 0.959, luma 0.507 (vignette included).
- **R3 C ghost** was mixed into the PRE-ACES colour (tone-mapped twice) and flashed on an inherited C: `acesToneMap(mix(color·k, prevC, 0.07))` → `mix(acesToneMap(color·k), clamp(prevC,0,1), 0.07·stateOk)`. Frame-1 test with SEEDC=50,50,50,50: HEAD meanL 0.525 vs clean 0.464 (washed, stdL 0.149 vs 0.174); new 0.454 = clean 0.454.

### Default-look change (192 px, 24 frames from T0=2)
| scenario | meanL | stdL | meanA |
|---|---|---|---|
| idle — HEAD | 0.494 | 0.177 | 0.643 |
| idle — new | 0.454 | 0.174 | 0.643 |
| held, audio — HEAD | 0.549 | 0.153 | 0.743 |
| held, audio — new | 0.508 | 0.151 | 0.743 |
576 idle: HEAD .502/.174/.643 → ≈.46/.17/.643. The interior is darker (vignette) but now keeps the photo's colours instead of turning salmon (`dlp_head_576_idle.png` vs `dlp_new_576_idle.png`, `m_dlp_move.png`). Slider extremes 0,0,0,0 / 1,1,1,1 with audio 1 + held: nan 0.
Timing (SwiftShader, 512 px, 90 frames, min of 4, load ≈ 8–9, noisy): HEAD 72 ms vs new 79 ms ≈ **1.10×**.

### Open items
- The four JSON param NAMES do not describe their roles (Lens Strength is the pixel block size, Chromatic Spread the lens radius, Barrel Distortion the grid-line opacity, Center Glow the Cauchy strength). Presets key on ids/defaults so names are cosmetic, but the UI mislabels the sliders; renaming violates "saved params byte-exact" — coordinator/Noah decision.
- Header said `depth-aware` (depth is only passed through): dropped from Features. bubble-lens-coupled's JSON/header `depth-aware` dropped for the same reason.
- Ghosts are content-dependent and only exist where the photo has bright highlights; weight/threshold tuned on a synthetic photo.
- The hex dot overlay (`hexEdge(uv, 18+block)`) is unregistered with the block lattice (moiré at some block sizes) — HEAD behaviour, left.

---------------------------------------------------------------------------------------------------
## Gates (both files)
- `python3 scripts/wgsl_precommit_gate.py --files …`: naga OK, bindgroup compatible, 0 extraBuffer violations, 0 pasted headers (run after the last edit of each file).
- `npm run audit:extrabuffer`: 0 new violations (neither file touches extraBuffer any more). `npm run audit:dead-sliders -- --files bubble-lens-coupled digital-lens-prismatic`: 0 new dead sliders; every `zoom_params` component is consumed and visible (bubble: x radius, y magnification, z thickness+absorption, w viscosity+stir radius; lens: x block, y radius, z grid opacity, w Cauchy B).
- Renders: 192 + 576, idle / held+audio / moving cursor / click / poisoned C (SEEDC 50 and 0.5) / slider extremes / 900-frame stir (bubble) / time wrap / spring settle — all nan 0.
- Harness extensions used: `forkC/mrc.mjs` (= `agents/mr.mjs` + `ZEROX=1`, `RIPPLES`, `MPATH2` polyline path, `HOLD`) — the stock harness always sends `config.y = 0` (no ripples) and never re-zeroes extraBuffer; worth promoting into `agents/` if it recurs.

---------------------------------------------------------------------------------------------------
## Review fix round (unanchored review of bubble-lens-coupled; same files, no git/build/Vitest)

All numbers: SwiftShader, `forkC/mrc.mjs`, A16=1, `ZEROX=1`; A/dens read back through a debug build that writes `(|vel|, dens, vel.x, 1)` to the output. No real-GPU QA.

### 1. Hard-edged fluid disc → circular colour seam — VERIFIED, FIXED
- **Repro** (reviewer's): click (0.5,0.5) at t=2.0, 384 px, 90 frames to t≈3.5, A row y=192. Before: `dens … 0.681 0.653 0.625 | 0.002 0.000` — a one-texel cliff of **0.623** at r≈0.197 (the click reach 0.2), global max 1-texel dens step **0.789**, max dens 1.664. `seamimg_prev.png` shows the crisp inner disc in the film.
- **Cause (confirmed):** the semi-Lagrangian back-trace reads the DESTINATION pixel's own velocity; outside the click reach / stir radius `vel` is exactly 0, so nothing is ever pulled into those pixels, and dens piles up against the support edge instead of spreading. Ideas 1/2 map `170·dens` nm onto film thickness, so a 0.62 step is ≈ half a colour cycle in one texel.
- **Fix:** one diffusion step per frame right after the advection: `advected = mix(advected, nMean, 0.3)` (D ≈ 0.075 texel²/frame). To keep the cost down `nMean` is a **2-tap** mean (checkerboard axis: even pixels average ±x, odd pixels ±y) — measured the same softening as the 4-neighbour mean at half the texture reads. Skipped when the sentinel is invalid (everything reads as rest) and within one texel of the two corner state texels. The raw `(vel.xy, vorticity, dens)` A packing, the sentinel/state texels and the clamps (±0.5 / 0..2) are untouched.
- **After:** same repro row `… 0.001 0.003 0.012 0.046 0.115 0.192 0.249 0.291 0.325 …` — max row step **0.076** (8× smaller; the front is an ≈ 8-texel ramp), global max 1-texel step **0.101**, support (dens > 0.002) 17.9 k → 22.9 k px. `seamimg_new.png`: the disc edge is gone, the film shows smooth swirl bands. 4-tap vs 2-tap: 0.076/0.098 vs 0.076/0.101 (indistinguishable).
- **Stir wake** (violent 5-point zig-zag, held, 384 px, 120 frames): max 1-texel dens step 0.876 → 0.373, steps > 0.2: 159 → 54, > 0.1: 317 → 187 (`wake_cmp.png`, `wake_zoom.png`). **Residual (honest):** where two opposing flows collide (`vx` +0.5 | −0.25 across 2 texels) the unprojected self-advection of the solver still forms a 1–2 texel convergence shock; diffusion at D ≈ 0.075 cannot widen a shock closing at ~2 texels/frame, so a violent zig-zag can still show a small notch in the film (visible in `wake_zoom.png`, far smaller than the old disc). That is the solver's behaviour, not a support-edge artefact.
- **Long run, final shader** (900 frames / 15 s, 384 px, zig-zag + 4–5 clicks):
  | scenario | max \|vx\|,\|vy\| | max dens | mean dens | px dens>0.01 |
  |---|---|---|---|---|
  | stir+clicks stop at t≈8, viscosity slider 0.5, read at t=17 | 0.0000 | 0.0000 | 0 | 0 (decays to exactly 0) |
  | same, viscosity slider 1.0 (0.99/frame, stickiest) | 0.0051 | 0.0215 (≈ 3.7 nm of film) | 0.0076 | 46 k (spread, not stuck) |
  | stir + clicks to the last frame, slider 0.5 | 0.5000 (clamp) | 1.664 | 0.141 | 25 k |
  | stir + clicks to the last frame, slider 1.0 | 0.5000 (clamp) | 2.000 (clamp) | 0.403 | 110 k |
  (`|vel|` printed as 0.707 = both components clamped at 0.5.) Pre-fix busy/slider-1.0: mean dens 0.322, 77 k px — diffusion spreads the support (+25 %) but nothing blows up or latches.
- **Poisoned C** (`SEEDC=50,50,50,50` and `0.5,0.5,0.5,0.5`, 4 frames, 192 px): max |Δ| vs a clean start = **0/255** (HEAD: 234/255). Default-look stats unchanged by the fix: idle .525/.176/.853, held .524/.163/.863 (meanL/stdL/meanA).
- **Frame time vs HEAD** (SwiftShader, 512 px, 60 frames, 6 alternating rounds, machine load 8–18 from the other forks; medians, min-of-6 in brackets): idle HEAD 51.5 ms; before the fix (no diffusion) 57 ms = 1.11× (1.21×); 4-tap diffusion 69 ms = **1.34×** (1.26×) — over budget; **2-tap checkerboard (shipped) 63 ms = 1.22×** (1.23×). Stir + click scenario: HEAD 58.5 / no diffusion 63.5 (1.09×) / 4-tap 76 (1.30×) / 2-tap 71 (**1.21×**). The min-of-6 ratios for the stir case are not usable (a single 38 ms HEAD outlier). An 18×18 workgroup-shared halo tile (1.27 reads/thread + `workgroupBarrier`) was bit-identical but **10× slower on SwiftShader (633 ms vs 60 ms)** — rejected; it might be fine on a real GPU but cannot be shown here.

### 2. Axis-aligned glints — FIXED
- Value-noise maxima sit on lattice points, so `smoothstep(0.62,0.95,vnoise(uv·aspect·90))` read as 6–10 px axis-aligned rectangles/crosses (`wake_zoom.png`, left panel).
- Replaced by `glints()`: one soft round dot per cell of a lattice rotated 28.6°, centre jittered into the 0.3–0.7 interior of the cell, radius 0.3 cell (never clipped by the cell edge → no popping as the domain drifts), per-cell on/off `smoothstep(0.3,0.75,hash)` and a slow per-cell twinkle `0.55+0.45·sin(t·(1.5+2h)+40h)`. Domain scale 60 (cell = 1/60 of the height: 3 / 6 / 10 px at 192 / 384 / 576), gain 1.6 → 2.4 to keep the same visibility. Still gated off when `influence·dens ≤ 0.002`, so idle cost is unchanged. `glf_192.png`, `glf_576.png`, `wake_zoom.png` (right): round dots at every size.

### Gates after the last edit
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/bubble-lens-coupled.wgsl`: naga OK, bindgroup compatible, 0 extraBuffer violations, 0 pasted headers. Header `Ideas:` line updated (diffusion + round glints named in the rescue text). JSON untouched in this round.

### Open after the round
- Convergence shocks in violent stirring remain (see above); fixing them needs a pressure projection or a conservative flux scheme — out of scope for a 1st-pass upgrade.
- Real-GPU look and cost unchecked; the 2-tap choice was made on SwiftShader texture-read cost.
