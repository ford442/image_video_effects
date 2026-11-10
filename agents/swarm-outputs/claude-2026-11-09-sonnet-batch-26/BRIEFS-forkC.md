# BRIEFS — Fork C (sonnet/batch-26): bubble-lens-coupled (1st), digital-lens-prismatic (1st)

Written 2026-11-09 BEFORE any WGSL edit. HEAD renders (scratch `forkC/`): `bub_head_576_{idle,off,stir_real}.png`, `dlp_head_576_{idle,held,big}.png`, `dlp_head_flat` (flat-grey colour probe), plus the coordinator's 192 px baselines in `base/`. Harness for "real app" emulation: `forkC/mrc.mjs` = `agents/mr.mjs` + `ZEROX=1` (re-zero extraBuffer every frame, which is what the app does), `RIPPLES='[[x,y,tStart],…]'` (real ripple uniforms; stock harness always sends 0), `MPATH2` (polyline cursor path) + `HOLD='[a0,a1]'`. All renders A16=1 (rgba16float A/C).

Shared state scheme (both shaders): A texel (0,0) = cursor spring state, texel (1,0) = `(fract(lastTime), …, 0.7371 sentinel)`; C reads of those two texels are masked; every thread integrates the same dt = clamp(fract(time − st1.x), 0.001, 0.05); f16 rest-snap on the spring. Copied from the batch-25 / batch-24 reference implementations, not invented.

---------------------------------------------------------------------------------------------------
## 1. bubble-lens-coupled

### HEAD observation (576 px, idle centre cursor; `bub_head_576_idle.png`)
The picture is NOT a magnifier. There is a pinwheel singularity at the bubble centre and the whole interior is a set of inverted concentric rings (+ a horizontal rainbow band through the middle, alpha panel shows a bright horizontal bar):
- **Lens law**: `displacement = dir·(1−f²)(mag−1)·R·(1−f)` is proportional to R·direction, not to the distance from the centre. Sample radius r' = R·[f − (1−f)²(1+f)(mag−1)]; at default mag = 2 that is −R at the centre (a point on the opposite side of the ring) and negative (image inverted) for f < ~0.45; the direction `normalize(toMouse)` is arbitrary at f→0 → pinwheel. A continuous magnifier needs r' = dist / Z(f), Z = 1 + (mag−1)(1−f²).
- **Fresnel from a 2-D direction**: `cosTheta = dot(normalize(-toMouse), (0,1))` is the cosine of the polar ANGLE, not of the sphere incidence angle → Fresnel ≡ 1 along the horizontal diameter (rainbow band, alpha bar) and ≈ F0 everywhere else; there is no radial rim at all.
- **Dead cursor stirring in the real app**: the spring sits in extraBuffer[133..138] (re-uploaded zeroed every frame, single writer = thread (0,0) = race) → `mouse` ≈ `rawMouse` for almost every thread → `mouseVel = (rawMouse − mouse)·40 ≈ 0`: moving the bubble never stirs the fluid; only clicks do (and only clicks add `dens`).
- **Integer-truncated advection**: `coord − vec2<i32>(prevVel·3.0)`; |vel| ≤ 0.5 so the back-trace is ≤ 1 texel and is exactly 0 for |vel| < 0.333 → the fluid does not advect below a third of its max speed; it only decays.
- No validity sentinel: a late start / direct switch inherits the previous shader's C as "fluid" (SEEDC=50 → dens clamps to 2 and decays ×0.955/frame: a ~1 s amber wash + warp).
- `normalize(toMouse)` at the exact centre pixel is 0/0 (odd canvas sizes, idle cursor on a pixel centre).
- Smaller: A.z "vorticity" = `vel.x − vel.y` is not a curl and is never read (documented as a legacy diagnostic, left alone — packing stays); the hash sparkle `pow(hash12(uv·300 + time·2),20)·influence·dens·3` is per-pixel + per-frame (strobing; only alive after a click at HEAD — it matters once the wake makes `dens` non-zero, see Idea 2).

### Idea Card
```
SHADER: bubble-lens-coupled
IDENTITY: a magnifying soap-bubble lens that follows the cursor; moving it drags a viscous fluid whose flow dents the bubble wall and swirls the film; clicks burst the fluid
KEEP VERBATIM: 4 params + roles (x Radius, y Magnification, z FilmThickness, w Viscosity — JSON ids x,y,z,w); the fluid solver family (vel.xy + dens advected from exact C, viscosity decay, cursor stir + vortex term, click ripple bursts with exp(-1.5·age), edge damping, clamps); A = raw fluid state (vel.xy, z = legacy vel.x−vel.y diagnostic, dens), C read as that field; ior = 1.3+dens·0.2+mids·0.1 → Schlick F0; amber fluid tint; alpha = film absorption/fresnel/dens (semantic); outside warp vel·dens·0.005; ACES on display; depth passthrough.
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): the film term is a three-cosine fake (`phase = thickness·10·(1−f)`, no angle, no drainage) — the next-better approximation of the SAME operator is the 2-beam film reflectance sin²(2π·n·d·cosθt/λ) at three wavelengths.
  tactic 2 (physics one step further): a real soap film drains (thin at the top, black film before it pops, thick at the bottom), its colour swirls where the flow stirs the thickness (Marangoni), and the colour bands shift with the viewing angle (cosθt from Snell at the film).
  tactic 3 (promote an intermediate): `mouseVel` (the spring lag, 40× lag velocity) already exists and only feeds `vel`; `vel` sampled AT THE WALL is what actually pushes a bubble; HEAD instead scales a fixed 3-lobe sin() by |vel| at the PIXEL — a phase-locked wobble with no relation to the flow.
  tactic 6 (history): C stays the raw field; the new spring state lives in two A texels and is masked out of the field reads.
ADD (3 native ideas):
  1. Drained, angle-aware soap-film interference (§12.2F thin-film phase, extending the existing `phase`/`interference`): thickness d(nm) = FilmThickness·190·(0.45 + 1.1·drain(y)) + 170·dens + treble·40, drain = bottom-heavy; cosθt from the sphere normal and n = 1.33; reflectance sin²(2π n d cosθt/λ) at 650/550/450 nm; the film reflects a soft top-lit environment (+ a small window highlight) and TAKES that energy from the transmitted photo (energy accounting). Visible across the whole body (HEAD's film weight was fresnel·0.55 ≈ 1 % inside).
  2. Stir wake seeds the film — the (rescued) cursor lag velocity also injects density (film thickness) under the bubble, so moving the bubble leaves swirling colour that the flow advects (the "coupled" in the name; HEAD only injected `dens` on clicks).
  3. Flow-dented wall — `deformedRadius` follows the radial component of the C velocity sampled AT the rim point in this pixel's direction (replaces the phase-locked sin(3θ+2t)·|vel| wobble); soft-capped at ±40 % R so the bubble dents instead of folding.
FORMULA ADMISSION: thin-film phase row (F) on this file only (FilmThickness slider already owns it). 2 and 3 are tactic-derived (wake injection, wall sampling). No D-row used (vorticity confinement considered and dropped: invisible through a lens that only samples the field 2 % deep).
FORBID on this file: IQ palette, new params, springs beyond the one cursor spring, ripple stamps beyond the click bursts HEAD has, replacing the solver, holographic/oil-slick costume.
A PACKING: raw fluid state (unchanged); texels (0,0) = (cursor.xy, vel.xy), (1,0) = (fract(lastTime),0,0,SENT) are STATE; field reads of those texels are masked; sentinel invalid → fluid reset to rest.
```
### RESCUE list
- R1 lens law (pinwheel + inverted rings) → continuous magnifier r' = dist/Z(f), Z = 1+(mag−1)(1−f²): magnification `mag` at the centre, 1 at the wall (no seam). Default look change: large and expected.
- R2 2-D "Fresnel" → sphere incidence angle cosθ = sqrt(1−f²) (rim reflectance, no horizontal band).
- R3 dead cursor spring → A-texel spring (ω² = 42, critically damped: HEAD's constants), rest-snap; stirring alive.
- R4 integer advection → bilinear back-trace (4 exact loads).
- R5 inherited / first-frame C → sentinel-gated reset; state texels masked in the field reads.
- R6 centre-pixel `normalize(0)` → `toMouse / max(dist,1e-4)`.
- R7 sparkle: see Idea 2 — if the wake makes it salt noise, retime it to a slow value noise (note in NOTES).

---------------------------------------------------------------------------------------------------
## 2. digital-lens-prismatic

### HEAD observation (576 px; `dlp_head_576_{idle,big}.png`, colour probe `dlp_head_flat`)
A pixelated disc (block lattice, thin dark grid lines, hex dot overlay, faint warm rim ring) follows the cursor; the interior is salmon/pink while the photo is green/teal.
- **Spectral reconstruction is not colour-neutral**: the 6 bands analysed/synthesised with `wavelengthToRGB` weights give out = M·in with M = [[3.21,.36,.15],[.36,.61,.12],[.15,.12,.93]] (computed from the file's own weights and absorption). Red gain 3.2 vs green 0.6: a flat 0.6 grey becomes (0.77,0.64,0.60) vs 0.66 outside; teal (0.4,0.7,0.6) → (0.81,0.62,0.54) = salmon (hue flipped); white → (1.32,0.95,0.83). The green `tint` (0.15,1,0.55) at 35 % only partly hides it.
- Spring: critically damped spring in extraBuffer[133..138] (written by thread (0,0)); dead/racy in the real app → the lens centre is raw / (0,0) / nondeterministic (minirender hides it).
- C ghost: C holds the previous frame's ACES output but is mixed into the PRE-ACES colour (`acesToneMap(mix(color·k, prevC, 0.07))`) → display colour is tone-mapped twice for 7 % and a poisoned C (SEEDC=50) flashes white on frame 1.
- Param names lie: JSON ids/names `lens_strength / chromatic_spread / barrel_distortion / center_glow` but the code (and the JSON `description` fields) say x = pixel block size, y = lens radius, z = grid-line opacity, w = Cauchy B. Saved params must stay byte-exact → NOT renamed; flagged as an open item (NOTES).
- Header lists `depth-aware` (depth is only passed through) → dropped from Features; JSON `features` lacks `upgraded-rgba` (gained once the card is implemented).

### Idea Card
```
SHADER: digital-lens-prismatic
IDENTITY: a cursor-following digital lens — the image inside is block-quantized (pixel grid + hex dots), refracted through a glass dome with 6-band Cauchy dispersion, tinted digital-green, with a warm iridescent rim; held pointer squeezes the lens; clicks flash a pixelated pulse
KEEP VERBATIM: 4 params + roles (x block size, y lens radius, z grid opacity, w Cauchy B) and their (mis)names; block quantization `floor(uv·blocks)`; Cauchy 6-band loop (wavelengths, `cauchyIOR`, `refractThroughSurface`, absorption, spectral saturation, bass/mids/treble modulators); the green `tint` at 0.35; grid lines; hex overlay; rim glow; ripple pulse; held squeeze; alpha = 0.55 + mask·0.35 + ripple + held (semantic); ACES; A = display RGBA with a 7 % C ghost; depth passthrough.
MECHANISM INTERROGATION (§12.1):
  tactic 2 (physics one step further): a real lens has natural illumination falloff (cos⁴), its aperture edge shows lateral chromatic aberration (the red and blue images have different sizes, so the silhouette itself fringes), and internal surface reflections throw ghosts of the bright parts of the scene back through the glass along the optical axis (here the axis is the cursor).
  tactic 3 (promote an intermediate): `ior` per band, `cauchyB`, `dist`, `radius`, `squeeze`, `uv_quantized` are all computed; the ghost and the aperture fringe use them and add no new state.
  tactic 7 (direction): the held squeeze is an anamorphic compression — an anamorphic lens stretches its flare ghosts horizontally.
ADD (3 native ideas):
  1. Natural cos⁴ vignetting (§12.2A) inside the lens: I = 1/(1+(K·dist/radius)²)², K = 0.55 → 59 % at the aperture edge; gives the flat disc a lens-body falloff.
  2. Ghost chain (§12.2F lens-flare ghosts — the batch's single use): two secondary images of the BRIGHT parts of the scene (bright-pass luma 0.62→0.9) sampled at block centres at c + (c − uv_q)·k (k = −0.45 enlarged copy, k = 0.8 inverted copy), tinted by the lens coating colours, windowed to the lens edge, stretched horizontally by `squeeze` (anamorphic).
  3. Dispersive aperture edge — each colour channel's blend radius follows its own refractive index (R smaller, B larger, from the existing `cauchyIOR`), so the lens silhouette carries a rainbow fringe whose width follows the existing CauchyB slider (tactic-derived extension of the file's own dispersion to the aperture; no new §12.2 Cauchy row claimed).
FORMULA ADMISSION: cos⁴ (A row, lens) and lens-flare ghosts (F row, this file only); both consume quantities the file computes. Row budget respected (no Brown–Conrady, no Airy, no Snell).
FORBID on this file: ripple/spring additions beyond what HEAD owns, IQ palette, thin-film, new params, replacing the quantization with hex, neon edge detection.
A PACKING: ACES display RGBA (unchanged; the C ghost is now mixed in display space); texels (0,0) = (cursor.xy, vel.xy), (1,0) = (fract(lastTime),0,0,SENT) are STATE, C reads masked.
```
### RESCUE list
- R1 dead spring → A-texel cursor spring (stiffness 45 / damping 13.416 = HEAD's), rest-snap.
- R2 spectral reconstruction not neutral → multiply the band sum by the inverse of the file's own analysis/synthesis matrix (so a uniform colour round-trips exactly; dispersion fringes remain), keep the absorption as an explicit mild glass tint. Default look change: large (hue flip fixed), measured on the photo and on flat grey.
- R3 C ghost double tone-map / poison → ACES first, mix prevC (clamped 0..1, state texels masked) in display space.
- Open (not fixable without breaking "saved params byte-exact"): the four JSON param names do not describe their roles.

---------------------------------------------------------------------------------------------------
## Revisions after implementation (cards above were written first; these are the measured deviations)
- bubble Idea 2: injection weight 0.012 → 0.05 (first value left dens ≤ 0.21 on 2.7 % of pixels, ablation changed 2.1 % of pixels / 0.02 % >16/255 = invisible).
- bubble Idea 3: sampling the wall velocity alone changed 0.6 % of pixels in a stir (the stir plume radius 0.04–0.18 never reaches the wall) → added the drag-stretch term (drop mode l = 2 from the cursor lag, 0.45·min(lag,0.2)·(2cos²−1)) and the `tanh` soft cap; ablation now 13.8 % / 9.1 %. Film gain raised (`refl` floor 0.10 → 0.14, ×1.6 → ×2.0) after the first render showed the body colour at ≈ pastel grey. Sparkle (R7) made smooth and gated.
- digital lens Idea 1: K 0.55 → 0.45 (69 % at the aperture; 59 % read as a dark ring). Idea 2: ghost scales changed from (−0.45 enlarged, 0.8 inverted) — which only mirrored highlights already inside the lens — to (−1.6 upright ×0.62, 2.0 inverted ×0.5) so highlights ANYWHERE in frame appear as minified ghosts; weight 0.38 → 0.85. R2: tint mix 0.35 → 0.10 + ×1.18 make-up gain (a neutral rebuild plus the unchanged 0.35 tint made a green phosphor). R3: the C ghost is also skipped while the sentinel is invalid.
- Per-pixel cost: bubble was 1.31× HEAD until the rim tap / wall dent / sparkle moved behind `dist < 1.45R` / `influence·dens > 0.002` branches and the bilinear back-trace behind `|trace| > 0.02` (now ≈ 1.10×, output bit-identical to the unbranched version: mean |Δ| 0.002/255).

---------------------------------------------------------------------------------------------------
## Review fix round (bubble-lens-coupled; measurements in NOTES-forkC.md → "Review fix round")
- **Issue 1 (fluid-state cliff → circular colour seam): verified** with the reviewer's repro (click (0.5,0.5) t=2.0, 384 px, row y=192: dens 0.625 → 0.002 in one texel at r≈0.197, global max step 0.789). Cause: the semi-Lagrangian back-trace uses the destination pixel's own velocity, which is exactly 0 outside the click reach / stir radius, so nothing is pulled into those pixels. RESCUE R8 added: one diffusion step per frame (`mix(advected, neighbour mean, 0.3)`, 2-tap checkerboard axis, skipped on invalid C / corner state texels) → row step 0.623 → 0.076, global 0.789 → 0.101; stir-wake max step 0.876 → 0.373. Packing unchanged. Cost: 4-tap measured 1.34× HEAD (over budget) → 2-tap 1.22× (idle) / 1.21× (stir), medians of 6 alternating rounds. A shared-memory halo tile was 10× slower on SwiftShader and was dropped.
- **Issue 2 (axis-aligned glints): verified and replaced.** R7 revised: value-noise glints → round dots on a 28.6°-rotated jittered lattice (radius 0.3 cell, per-cell twinkle), checked at 192 / 384 / 576.
- Idea cards unchanged (Ideas 1/2/3 read the same dens/vel; the fix only changes how the support spreads). Residual: 1–2 texel convergence shocks where opposing flows collide in a violent stir (solver property).
