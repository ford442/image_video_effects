# BRIEFS — Fork C (sonnet/batch-25): glass-wall-prismatic (1st pass), gen-depth-refracted-liquid-stained-glass (2nd pass)

Written 2026-11-09 BEFORE any WGSL edit. HEAD renders: scratchpad/forkC/{gw,gd}_head_{192,576}_{idle,held}.png, montages m_gw_head576.png / m_gd_head576.png, source passthrough src_192.png.
Test photo (minirender_img): pastel, mean RGB (0.433, 0.400, 0.392), chroma 0.128; depth is structured (near disc, far disc, ramp) so depth-driven ideas are checkable.

---------------------------------------------------------------------------------------------------
## 1. glass-wall-prismatic  (1st pass)

### HEAD observation
- 192 idle: meanL 0.453 / stdL 0.149 / meanA 0.937; held+audio: 0.460 / 0.140 / 0.953. 576 idle 0.436/0.154/0.901. No NaN.
- **Colour cast (measured):** source mean RGB (0.433, 0.400, 0.392) → HEAD output (0.646, 0.361, 0.351); mean chroma 0.128 → 0.315. Cause: `wavelengthToRGB` weights summed over the four bands are (≈2.5, 1.0, 1.0) in R,G,B and the code normalises by `2.2/Σabs` only. A flat tile interior (zero refraction offset → four identical samples) therefore returns ≈(1.5,0.5,0.5)·s: a red filter, not a glass. The photo's greens vanish.
- Tiles are flat plates with a 12 % bevel: the interior refracts nothing, so at the default look the "prismatic" part is only a faint fringe on bevels / tilted tiles.
- `fresnel` is computed (R0 + (1−R0)(1−cosθ)^4.5) and used ONLY in alpha — no reflection ever reaches the colour although the description promises "Fresnel highlights".
- **Dead/racy pointer state:** thread (0,0) writes extraBuffer[133..138] (smoothed point, velocity, prevDown, click impulse), every other thread reads [133],[134],[138] in the same dispatch. extraBuffer is re-uploaded ZEROED every frame, so in the real app `smoothMouse` is (0,0)/racy and `clickImpulse` is 0/racy; the tile tilt and the click ring are non-deterministic. minirender persists extraBuffer, so it shows the spring "working" (judge nothing from it). Design intent read from the code: when NOT pressed the tilt point orbits a Lissajous (0.5+0.22 sin 0.7t, 0.5+0.22 cos 0.85t); while pressed (and one frame after release) it follows the cursor; press edge fires a decaying impulse (×0.94/frame). Per-frame constants (0.18 / 0.82) ≈ an under-damped spring, ω ≈ 24 rad/s, ζ ≈ 0.24 at 60 fps.
- C is read as colour history (`mix(final, prev, 0.1+mids·0.06)`) BEFORE ACES while C is the previous ACES display value (double tone-map of the ghost).

### Idea Card
```
SHADER: glass-wall-prismatic
IDENTITY: a wall of square glass tiles in front of the photo; each tile is a bevelled plate that refracts the scene through four Cauchy-dispersed bands, tilts toward a pointer lamp, with dark mortar grooves
KEEP VERBATIM: 4 params + roles (grid_size → tile count 6..26, curvature → refraction offset scale, dispersion → Cauchy B (+bass), thickness → absorption); the 4-wavelength loop with refract() and Cauchy IOR; bevel normal profile; tilt toward the (smoothed) lamp with influence 0.85 and mids/hold gain; mortar groove darkening; spec lobe pow 36 on the lamp; transmission/alpha formula; capped click ripple fronts + cursor ring; C history mix; ACES; A = display RGBA; depth passthrough; orbit-unless-pressed pointer behaviour (HEAD's intent).
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): the spectral sum is a 4-tap Cauchy basis; the next-better is the SAME 4 taps with a white-balanced basis (a lens must return the scene colour when nothing refracts). Renormalise per channel, keep fringes.
  tactic 2 (physics one step further): a real glass tile (a) is never perfectly flat — cast tiles carry a slight wedge, so every tile throws its own refraction and spectrum; (b) reflects its surroundings off the bevel facets in proportion to Fresnel; (c) a bright lamp seen on a dispersive surface splits into coloured lobes ("fire"), because the surface normal that satisfies the mirror condition differs per wavelength.
  tactic 3 (promote an intermediate): `fresnel` is computed and thrown away; the per-band `ior` values exist in the loop; `cellID` is the natural seed for a per-tile wedge.
  tactic 6 (history): C is read as display colour history — unchanged, but moved after ACES so the ghost is not tone-mapped twice; C texels (0,0),(1,0) hold the pointer state and are masked.
ADD (3 native ideas):
  1. Cast-glass wedge — per-tile stable random tilt from hash(cellID) added to the bevel normal before the Cauchy loop, so flat tile interiors refract and fringe differently tile to tile ("each tile acts as a prismatic lens", which at HEAD only the bevel and the pointer tilt ever did). Amplitude rides the existing curvature/dispersion sliders through the existing offset pipeline (no new param).
  2. Fresnel–Schlick bevel sheen (§12.2F, new use) — promote the thrown-away `fresnel`: reflect the view vector about the (wedged, tilted) normal, look up a soft-box + sky-gradient environment, add env·F·mortar and take (1−F) from the transmitted light. Bevel facets facing the window glint, and the glint slides as the pointer tilts tiles.
  3. Prismatic lamp — the white lamp lobe `pow(dot(n, L), 36)` is evaluated per colour channel with the facet slope scaled by the relative Cauchy index of that channel (n(λ)−n(540)) / (n(540)−1), so the highlight leaves a red/blue-fringed rim instead of a white blob. Uses the same cauchyIOR/B slider.
FORMULA ADMISSION: Fresnel–Schlick (F) on idea 2 — family match (glass tiles reflect), consumes `fresnel`/`normal`/`viewDir` the file already has, deleting it leaves HEAD's tiles. Idea 1 and 3 are tactic-derived (cellID wedge; per-channel IOR from cauchyIOR) — not table rows. Snell/Cauchy rows are NOT newly used (refract()/cauchyIOR already in HEAD). Deletion test both ways passes: remove any one idea → still the dispersed tile wall; keep only the idea (no tile grid / bevel / Cauchy loop) → not this effect.
FORBID on this file: IQ palette, new ripple/shockwave systems, a second spring, changing grid/bevel/mortar, new params, raymarch/hologram costume.
A PACKING: display RGBA (ACES) in A and writeTexture. Texels (0,0)=(pointer pos.xy, vel.xy), (1,0)=(fract(lastTime), click impulse, prevDown, 0.7371 sentinel) are STATE in A only (writeTexture unaffected); C read masked there. f16: positions ≈5e-4 resolution → rest-snap; fract(time) stored.
```
### RESCUE list
- R1 pointer state: extraBuffer spring/prevDown/impulse (dead + racy) → A-texel state with sentinel (dt-based under-damped spring K=600, c=12 ≈ HEAD per-frame constants; impulse exp(−3.7 dt) ≈ 0.94/frame; orbit-unless-pressed preserved).
- R2 spectral white balance: per-channel basis normalisation (neutral stays neutral at zero offset); thickness slider keeps its role as absorption relative to the default (default look = faithful photo colours). **Default look changes** (measured below in NOTES).
- R3 history in display space (post-ACES) + state-texel mask.

---------------------------------------------------------------------------------------------------
## 2. gen-depth-refracted-liquid-stained-glass  (2nd pass)

### HEAD observation
Healthy: kaleidoscope of the photo wedge, depth-heightfield refraction, per-cell hue tint, thin-film film tint, came + solder + highlights + caustic glow. 192 idle meanL 0.415 / stdL 0.128 / meanA 1.0 (alpha saturates: `max(sourceAlpha, coverage)`, source α=1 — fine, HEAD behaviour), held 0.433/0.122. Mean RGB (0.481,0.353,0.411) vs source (0.433,0.400,0.392) — a purple-ish tint by design. No NaN, ACES input is ≥0 everywhere (no clamp needed), C is read exactly (4–6 % tint ghost). No dead slider found (facet/bevel/drift/chroma all visible). Corners beyond r≈1 show flat radial colour bands (sample_uv clamp) — taste/identity, NOT touched (open item). No spring (pointer = kaleidoscope centre, raw) — fine, no state to rescue.
Existing ideas (all KEPT): leaded-came specular highlight along facet seams; depth-driven caustic focus glow where steep bevels concentrate the refraction; lead came structural lattice; solder joint nodes.

### Idea Card
```
SHADER: gen-depth-refracted-liquid-stained-glass
IDENTITY: the photo folded into a polar stained-glass kaleidoscope; depth-derived normals refract it, each piece takes a stable pigment hue, divided by lead came
KEEP VERBATIM: 4 params + roles (facet_count 3..16, bevel_width = depth sampling radius/refraction/edge width, temporal_drift = fold rotation rate, chromatic_amount = dispersion + tint depth); polar fold; depth-gradient normal refraction; threePointLighting; thinFilmTint; ornamentSample; all four existing ideas; click flex ripples; held gain; C tint ghost; ACES; A = display RGBA; semantic alpha; relief depth output.
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): the "pigment" is a weak multiply `mix(1, tint+0.45, 0.24–0.48)` — the next-better approximation of coloured glass is exponential absorption through a path length.
  tactic 2 (physics one step further): coloured glass is a stained *medium*: thicker = deeper and darker, oblique rays travel further (1/cosθ), the melt is thicker where the sheet is "deeper" (the shader already refracts harder with (1−depth)); hand-rolled antique glass carries streaks/wisps of colour inside a single piece; painted glass carries grisaille trace lines that draw the image contours.
  tactic 3 (promote an intermediate): `normal.z` (slope cosine), `depth_val`, `materialHue`, and `gradient` are computed — path length comes from the first two, wisps modulate the third, grisaille comes from the depth gradient (currently used only for the normal and the relief output).
  tactic 6 (history): C stays the display-space tint ghost (4–6 %), unchanged.
ADD (3 native ideas):
  1. Beer–Lambert pigment absorption (§12.2F): T = exp(−σ·L) with σ = (1 − pigment)·k(chroma) from the piece's own hue, L = (0.30 + 0.70·(1 − depth_val)) / max(normal.z, 0.35) (deeper melt + oblique path), expressed relative to a reference path so the default average brightness stays near HEAD: far / steep glass goes deeper and more saturated, near / flat glass paler.
  2. Antique-glass wisps — domain-warped value noise in the folded photo space (so the wisps mirror with the facets) moves each piece's hue by ±0.06 and its melt thickness by ±25 %, so one piece is no longer a flat colour (streaky/wispy cathedral glass).
  3. Grisaille trace line — dark brown vitreous-paint line where the depth slope (gradient normalised by the sampling radius) is large, i.e. along the photo's own object contours; width rides the existing bevel radius; adds to alpha coverage. Dropped if it reads as muddy on the renders.
FORMULA ADMISSION: Beer–Lambert (F) on idea 1 — family match (coloured glass is an absorbing medium), consumes depth_val/normal.z/materialHue the file already has, deleting it leaves HEAD's weak tint multiply. Ideas 2 and 3 are tactic-derived (no table rows). Deletion tests pass in both directions (kaleidoscope + came + refraction is the effect; the ideas only enrich the glass).
FORBID on this file: new params, replacing the kaleidoscope fold or the came/solder/highlight/caustic ideas, IQ palette, springs, changing the fold sampling (corner clamp bands are left alone), halation/bloom (row budget belongs to A/B).
A PACKING: A/C = final ACES display RGBA (unchanged, no state texels).
```
### RESCUE list
- None required (no dead control, no NaN, no packing lie, no pointer-state bug). Open: corner clamp bands, shared `mix(col, prevTint*0.9…)` pre-ACES history (HEAD, 4–6 %, left).
