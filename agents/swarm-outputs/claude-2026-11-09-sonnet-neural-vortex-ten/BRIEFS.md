# sonnet/neural-vortex-ten — Idea Cards (written BEFORE any idea edit to WGSL)

Contract: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §9, §12). Batch date for headers: **2026-11-09**.
Requested ids (10): neural-nexus, conv-reaction-convolution, fluid-grid-rgba-fluid, gen-chromatic-vortex,
mouse-neural-dreamscape, spectral-distortion, scan-slice, chroma-vortex, neural-resonance, phosphor-magnifier.

Theme already living in the files: **pointer-led fields and feedback** — three neural-network shaders, two vortices,
a reaction-diffusion filter and a fluid grid, and three "scan / spectrum / CRT" optics. Each card below is written in
its own device's vocabulary; no two files share an idea.

Infrastructure done first, in its own commit (`ece93c36`), before any idea work: 7 of the 10 files pasted the 13-binding
header; migrated with `scripts/migrate_to_prelude.py --naga` (V1–V5 proofs green). **No `Upgraded:` bump for that.**

Engine facts re-verified in this repo (not copied from a previous batch):
- `src/renderer/webgpu/audioDepth.ts::writeExtraBuffer` re-uploads the whole 256-float `extraBuffer` every frame
  (`[0..2]` audio, `[4]` historyHead, `[5..132]` FFT, everything else zero). So the `[133..138]` springs in
  neural-nexus, spectral-distortion, scan-slice and neural-resonance never persist: their "first frame" snap fires every
  frame and they behave as the raw cursor. **Reported, not repaired here** (out of scope for an idea batch; no idea below
  depends on a persistent spring).
- Colour/history textures are `rgba16float` on the default tiers (filterable); on an `rgba32float` tier without
  `float32-filterable` the layout is unfilterable, so a filtering `textureSampleLevel(dataTextureC, u_sampler, …)` is a
  latent pipeline error. Where a file I touch does that (fluid-grid, neural-resonance, mouse-neural-dreamscape) the read
  becomes an exact `textureLoad` (manual bilinear where the half-texel average is the look). Floor, not idea.
- Audio is `plasmaBuffer[0].xyz` only.

Tactics used (§12.1): T1 deepen the kernel · T2 physics one step further · T3 promote an intermediate · T4 second-order
the parameter · T5 name the artifact of the real device · T6 use the history the shader already owns · T7 direction.

Row ledger (§12.4 de-dup — each §12.2 row on ≤ 2 files): Isotropic 9-pt Laplacian (D) conv-reaction · Vorticity
confinement (D) fluid-grid · Cauchy dispersion (F) spectral-distortion. Every other idea is the file's own vocabulary.
Nothing repeats.

ACES policy for this batch: kept where HEAD has it (conv-reaction, gen-chromatic-vortex, chroma-vortex,
phosphor-magnifier). **Not added** to pure photo resamplers (fluid-grid, spectral-distortion, scan-slice): a tone curve
on a re-sampled photo would change the picture, not the effect. Neural-additive composites (neural-nexus,
mouse-neural-dreamscape) tone-map the *additive light layer only*, so the photo underneath is untouched.
neural-resonance keeps HEAD's clamp (A = raw display RGB read back as history; an ACES in the loop would drift).

---
## 1. neural-nexus — interactive-mouse, 167 lines
```
SHADER: neural-nexus
IDENTITY: hashed neurons whose pulses propagate out from the pointer; dendrite lobes, warm sparks, cyan click bursts, all
  additive light over a photo that is nudged by the activity field.
KEEP VERBATIM: 4 params (Density → neuron count, Signal Speed, Decay, Branches → dendrite lobes); per-neuron FFT voice;
  signalPhase / pulse / dendrite / aura; click synapse bursts over u.ripples; mousePulse; the warp of sampleUV; the
  electric-blue / synapse-purple / warm-spark / click-glow colours; the HEAD spring (dead — untouched); A = raw
  (totalActivity, sparks, mousePulse, alpha).
INTERROGATION: T5 a neuron has dendrites (HEAD) *and an axon* — the wire that carries the spike to the next cell. The
  shader has soma blobs and dendrite lobes but nothing travelling between neurons. T3 `signalPhase`/`connectionDist`
  already say when each neuron fires; the axon can be gated by that same firing term. T6 A already stores `sparks` in
  .g; C is read back nowhere, so an integrate-and-fire trace is free and keeps HEAD's raw-field packing.
ADD:
  1. Axon fibres with travelling action potentials — each neuron i is wired to neurons i+1 and i+3; segment SDF gives a
     thin cyan fibre; an impulse packet runs source→target at a rate that rides Signal Speed, brightness gated by the
     source neuron's own firing term (pointer-near neurons fire first, so the cascade leaves the cursor along the wires).
  2. Spike-rate afterglow — `sparks = max(sparksNow, C.g · keep)` from an exact C load, `keep` from the Decay slider, so a
     firing neuron lingers instead of flickering with |pulse|.
FORBID: a new spring, IQ palette, ripple stamps beyond HEAD's, any new param, replacing the dendrite aura.
A PACKING: raw sim state (totalActivity, sparks incl. afterglow, mousePulse, alpha) — HEAD's, C.g now read back as sparks.
ROWS: none.
```

## 2. conv-reaction-convolution — image, 164 lines (Ideas 2026-09-08: C.rg persistence; Pearson F/k)
```
SHADER: conv-reaction-convolution
IDENTITY: a Gray-Scott reaction-diffusion filter on the photo: luma seeds A, edge energy seeds B, C.rg carries the
  chemicals, mouse injects B, ripples feed travelling fronts; output packs (A, B, mixed blue, activity).
KEEP VERBATIM: 4 params (Diffusion A, Diffusion B, Feed Rate, Mouse Influence); the luma/edge seeding and 0.82 C.rg
  persistence; image-Laplacian terms; mouse/ripple feed; the Pearson k line (feedBase → kill); CA on edges; ACES on
  finalColor; packed = (A, B, final.b, activity) — HEAD's documented packing.
INTERROGATION: T1 `lapA`/`lapB` are 4-point Laplacians of the *image*; the chemicals live in C but never diffuse — the
  PDE is only a relaxation toward the picture, so patterns cannot propagate. The next-better operator on the stored state
  is an isotropic 9-point Laplacian of C.rg. T4 `feedBase` is one scalar for the whole frame; Pearson's map says F/k
  decide spots vs stripes vs mitosis, so a spatially varying F over the photo paints regimes onto the picture.
ADD:
  1. Isotropic 9-point Laplacian of the stored chemicals (§12.2D) blended with the image Laplacian — fronts now
     actually diffuse through C.rg (8 exact loads), without the 5-point axis bias.
  2. Luma-painted Pearson regime — local F is scaled by the source luma (bright = spots, dark = labyrinth) and `kill`
     follows the same Pearson line from the local F; Feed Rate keeps its role (global F).
FORBID: springs, new params, IQ palette, touching the packed output layout, changing the persistence constants.
A PACKING: HEAD's (A, B, mixed blue, activity); C.rg = chemicals.
ROWS: Isotropic 9-point Laplacian (D).
```

## 3. fluid-grid-rgba-fluid — advanced-hybrid, 164 lines
```
SHADER: fluid-grid-rgba-fluid
IDENTITY: a quantised grid of photo tiles pushed by a live Navier-Stokes field (semi-Lagrangian advection, viscosity,
  one Jacobi pressure step, mouse force, ripple dye) with grid lines tinted by velocity hue / dye density.
KEEP VERBATIM: 4 params (Grid Size, Viscosity, Dye Intensity, Decay Rate); advection / diffusion / pressure / mouse force /
  ripple injection; per-tile displacement by velocity+pressure; dye-tinted grid lines; A = raw (vel.xy, pressure, density).
INTERROGATION: T2 numerical viscosity from bilinear semi-Lagrangian advection smears small swirls — the first-order fix
  every fluid author applies is vorticity confinement. T3 the curl is the intermediate HEAD never computes, yet the
  tiles are the natural place to *show* it: a tile in a swirl should turn, not just slide.
ADD:
  1. Vorticity confinement (§12.2D, D1) — curl of the stored velocity from exact C loads, force N×ω along the
     curl-gradient normal added to the velocity (bounded, with a light drag so it cannot run away).
  2. Vorticity-spun tiles — the curl at each tile centre rotates the tile's sample coordinates about that centre, so
     tiles turn like gyros inside eddies and stay still in laminar flow.
FLOOR (not ideas): the filtering sampler on C becomes an exact manual bilinear (same half-texel addressing, identical
  picture); grid-line alpha is semantic instead of hard 1.0.
FORBID: ACES (pure photo resampler), spring, IQ palette, any new param, replacing the solver, packing B.
A PACKING: raw sim state (vel.xy, pressure, density), HEAD's.
ROWS: Vorticity confinement (D).
```

## 4. gen-chromatic-vortex — distortion, 164 lines (Ideas 2026-10-05: mirror-fold glint; breathing dispersion; hue arms)
```
SHADER: gen-chromatic-vortex
IDENTITY: a polar swirl warp of the photo (mirror-folded sectors, per-channel sector/radius dispersion, rotating YUV
  chroma, hue-carrying arm streaks, fold glint) with a display-space persistence blend.
KEEP VERBATIM: 4 params (Swirl Strength, Radius Scale, Polar Distortion, Color Warp); spiral/warpPhase/foldedTheta; the
  three existing ideas (glint, breathing dispersion, hue arms); YUV rotation; ACES; A = ACES display RGBA.
INTERROGATION: T3 `depth` is read and only used for a 20 % alpha dim — the vortex is flat. T4 the swirl is one scalar
  `swirlStrength·r·radiusScale`; a funnel winds tighter where things are near. T6 C is display colour read at the *same*
  pixel at 4 % — a ghost that sits still while the arms rotate; a vortex's long exposure smears along the azimuth.
ADD:
  4. Depth-sheared twist — the swirl rate is multiplied by (1 + k·(depth − ½)), so foreground winds tighter than the
     background (differential rotation in the funnel). Flat depth ⇒ HEAD exactly.
  5. Azimuthal comet trails — history is read at the position rotated back about the vortex centre by the arm's own
     angular rate (exact bilinear C loads), and the persistence weight is lifted by `streak`, so each arm drags a curved
     tail instead of a stationary ghost.
FORBID: a new fold/sector system, Cauchy (spectral-distortion has it), springs, ripples, new params.
A PACKING: ACES display RGBA (HEAD's).
ROWS: none.
```

## 5. mouse-neural-dreamscape — interactive-mouse, 163 lines
```
SHADER: mouse-neural-dreamscape
IDENTITY: a grid of virtual neurons that light by pointer proximity; 8-neighbour synapse lines glow when both ends are
  active; click ripples send activation waves; activation decays through C; palette-coloured somas over a dimmed photo.
KEEP VERBATIM: 4 params (Network Density, Activation Radius, Pulse Speed, Synapse Strength); grid/neuron maths;
  activation + ripple waves + decay `max(act, prev·0.95)`; neighbour-line geometry; neuron palette; alpha = activation.
INTERROGATION: T5 synapse lines in HEAD are static glows; a real synapse carries *directed* impulses. T6 C.r is read
  back already; the activation is cell-constant so the wire pixels carry no memory of having been lit — "fire together,
  wire together" is the first side-effect of co-activation and needs only one more channel.
ADD:
  1. Impulse packets on the synapses — a bright packet runs along each lit connection from the more-active cell to the
     less-active one (phase rides Pulse Speed, seeded per connection so the wires don't pulse in unison).
  2. Hebbian trace — A.g keeps a slowly decaying max of the connection glow, exact C load, and is redrawn at a fraction of
     Synapse Strength, so wires that fired together stay faintly lit after the pointer leaves.
FLOOR (not ideas): filtering read of C → exact `textureLoad`; additive light layer tone-mapped (photo untouched).
FORBID: spring, IQ re-palette, Gray-Scott, any new param, extra ripple stamps.
A PACKING: raw sim state — A = (activation, connection memory, 0, 0); C.r and C.g read back as exactly that.
ROWS: none.
```

## 6. spectral-distortion — interactive-mouse, 163 lines
```
SHADER: spectral-distortion
IDENTITY: three independent value-noise warp fields (R/G/B) tear the photo chromatically; a warp blob under the pointer,
  click warp rings, per-FFT-band R/B separation.
KEEP VERBATIM: 4 params (RGB Separation, Warp Scale, Mouse Influence, Speed); the three noise taps verbatim; blob /
  click-ring warpStr; `sepR/sepB` band separation; alpha; A = display RGBA.
INTERROGATION: T2 real dispersion is ordered by wavelength — n(λ)=A+B/λ² — red bends least, blue most; HEAD's R and B
  warp amplitudes are the same noise scale and a symmetric ±sep. T6 the feature tag says "temporal-persistence" but C is
  never read; A is display colour, so a per-channel lag is a free, truthful read-back. T5 three-chip cameras and
  phosphor screens lag red fastest, blue slowest.
ADD:
  1. Cauchy-ordered dispersion (§12.2F) — the per-channel warp offsets are scaled by 1 + B/λ² (650/550/450 nm, relative
     to green) with B from RGB Separation: a real prismatic ordering instead of fixed equal-and-opposite offsets.
  2. Per-channel spectral lag — each channel is low-passed against exact C history at its own time constant (R fastest,
     B slowest), amount riding RGB Separation, so motion leaves a red→blue colour ramp behind it.
FORBID: ACES (resampler), thin-film iridescence, new params, touching the dead spring.
A PACKING: display RGBA (HEAD's); C read back as colour.
ROWS: Cauchy dispersion (F).
```

## 7. scan-slice — interactive-mouse, 163 lines
```
SHADER: scan-slice
IDENTITY: up to seven vertical scan slices around the pointer; each shifts the image vertically by a pointer-derived
  offset, splits RGB horizontally, tints by its palette, glows cyan at the edge; clicks stamp short-lived slices; the
  background is desaturated and dimmed.
KEEP VERBATIM: 4 params (Slice Width, Offset Scale, Aberration, Bg Dimming); the slice bank + click slices and their
  `maxBand/bestOffset/bestIndex` competition; palette tint + per-slice FFT voice; edge glow; background desat/dim; peak
  normalise; alpha; A = display RGBA.
INTERROGATION: T5 the device is a slit-scan / line-CCD scanner: a slit records *one column*, repeatedly — content inside
  the slit is stretched toward its centre column; and a three-line CCD has per-channel sensor lines, so the three
  channels' slit apertures are not the same width. T3 `maxBand` is the winning slice's profile, but its centre and width
  are discarded by the competition — they are the missing intermediates.
ADD:
  1. Slit-scan stretch — inside the winning slice the x sample is pulled toward the slice's centre column by
     (1 − 0.45·band²), so the centre column smears sideways like a real slit (bounded, no change at the slice edge).
  2. Per-channel slit aperture — R and B evaluate their own slice mask against the (centre, width) that won, shifted by
     the Aberration offset, so a coloured fringe straddles the slice boundary instead of only inside it.
FORBID: ACES (resampler), spring/hold overlay beyond HEAD's, IQ palette, new params, afterglow of the head.
A PACKING: display RGBA (HEAD's).
ROWS: none.
```

## 8. chroma-vortex — visual-effects, 162 lines
```
SHADER: chroma-vortex
IDENTITY: two vortex centres (pointer + an orbiting one) rotate the photo with per-channel angle splits; a spiral-SDF
  mask tints by a spectral ramp; ACES on display.
KEEP VERBATIM: 4 params (Vortex Twist, RGB Split, Vortex Radius, Center Stability); the factor/power falloff; per-channel
  angleR/G/B split; the weighted colour blend of vortices; the spiral SDF mask; ACES; A = pre-ACES colour (HEAD's).
INTERROGATION: T2 real vortices come in dipoles — a counter-rotating partner is the first-order companion of any pair.
  T3 `angleBase` (the actual rotation applied) is computed and thrown away, while the ramp that colours the swirl is
  driven by depth, which is flat on most photos — the colour wheel is not tied to the swirl it decorates.
ADD:
  1. Counter-rotating third vortex — the centre list grows to {pointer, orbiter, point-reflection of the orbiter}, the
     new one with opposite circulation and weight 0.45 (a vortex dipole with the orbiter).
  2. Rotation-phase hue — the spectral ramp gains the weighted applied rotation angle, so rainbow bands follow
     iso-rotation contours of the swirl.
FORBID: Cauchy (spectral-distortion has it), a history/persistence layer (not in HEAD), IQ palette, springs, new params.
A PACKING: pre-ACES colour RGBA (HEAD's); A is not read back.
ROWS: none.
```

## 9. neural-resonance — artistic, 162 lines
```
SHADER: neural-resonance
IDENTITY: a curl-noise warped feedback loop: the photo and previous display colour are advected by the same curl field,
  split chromatically along it, tinted cyan/magenta, with click rings that linger through feedback.
KEEP VERBATIM: 4 params (Amplification, Curl Strength, Feedback Mix, Chromatic Drift); curlField; mouse mask; the warp;
  chroma split; feedback mix; synapseTint; click rings; clamp (no ACES in the loop); A = display RGB (read back as C),
  B = mask quad.
INTERROGATION: T7 feedback is read at a single warped point — magnitude only. Feedback in a real flow smears along the
  streamlines (iron-filings, ink in turbulence). T3 `length(curl)` is exported to B but never shown; the synaptic tint is
  uniform, so nothing marks where the flow actually winds up.
ADD:
  1. Streamline-aligned persistence — the feedback is gathered as three exact-bilinear taps *along the curl direction*
     (length = the curl displacement the pixel already has), so trails stretch along flow lines.
  2. Eddy-core synapse glow — the synapse tint amplitude is modulated by the local curl magnitude (normalised by Curl
     Strength), so cores of strong curl flare and laminar regions stay calm.
FLOOR (not ideas): the filtering sampler on C → exact manual bilinear.
FORBID: ACES in the loop, spring repair, new params, new ring system, IQ palette.
A PACKING: display RGB + alpha (HEAD's, raw clamp); B = mask quad (HEAD's).
ROWS: none.
```

## 10. phosphor-magnifier — interactive-mouse, 162 lines (Ideas 2026-10-04: per-channel persistence; beam blooming)
```
SHADER: phosphor-magnifier
IDENTITY: a CRT lens under the cursor — magnification, aperture-grille mask, scanlines, per-channel phosphor persistence,
  beam blooming, degauss rings, click shells; ACES display RGBA read back as the afterimage.
KEEP VERBATIM: 4 params (Zoom Level, Pixel Size, Glow, Lens Size); barrel + depth magnification; snapped pixel sampling;
  shadowMask + bloomW; scanLine/scanBeat; degauss from held/click; persistence `max(display, C·decay)`; ACES; alpha; A.
INTERROGATION: T5 a CRT technician names convergence error (the three guns miss each other, worst near the edge of the
  tube), purity error (a magnetised shadow mask lands beams on the wrong phosphor stripes) and degauss. HEAD has the
  degauss; its chromatic split is a fixed ±x shift of constant size, and a held pointer only raises ring brightness.
  T4 `caStrength` is one scalar; real convergence error grows with radius.
ADD:
  1. Edge-growing radial convergence error — the R and B guns are displaced radially about the lens centre by
     caStrength·(0.35 + 2·(dist/lensSize)²) with a small vertical component, instead of a constant ±x shift.
  2. Held-pointer purity error — while the pointer is held the magnet pulls the mask: a phase shift
     (≈ heldPressure² · 0.28 stripe periods, slowly breathing) is applied to the grille lookup, so stripe colours rotate
     into each other with a smooth graded contour around the cursor.
FORBID: another persistence/bloom variant, interlace flicker, ripple stamps beyond HEAD's, IQ palette, new params.
A PACKING: ACES display RGBA (HEAD's); C read back as the afterimage.
ROWS: none.
```

---
## Amendments found while implementing (cards above are the pre-edit originals; these are the changes, with the evidence)

**A1 — fluid-grid-rgba-fluid: a third idea was needed (stirring).** HEAD's only pointer force is radial
(`normalize(uv − mouse) · −0.3`) and the ripple injection is radial too — both curl-free. With vorticity ≈ 0, the carded
confinement and tile-spin rendered identical to HEAD in the harness (meanL 0.4333 vs 0.4329). Added **Idea 1: tangential
stirring** (same falloff and hold gate as the radial force, ×0.2), and renumbered confinement → Idea 2 and spun tiles →
Idea 3. Still 3 ideas, all in the solver's own vocabulary.

**A2 — phosphor-magnifier: the carded ideas were re-picked.** `shadowMask(snappedG, …)` is evaluated at the *snapped*
coordinate, so `fract(snapped·pixelSize) ≈ 0` and the mask is (0,1,0) everywhere. R and B are multiplied by 0, so HEAD's
lens is a green-phosphor look; the per-channel R/B sampling (and so the carded edge-growing convergence error, and HEAD's
own "beam blooming across the grille") has no visible effect. Not repaired (un-greening the lens would change the picture's
identity) — **reported for the coordinator / real-GPU QA**. The two replacement ideas act on live paths: **Idea 3 vertical
beam-spot growth** (scan-line gaps fill with beam current) and **Idea 4 held-pointer magnet bending the raster** (the other
half of HEAD's held = degauss story). Numbering continues HEAD's 1–2.

**A3 — ACES policy line.** The policy above said neural-additive composites would tone-map the additive layer only. On
inspection a low-end-preserving shoulder is a look change in its own right, so neural-nexus and mouse-neural-dreamscape
keep HEAD's output stage (no tone-map), like the photo resamplers. ACES stays where HEAD has it.
