# BRIEFS — fork E (gen-neuro-kinetic-liquid-gold-lotus, kimi-nebula-depth)

Written BEFORE any edit to either WGSL. HEAD = origin/main 0761b6b9. Scratch dir: `/tmp/claude-0/-root-image-video-effects/914950b4-f44b-4d87-a537-edda39759ec7/scratchpad/forkE/` (harness copy `mrE.mjs` zeroes `extraBuffer` every frame like the engine, injects ripples via `RIPPLES`, reports `perfMin` with `PERF=1`; `cmpraw.py` diffs two `RAW=` dumps).

## HEAD render table (SwiftShader, SRC=img, 20 frames, tEnd 1.5, bass/mid/treb 0)

| file | size | sliders | mouse | meanL | stdL | meanA | notes |
|---|---|---|---|---|---|---|---|
| lotus HEAD | 192 | 1,0.5,0.8,0.5 | .5,.5,0 | 0.046 | 0.088 | 0.116 | **lump in the top-left 30 % of the frame, half cropped; no petals; reads as a gold pine-cone** |
| lotus diag A (camera aimed only) | 192 | same | same | 0.042 | 0.082 | 0.116 | centred now, still a pine-cone: **no petals exist in the SDF** |
| lotus diag B (camera + petal repetition fixed) | 192 | same | same | 0.068 | 0.118 | 0.162 | eight radial gold blades round the floret core — reads as a lotus |
| kimi HEAD | 192 | .5,.5,.5,.5 | .5,.5,0 | 0.340 | 0.198 | 0.400 | halftone works; outline missing on one diagonal family (see below) |
| kimi HEAD | 576 | same | same | 0.377 | 0.196 | 0.342 | same |
| kimi HEAD | 576 | same | .2,.3,1 + audio .8,.5,.9 | 0.382 | 0.193 | 0.342 | audio/held barely moves it |

Looked at the PNGs (Read tool) for lotus HEAD / A / B and kimi 576 idle.

---

## SHADER: gen-neuro-kinetic-liquid-gold-lotus

IDENTITY (one sentence): a liquid-gold lotus — eight gold petals round a phyllotaxis stamen core, torque waves twisting the petals, cyan/magenta plasma runners, a pointer gravity well bending the rays, click blossom shocks, a rotating bounded-history trail.

KEEP VERBATIM: the four saved params and roles (x Bloom Radius → `bloom` lift of the petal bowl, y Plasma Intensity, z Gold Smoothness → spec exponent + trail decay, w Mouse Influence); `opSmoothUnion(core, petals, 0.4)` with the fbm liquid perturbation on both; the `sin(r·7 − 11t)·torque` traveling twist; conductor Fresnel F0 (1,0.71,0.29); Vogel phyllotaxis florets; capillary rivulets; KH shear-roll packets; plasma runners + cyan↔magenta mix; pointer/ripple gravity-well ray bend (ripple.w never read); click blossom shocks; ACES → A, `max(ACES, torque-advected exact-C × decay)` history; semantic alpha; hit depth. The plasma audio wiring (`plasmaBuffer[0].xyz`).

### §12.1 mechanism interrogation
- **Tactic 1 (deepen the kernel):** the shading is Blinn-Phong spec × tinted Fresnel over a flat `base_gold·(diff·0.5+0.2)`. The next-better approximation of "polished gold" is a reflection term: a conductor's colour IS what it mirrors, tinted by F(θ). HEAD mirrors nothing (the background is a flat 0.02/0.02/0.05).
- **Tactic 2 (physics one step further):** a bright conductor with concave neighbours shows **inter-reflection** — light that has bounced twice off gold carries F0² (deeper, more saturated orange). That is the first-order side effect that every gold-ring photograph shows between facing petals.
- **Tactic 3 (promote an intermediate):** `n`, `v`, `fresnel`, `gold_smooth` and `map()` are already computed → a short reflected march along `reflect(−v,n)` uses only existing quantities. The surface radial tangent (`p.xz` direction) is already used by the rivulets/runners (`atan2(p.z,p.x)`) → it is also the vein direction for an anisotropic highlight.
- **Tactic 6 (history):** unchanged — exact C is already used (kept).
- **Tactic 7 (direction):** petals have radial veins; a metal surface drawn out along the veins (liquid gold running down a blade) shows a highlight stretched *across* the flow (Kajiya–Kay), not a round Blinn dot.

### HEAD defects (confirmed by render + read) — rescues (do NOT count toward 2–4 ideas)
1. **R1 camera framing (confirmed).** `ro=(0,2,−5)`, `rd=normalize(uv,1)` looks horizontally along +z; the lotus is 22° *below* the axis, and uv.y is screen-down while rd.y is world-up, so the picture is upside-down and the lotus sits cropped in the top 30 % of the frame. Fix: look-at toward the origin, `−camUp·uv.y`.
2. **R2 petal domain repetition (confirmed).** `sdLotusPetals` rotates `p` (untwisted) by `+a_mod` instead of `−a_mod` (maps sector centre to angle 2·a_mod, not 0), keeps the torque-twisted point only for picking the sector id (so the torque wave never bends petals), and never offsets the petal sphere radially (`p_w.z` stays 0). Result: eight "petals" collapse into ≤0.6-radius blobs round the axis, a pine-cone. Fix: rotate the twisted `q` by `−a_mod`, offset the blade radially, make each petal an ellipsoid blade (the HEAD `abs(x)−c` twin lobe is kept as a narrow split); bowl lift and fbm liquid kept. The rivulet / KH / runner terms (which assume blades) finally have blades to run on.
3. **R3 plasma overlay extrapolates (read, reproduce at plasma_int 2 + bass).** `mix(col, plasma·2, plasma_factor)` with `plasma_factor ≤ 2.5` → channels go negative → the catalog ACES maps negatives to bright (ACES(−0.18)≈0.68) → R channel flares to 1 where cyan plasma should be. Fix: weight `clamp(plasma_factor,0,1)`; clamp `col ≥ 0` before ACES.
4. **R4 negative-pointer sentinel** (cheap guard, mirrors kimi's): `u.zoom_config.yz < 0` would rotate the camera by ±3 rad. Guard to 0.5.
5. Not a defect but must be told truthfully: the `extraBuffer[133..138]` "persistent spring" is re-zeroed by the engine each frame, so `springPos == raw pointer`, `nextHeldGravity == mouseDown` (the written values are the same as the read ones, so the unsynchronised read-after-write is harmless). Left as is; no `spring` feature claimed. JSON param ids (rotationSpeed/complexity/bloomIntensity/gravityWellStrength) do not match the roles in the WGSL (names/mapping do) — byte-exact, untouched, reported.

### ADD (2 native ideas)
1. **Mirror-gold reflection with petal inter-reflection** — a 8-step reflected march along `reflect(−v,n)` through the existing `map()`: if it strikes another petal the reflected colour is that gold's lit colour × F0² (double-bounce, more saturated); if it escapes it reads a tiny studio env (dark warm floor, warm horizon, a key softbox in the existing light direction `l`, a cool fill echoing the background). All × the existing spectral `fresnel`. `gold_smooth` blends sharp ↔ smeared env (rough gold = blurred softbox). Why on this effect: polished gold reflecting nothing is the reason it reads as "yellow plastic".
2. **Anisotropic vein highlight (Kajiya–Kay)** — the spec lobe is stretched along the petal radial tangent `t = normalize(radial − n·(radial·n))`: `spec_aniso = pow(sqrt(1 − (t·h)²), exp)`; replaces nothing, adds a second streaked lobe weighted by the existing `fresnel` and `gold_smooth`. Why: it is the same direction the rivulets already run; liquid gold drawn down a blade streaks across the flow.

FORBID on this file: new springs, ripple fronts beyond the existing shocks, IQ palettes, scanlines, a water plane / second creature, any new param, re-adding phyllotaxis/rivulets/KH, step-AO (bismuth owns it), curvature (neuro-lattice owns it), Beer–Lambert (sonoluminescent), Cauchy (dyson), Airy (pulsar).
A PACKING: ACES display RGBA (unchanged — A = C feedback colour, alpha semantic coverage). No new ACES→C→ACES: the new terms live inside `col` before the existing single ACES.
Rows: native (Fresnel family, "mirror / inter-reflection"; Kajiya–Kay is the anisotropy row of tactic 7). No §12.2 row shared with another fork.

---

## SHADER: kimi-nebula-depth (file kimi_nebula_depth.wgsl)

IDENTITY (one sentence): a photo turned into a halftone print — posterized colour, luma-sized dots on a rotated screen, Sobel ink outlines, paper grain, bass-pulsed dot pitch, a vignette; not a nebula, not a raymarch.

KEEP VERBATIM: the four params and roles (x dot pitch 2–22 px, y edge threshold, z posterize levels 2–12, w ink density); the Sobel 3×3 loop's taps and weights (the "fragile naga-transpiled core"); the rosette rotation 0.26 + `misreg` click misregister; luma-driven dot radius `(1−luma)·0.7`; posterize `floor(c·levels)/levels`; bass dot pulse; mids/treble paper lift; wet-ink bleed from exact C alpha; ACES on display; A = ACES display RGBA with alpha = ink coverage; depth = ink coverage as at HEAD. No new spring, no ripples beyond the existing misregister.

### §12.1 mechanism interrogation
- **Tactic 1:** dot radius is a linear function of luma. A real plate is not linear: the printed dot is larger than the film dot (dot gain, Murray–Davies/Yule–Nielsen), peaking in the midtones, and a plate cannot hold dots below a minimum size.
- **Tactic 2:** what else does a print do? The colour plate and the black plate are never in perfect register — fringe halos at colour edges.
- **Tactic 3:** `gx`/`gy` (Sobel) are computed and then summed into a scalar; the paper `hash12_` is computed and then used as a scalar; both are "intermediates thrown away".
- **Tactic 6:** history C.a already used for wet-ink bleed (kept).

### HEAD defects (confirmed by read, partly by render) — rescues
1. **R1 Sobel magnitude cancels on one diagonal family (confirmed by read + render).** `edge = length(gx + gy)`: `gx`, `gy` are broadcast scalars, so `edge = √3·|gx+gy|`; for an edge with `gx = −gy` (the "\" diagonals) the response is exactly **0** and for "/" it is 1.41× too strong. The synthetic discs lose their outline on opposite arcs. Fix the *combination line only* (the loop/taps/weights stay): `edge = √3·hypot(gx,gy)` — axis-aligned edges give the identical value as HEAD, diagonals become isotropic.
2. **R2 paper "grain" is not spatial (confirmed by read).** `hash12_(uv·time·0.001 + 100)`: the hash input varies by ≤ 0.001·t across the whole frame, so the grain is one slow global brightness value, not grain. Fix: a per-pixel static paper tooth `hash12_(pixel)` — paper is static; keeps the 0.95–1.0 ink-alpha / 0.97–1.0 colour amplitudes.
3. **R3 vignette "spring" cannot persist** — `extraBuffer[133..138]` is re-zeroed by the engine every frame; the writer is thread (0,0) and every other thread reads the same cells in the same dispatch (an unsynchronised read-after-write that can make the vignette centre differ per workgroup tile). HEAD behaviour is the raw pointer. Fix: stateless `vigCenter = pointer (0.5 when the −1 sentinel)`, no extraBuffer traffic; the persistent-state header block is removed (truthfully).
4. **R4 pasted bindings** — the file pastes the 13 bindings + `struct Uniforms` instead of `#include "_prelude.wgsl"` (prelude_migration.json lists `kimi_nebula_depth: eligible`). `python3 scripts/migrate_to_prelude.py --files …` first (infrastructure; not an upgrade).
5. **R5 dot AA is cut by the binary gate** — `isDot` (dist < radius) gates the dot colour work, so the soft `dotMask` rim outside the radius never shows. Folded into Idea 1 (the dot is now drawn from `dotMask` only).
6. JSON `features` lists `volumetric` and `3d` (provably false — the header says no raymarch/nebula), and omits `audio-reactive` / `upgraded-rgba` that are true. Corrected; reported.

### ADD (3 native ideas)
1. **Dot gain + minimum printable dot** (tone curve of the plate) — area coverage `c = π·r²` is lifted by `g·4c(1−c)` (peaks at 50 % coverage, zero at paper/solid), the gain `g` rides the existing Ink Density slider (heavier ink spreads more); dots whose gained coverage is below ~3 % drop out (highlight plate can't hold them). Why: this is the actual non-linearity of every halftone; slider roles kept.
2. **Off-register colour plate** — the posterized colour plate is sampled at `uv + regOffset` (along the rosette axis, ≈ 0.12 cell, scaled by the dot pitch) while the black dot/outline plate stays on the true uv, so colour edges fringe against the ink exactly as a mis-registered print does. The existing click `misreg` stays and adds to it. Why: it is the signature artifact of a physical plate print.
3. **Ink pooling in the paper tooth** — with R2's real tooth, ink fills the valleys: the dot threshold is `dotRadius·(0.85 + 0.3·tooth)` so dot rims and outlines break up organically, more at low Ink Density. Why: the only reason to have paper grain is that ink sits in it.

FORBID: raymarch/nebula, springs, ripples beyond misregister, IQ palette, CMYK colour separation (would replace the look), structure-tensor screen steering (this file's reserved row was `structure-tensor orientation / halftone-screen` — not taken: discontinuous cells), glitch/scanline costume.
A PACKING: ACES display RGBA; alpha = ink coverage (unchanged).
Rows: dot gain (native to halftone — not a §12.2 row), registration (native), tooth (native). No shared row with the lotus.
