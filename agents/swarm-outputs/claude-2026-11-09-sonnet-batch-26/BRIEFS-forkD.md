# BRIEFS — Fork D (sonnet/batch-26): fractal-glass-distort-bilateral (1st pass), alpha-multi-layer-glass (2nd pass)

Written 2026-11-09 BEFORE any WGSL edit. HEAD renders (A16=1, T0=2, SRC=img): scratchpad/base/<id>_head_{a,b}.png (192) and scratchpad/forkD/<id>_head_{192,576}_{a,b}.png. a = idle cursor 0.5,0.5 audio 0; b = cursor 0.3,0.6 held, audio 0.4,0.3,0.2.
HEAD stats (192, idle / held): fractal-glass meanL/stdL/meanA .510/.164/.739 · .498/.176/.890 ; alpha-multi-layer-glass .428/.159/.826 · .434/.160/.833.
HEAD liveness sweeps (192, 3 frames, mean|Δ| vs default, scratchpad/forkD/sweep): see "HEAD facts" per shader.

---------------------------------------------------------------------------------------------------
## 1. fractal-glass-distort-bilateral (1st pass)

### HEAD facts (measured / read)
- **Bilateral stage is dead in the picture.** Only `filtered.g` survives: R and B are re-sampled raw at ±aberration (`color = (rawR, filtered.g, rawB)`), and the spatial sigma is 0.1–1.0 *pixels* (0.55 px at the default → effectively a delta kernel; radius 2 → 25 wasted taps, up to 49 at mix=1). Measured with the chromatic split removed: mix 0 vs 1 → mean|Δ| = 0.0004 (G only). The 0.0186 "bilateral_mix effect" the slider shows is entirely the flat ±0.03·mix horizontal R/B split (±1.5 % of the frame at default).
- **Spring is dead/racy**: thread (0,0) writes extraBuffer[133..138], all others read it, buffer is re-uploaded zeroed every frame → pivot is raw cursor / (0,0) / nondeterministic in the real app (minirender hides it). `held*0.2` is added to every layer angle as a hard pop on click.
- **Audio phase teleport**: `time*(1.0 + mids*0.5)` / `time*(1.0 + treble*0.5)` inside the sine phases → pattern jumps by time·Δaudio·0.5 (at t=100 s, Δmids 0.3 = 15 rad).
- Ghost: `mix(color, prevC, 0.07)` then ACES, but C is the previous frame's ACES **display** output → domain mismatch (and unclamped, so an inherited C = 50 puts 3.5 into the sum for one frame).
- `rotation_speed` is a per-layer twist ANGLE (x·π·0.3·(i+1)), not a speed — still the largest mover (rot0 vs default mean|Δ| 0.098). Left as is (a JSON rename would touch `params`; flagged in NOTES).
- scale 0.034/0.036, refract 0.050/0.050: live. Depth only passes through (sampled at uv, although the colour comes from the warped uv).
- Cost: HEAD 576 px idle ≈ 170–230 ms/frame under SwiftShader (25–49 bilateral taps).

### Idea Card
```
SHADER: fractal-glass-distort-bilateral
IDENTITY: the photo seen through a recursive stack of rotated/scaled rippling glass pivoting on the cursor, softened by an edge-preserving "dream" bilateral filter with a chromatic split
KEEP VERBATIM: 4 params + roles (rotation_speed → per-layer twist angle; scale → recursion scale 0.9–1.3; refract_strength → ripple amplitude ×(1+0.3·bass); bilateral_mix → bilateral amount + flat horizontal R/B split 0.03·mix + sharp window at the cursor); the 4-layer rotate/scale/sine recursion around the cursor; click-ripple pre-warp; sigma/mouse-window shape (sigma 0.1→1.0 × 0.2 near the cursor); semantic alpha (0.4 + |disp|·8 + held·0.15); depth passthrough; ACES; A = display RGBA; 7 % C ghost.
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): RGB-range bilateral → JOINT bilateral: the file already samples the depth map (passthrough only); a neighbour at a different depth must not bleed through the glass even when its colour matches. Prerequisite (rescue): the filter must actually reach all three channels and have a footprint.
  tactic 2 (physics one step further): rippling glass has fold curves where the ray map x→x+d(x) degenerates (det J → 0): light concentrates into bright caustic filaments and thins out where the map stretches; and glass disperses along the BEND (n(λ)=A+B/λ², blue bends more than red), not along a fixed screen axis.
  tactic 3 (promote an intermediate): `total_disp` is computed and used only for the UV and the alpha — its Jacobian (two forward differences of the same recursion) is the caustic density; the depth sample is taken anyway.
  tactic 6 (history): C stays the 7 % display-space ghost (fixed domain); the A texels (0,0),(1,0) carry the pivot spring and an eased click envelope.
ADD (3 native ideas):
  1. Fold caustics — focus = clamp(1/|det(I+∇d)|) from finite differences of the existing recursion; transmitted light brightens along fold curves and dims where the glass stretches (gain 1+k(focus−1), energy-redistributing, no new colour). Rides refract_strength (more bend → more folds).
  2. Cauchy dispersion along the bend (§12.2F Cauchy dispersion) — R/G/B are sampled at p + total_disp·n(λ)/n(550nm) (B calibrated so blue bends ≈1.2×, red ≈0.89× of green); the HEAD flat ±x split is kept on top, so the fringe now also follows every ripple crest.
  3. Joint depth-range bilateral — range weight = RGB range × depth range (σd 0.12); tap radius follows the sigma (0–2 instead of the 2–3 wasted rings); tap spacing is resolution-aware (≥1 px, 2.25 px at 576) so the "dream" smoothing exists at any working size. Colour sigma 0.3 → 0.2 (edges actually preserved).
FORMULA ADMISSION: Cauchy dispersion (F) NEW use on this file (row budget: refraction-shards B, this file D). Ideas 1 and 3 are tactic-derived; both consume quantities the file computes (total_disp recursion, depth sample, bilateral taps). Deletion test OK for each (still fractal glass + bilateral filter).
FORBID on this file: IQ palette, spring/ripple stamp beyond what HEAD owns (cursor pivot + click pre-warp), thin-film, a new param, replacing the recursion, kaleidoscope folds, extra "dream glow" bloom.
A PACKING: display RGBA (ACES) — unchanged; texels (0,0) = (pivot.xy, pivot vel.xy), (1,0) = (fract(lastTime), heldEnv, 0, 0.7371) are STATE (top-left corner), C read masked there.
```
### RESCUE list
- R1 dead/racy spring → A-texel critically-damped pivot spring (ω = √42 = HEAD's stiffness), shared dt, f16 rest-snap; `held` pop → eased envelope in the state texel.
- R2 bilateral discarded for R/B + sub-pixel sigma → filtered base reaches all channels (raw R/B taps contribute only their fringe delta); resolution-aware tap spacing; tap radius follows sigma. Default look changes (softer, edges kept).
- R3 audio inside `time*(…)` phase → bounded additive offset (`time + mids·0.9`). Identical at audio 0.
- R4 ghost domain → mix in display space after ACES, C clamped to [0,1] (inherited-C poison) and masked on the state texels.
- ~~R5 depth passthrough at the warped uv~~ — WITHDRAWN in the fix round (coordinator review): the depth OUTPUT stays HEAD's passthrough at the pixel's own uv; the warped-uv depth sample is only the bilateral range-weight centre.
- Not changed (flagged): `rotation_speed` is an angle, not a speed.

---------------------------------------------------------------------------------------------------
## 2. alpha-multi-layer-glass (2nd pass)

### HEAD facts (measured / read)
- Three pre-existing ideas stay: per-pane surfaces + parallax; rotated 4-tap frost; Beer-Lambert pane edges.
- **`chromatic` slider is effectively dead**: chromaticStrength = chrom·(0.008+mids·0.006) multiplies a pane offset of ≈0.01–0.03 UV → ≈3e-5 UV (0.02 px). Sweep chromatic 0 vs 1 vs default: mean|Δ| 0.0001, p99 0.004.
- **`ior` slider is nearly dead**: it only changes the Fresnel R0 (0.005–0.075, only felt at grazing lines): ior 0/1 vs default mean|Δ| 0.005/0.006. A real IOR sets how hard the pane bends.
- thickness (0.036/0.071) and roughness (0.005/0.016) are live (roughness weak but present).
- `mouseNormal = normalize(uv − mouse + 1e-4)` is a UNIT-slope cone with a singular point at the cursor (idle cursor sits at the screen centre): the normal flips direction within ~1 px of the cursor and has the same slope at every distance up to 0.35 — no physical touch profile.
- `prevInternal` (C) is unclamped → an inherited C = 50 puts 5.0 into the output for a frame. C holds ACES display output and is mixed in display space (consistent).
- Raw pointer: spring was already removed in the previous pass — leave it.

### Idea Card
```
SHADER: alpha-multi-layer-glass
IDENTITY: a stack of three refracting, frosted, absorbing glass panes over the photo; alpha stores the stack's transmittance
KEEP VERBATIM: 4 params + roles (ior → pane index, thickness → offset/path length, chromatic → dispersion, roughness → frost); per-pane noise surfaces + parallax around the cursor (Idea 1), rotated 4-tap frost (Idea 2), Beer-Lambert pane edges (Idea 3); Schlick Fresnel pseudo-angle; stack accumulation by transmittance weights; plateWave; ripples; spec; ACES; A = display RGBA; semantic transmittance alpha; raw pointer.
MECHANISM INTERROGATION (§12.1):
  tactic 2 (physics one step further): a stack of panes shows DOUBLE IMAGES — light that reflects off the back of one pane and the front of the next arrives laterally displaced and weak (R1·R2); only bright sources are strong enough to be seen (lamp ghosts in a double-glazed window). A pane pressed by a finger flexes into a dimple whose slope is zero at the contact point and steepest at the rim (Gaussian bump), and the front pane flexes more than the rear one.
  tactic 3 (promote an intermediate): `fresnel` per pane and `paneOffset` per pane are computed and thrown away after one use — the ghost reuses both (weight = F_i·F_{i−1}, position = −2·(offset_i+offset_{i−1})); `mouseDist`/`mouseInfluence` already exist — the dimple profile is a function of the same distance.
  tactic 4 (second-order the parameter): ior should scale the pane bend (n−1), normalised so the default is unchanged; chromatic should disperse at a visible magnitude.
  tactic 6 (history): C stays the display-space internal-bounce ghost (8–13 %), now clamped; no new state, no new texel use.
ADD (2 native ideas):
  4. Inter-pane ghost reflections — one extra tap per pane pair at the double-bounce position, bright-pass only (lamp-like highlights) × F_i·F_{i−1} × gain; adds to the stack as reflected light. Visible as a faint displaced copy of the bright blob, strongest along the grazing pane lines.
  5. Press dimple — replaces the singular unit-slope cone by a Gaussian-bump slope r·exp(−r²/2σ²) (zero at the contact point, steepest at the rim); front pane flexes fully, deeper panes less (×(1−0.3·layer)); held pointer deepens it (existing 0.5+0.5·held). Same pointer, same radius (0.35), no new state.
FORMULA ADMISSION: neither is a §12.2 table row (tactic-derived); Henyey–Greenstein (allowed for this file) deliberately NOT used — the frost radius at the default (0.6–2 px at 192) is too small for a lobe change to be visible, so it would be an invisible idea. Both consume quantities already computed (fresnel/paneOffset/mouseDist).
FORBID on this file: spring, click-shockwave stamp beyond the existing ripples, IQ palette, a new Cauchy row (file owns `chromatic`), thin film, new param.
RESCUE (not ideas): R6 chromatic magnitude ×~35 so the slider is live (default fringe ≈1–2 px at 192); R7 ior scales the pane bend, normalised per layer so the DEFAULT (ior 0.5) offset is byte-identical; R8 clamp C to [0,1] (inherited-C poison); (the dimple also removes the cursor singularity at the idle centre cursor).
A PACKING: display RGBA (ACES), unchanged; alpha unchanged formula.
```
