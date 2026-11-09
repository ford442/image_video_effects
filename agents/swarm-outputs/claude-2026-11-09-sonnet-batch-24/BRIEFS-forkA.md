# BRIEFS — Fork A (sonnet/batch-24): fabric-zipper (2nd pass), fabric-step-gabor (1st pass)

Written 2026-11-09 BEFORE any WGSL edit. HEAD renders: scratchpad/forkA/ (zip_head_{192,576}_{idle,held}.png, step_head_f{60,150,300,600}_{idle,held}.png, step_head_long*.png).

---------------------------------------------------------------------------------------------------
## 1. fabric-zipper

### HEAD observation (192 + 576 px, idle + held, audio 0 / 0.4,0.3,0.2)
Healthy. Zipper opens above the slider, below it the chain is closed. At 576 px the closed chain is a
single column of gold bars; in the open V both flanks carry bars at the SAME y phase (a mirror image,
not an interlocked chain). Teeth are one flat colour (`tooth_col`), slider is a flat grey disc with a
noise tint, no stitching on the tape, the weave is untouched by the slider. No NaN, meanL 0.225 / stdL
0.118 / meanA 0.796 (192 idle).

### Idea Card
```
SHADER: fabric-zipper
IDENTITY: a woven cloth cover unzipped by the cursor to reveal the photo; lit twill + rolled tape lips
KEEP VERBATIM: 4 params and roles (teeth_density → tooth pitch, spread → opening_width,
  weave_freq → twill thread density, jaggedness → tooth/edge scallop amplitude); slider follows the
  cursor with the opening above it; twill height field + lighting (IDEA 1 of last pass); rolled lips
  + contact shadow on the image (IDEA 2); seam line; semantic material alpha; ACES display RGBA in A,
  C not read; depth passthrough.
MECHANISM INTERROGATION (§12.1):
  tactic 1 (deepen the kernel): the "teeth" are a one-bit mask `step(0.4, fract(y*pitch))`. The
    next-better approximation of a zipper chain is two staggered rows of teeth whose heads cross the
    centre line and mesh — still the same pitch and still `fract(y*pitch)`.
  tactic 2 (follow the physics one step further): metal teeth catch the key light and show a
    grazing-angle rim; the slider body is steel not grey paint; a sewn tape carries the stitch rows
    that clamp the chain on. A technician names: interlock, brass scoop/barrel teeth, slider body,
    tape stitching, pulling/bunching of the tape at the slider.
  tactic 3 (promote an intermediate): `edge_dist` (signed distance to the cut edge) is already the
    quantity the lips and the contact shadow hang on — stitching rows are just two more bands at fixed
    edge_dist; the half-pitch stagger is `fract(y*pitch + 0.5*side)`. `slider_dist` is already
    computed for the slider disc — it also gives the dome normal and the pucker envelope.
  tactic 6 (history): C not read in HEAD and stays unread (no new continuity needed).
ADD (4 native ideas, all in the existing main path):
  1. Interlocking chain — left/right teeth offset by half a pitch, duty 0.5, heads crossing the centre
     line by ~0.4·TOOTH_HALF so the closed chain MESHES (alternating left/right heads) and the open
     flanks are staggered; the image-reveal scallop (`jagged_width`) takes the same half-pitch sign flip
     so the cut edge follows the teeth. Band-limited edges (pixel footprint) instead of hard `step`.
  2. Lit metal hardware — each tooth is a small barrel/dome in its own (edge, along) coordinates:
     diffuse + Blinn highlight from the SAME LIGHT_DIR as the twill, Fresnel–Schlick rim (§12.2F) with
     brass F0; the slider becomes a lit steel dome with a pull-tab post hole and a soft contact shadow
     on the tape. Teeth cast a thin contact shadow onto the fabric. (Same material helper for both.)
  3. Twin lockstitch rows — two dashed thread rows on each tape flap, parallel to the cut edge at fixed
     edge_dist offsets beyond the lip (they follow the edge as it opens), dash length locked to the tooth
     pitch, thread shaded as a rope (cross-section profile) with the twill groove darkened beside it.
  4. Tape bunching at the slider — chevron folds in the tape near the slider body (pinch of cloth
     being forced through the slider): a smooth fold height field modulates the twill normal + a small
     weave-coordinate bend, strongest on the closed side just below the slider, fades out by ~0.15.
FORMULA ADMISSION: row used = Fresnel–Schlick (§12.2F) on idea 2; it consumes the surface normal /
  LIGHT_DIR the file already has; deleting it leaves flat gold teeth (HEAD); family match: lit metal
  hardware on cloth = lighting/optical. Ideas 1,3,4 are tactic-derived (not table rows) and consume
  `edge_dist`, `slider_dist`, `tw` that already exist. Deletion test: removing any one leaves a
  recognisable zipper; keeping only the idea (no cloth/opening) is not a zipper.
FORBID on this file: springs, click shockwaves/ripples, IQ palette, any new param, changing the twill
  or lips, replacing the cloth look.
A PACKING: ACES display RGBA with HEAD material alpha (unchanged).
```
Default-look note: teeth geometry changes (staggered, duty 0.5 instead of 0.6, anchored on the tape,
lit); reveal-edge scallop on the right flap flips phase. These are the idea, not a rescue.

---------------------------------------------------------------------------------------------------
## 2. fabric-step-gabor

### HEAD observation
Short run (t≈2–5 s): saturated psychedelic Gabor colour over almost the whole frame; the cloth is not
visible as cloth. Long run (HEAD, 192 px, 60 / 150 / 300 / 600 frames, idle AND held cursor): the wash
never clears, pink/magenta tear regions along the top/left edges and under the cursor GROW from 300 →
600 frames and never heal. Held cursor leaves a permanent magenta smear plume. Root causes, from the code:
- **R1 no cloth.** Each pixel integrates its own `pos` with Verlet + a tether to its own rest `uv`;
  there is NO neighbour coupling. "Mass-spring" is only a per-pixel oscillator.
- **R1b constraint window is in texels.** `restLen = 1/res.x`; the pull-back only acts for
  `dist ∈ (2, tearThreshold) texels` (tearThreshold 1.5..4 texels ≈ 2.75 at default). Wind
  (`(fbm−0.5)·0.001` per frame, steady-state |v| ≈ 5e-3 uv/frame ≈ 1 texel/frame at 192 px, 5 at 1080) pushes
  pixels past the window within a few frames, after which NOTHING pulls them back: permanent tear +
  monotone drift to the clamped frame edges. Resolution dependent (the window shrinks as res grows).
- **R1c strain is displacement**, `clamp(|pos−uv|·50)` saturates at 0.02 uv, so a uniformly shifted
  (unstretched) cloth reads as maximally strained → wash everywhere.
- **R2 texel-edge C read.** `textureSampleLevel(dataTextureC, non_filtering_sampler, uv…)` at
  `uv = coord/size` (texel EDGE, not centre) → off-by-one-texel risk; use exact `textureLoad`.
- **R3 f16 precision.** A is rgba16float on balanced/battery tiers; HEAD stores absolute uv in [0,1]
  (resolution ≈ 5e-4, ~1 texel at 2048): per-frame velocities (1e-3) quantise to zero → frozen/noisy on
  those tiers. minirender is f32 and cannot show it; the offset packing below fixes it by construction.
- **R4 cost.** The 9×9 Gabor taps are re-sampled for each of the 4 orientations (324 samples + 324 exp):
  the Gaussian envelope and the taps are orientation independent.
- Mouse distance is in uv, not aspect corrected (elliptical on screen). B is written (strain, vel, 1)
  and never read — HEAD owns it, kept.

### Idea Card
```
SHADER: fabric-step-gabor
IDENTITY: the photo as a cloth that flutters and is pushed by the cursor; where the cloth is strained a
  4-orientation Gabor bank paints the oriented texture in a psychedelic cosine palette
KEEP VERBATIM: 4 params + roles (stiffness → how strongly the cloth holds/couples, tearThreshold →
  stretch at which the cloth lets go [range 1.5..4 kept, now a stretch RATIO], gravity → downward sag,
  damping → Verlet velocity damping 0.95..0.999); Verlet displacement with prev state; fbm wind
  (`fbm(pos*4+…)`); cursor pushes the cloth away inside r=0.15; pinned top edge; Gabor bank
  (4 orientations, freq/sigma/responseScale recipe, 9×9 support), cosine palette per orientation,
  |response|-weighted blend, ×1.3, strain mix 0.7, strain colour (blue→orange ×0.2), fabric alpha
  (0.9→0.7), B = (strain, vel, 1.0), depth read at pos.
RESCUE (the cloth did not read as cloth; recorded separately from ideas):
  R1 the displacement field is now a real mass-spring sheet: Hooke tether to rest + isotropic 9-point
     Laplacian coupling (§12.2D) on a fixed ~180-cell grid (stride s = round(res.y/180) so the cloth is
     the same at every resolution), explicit-Verlet stable (c² ≤ 0.5); wind/gravity/cursor are
     accelerations; the tether/coupling weaken (never vanish) where the local stretch exceeds
     tearThreshold → tears HEAL (no tear flag channel exists; A is full).
  R1c strain = real stretch from the cloth's deformation gradient (see idea 1), not displacement size.
  R2 exact textureLoad of C (clamped), junk guard |d| ≤ 0.15 (previous shader's A is inherited on switch).
  R3 A = (d, dPrev) OFFSETS from the rest uv (f16-safe), zero state = rest, no init branch.
  R4 the 9×9 neighbourhood is fetched once and shared by the 4 orientations (identical maths).
  R5 cursor distance aspect-corrected.
MECHANISM INTERROGATION (§12.1):
  tactic 2: a sheet under tension shows (a) thread lattice, (b) wrinkles where compressed.
  tactic 3: with a real coupled field `J = I + ∇d` is free (4 taps we already need for the Laplacian);
    HEAD threw away direction entirely and used `atan2(vel)*strain`.
  tactic 6: C holds the cloth field; its neighbours give J without any new state.
  tactic 7 (direction): stretch is anisotropic — the principal axis of the Cauchy–Green tensor is the
    direction a real Gabor-type analyser of a woven cloth would lock onto.
ADD (3 native ideas):
  1. Principal-strain orientation (Structure-tensor orientation, §12.2A): C_g = JᵀJ (aspect-corrected),
     θ = ½·atan2(2·C₁₂, C₁₁−C₂₂), coherence = (λ₁−λ₂)/(λ₁+λ₂). Rotates the Gabor bank by θ·coh·strain
     (replaces atan2(vel)·strain; time·0.05 drift kept). Also supplies σ_max (tear gate) and σ_min.
  2. Thread lattice in MATERIAL space — plain-weave checker (cos·cos) evaluated at `pos` (the source /
     material coordinate each pixel displays), pitch ≈ 7 px of the SOURCE so it lands inside the Gabor
     bank's frequency band; it modulates the displayed colour a little and the Gabor tap luma a lot,
     so the bank genuinely detects thread direction and the lattice stretches/shears with the cloth —
     the folds become visible. (Deformation of a smooth photo alone is nearly invisible.)
  3. Compression buckling — `area = det J`; where the cloth is compressed (area < 1) it bunches: darken
     (wrinkle valley) and add a faint sheen on the stretched side; reads as folds. No new state.
FORMULA ADMISSION: row 1 = Structure-tensor orientation (A) — consumes ∇d which the Laplacian already
  loads; deleting it leaves the cloth + Gabor (HEAD angle); row Isotropic 9-point Laplacian (D) is used
  as the coupling term (rescue R1, listed in NOTES). Ideas 2, 3 are tactic-derived. Family match: cloth
  = liquid/sim + texture-analysis; both rows consume quantities the file now has.
FORBID: springs for the cursor (HEAD cursor is a push, kept), ripples, a spring-damper cursor in
  extraBuffer, audio overlay, new params, changing the palette or the Gabor recipe, a second solver.
A PACKING: raw sim state — A = (d.xy, dPrev.xy) displacement OFFSETS from the rest uv (HEAD stored
  absolute (pos, prevPos)); NOT tone-mapped; ACES only on writeTexture. B = (strain, vel.xy, 1) as HEAD.
```
Audio: not claimed, not added (no plasmaBuffer use). `upgraded-rgba` tag added only with ACES on the
display RGB. Display change: ACES on writeTexture (floor).
