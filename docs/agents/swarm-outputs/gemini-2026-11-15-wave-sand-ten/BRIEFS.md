# Idea Cards — gemini/wave-sand-ten (2026-11-15)

Written **before** any WGSL edits. Ten catalog shaders (49–94 lines; 14 WGSL files total including multipass graphs `poincare-tiling` and `ripple-tank`) spanning generative, liquid-effects, simulation, and advanced-hybrid families:
`gen-julia-set-classic`, `gen-interference-moire-field`, `liquid-v1`, `sim-sand-dunes`, `poincare-tiling` (2 passes), `cymatic-sand`, `ripple-tank` (4 passes), `pixel-sand`, `fire-smoke-volumetric-fog`, `optical-flow-dream` (`optical-flow-estimate.wgsl`).

Every card adds 2 native ideas inside the existing main path. Saved `params` stay byte-exact across all ten JSON definitions. No `extraBuffer[133..138]` spring cursor is added to any file. No shared ripple stamp or generic overlay.

Ten WGSL files still paste the canonical 13-binding header (`sim-sand-dunes.wgsl`, `poincare-tiling-map.wgsl`, `poincare-tiling-layer.wgsl`, `cymatic-sand.wgsl`, `ripple-tank-inject.wgsl`, `ripple-tank-pass2.wgsl`, `ripple-tank-pass3.wgsl`, `pixel-sand.wgsl`, `fire-smoke-volumetric-fog.wgsl`, `optical-flow-estimate.wgsl`). Those are migrated first via `python3 scripts/migrate_to_prelude.py --files ...`; that header swap is infrastructure and is not counted toward any Idea Card.

**Batch formula de-duplication (§12.4 / §12.7):** every §12.2 formula row newly applied appears at most once (Blackbody twice, on the two genuinely thermal shaders):
- Cauchy / spectral grating dispersion (§12.2F) → `gen-interference-moire-field` only
- Isotropic 9-point Laplacian (§12.2D) → `liquid-v1` only
- Snell vector refraction (§12.2F) → `liquid-v1` only
- Shallow-water / granular continuity flux (§12.2D) → `cymatic-sand` only
- Deep-water / bathymetric dispersion (§12.2D) → `ripple-tank` only
- Fresnel–Schlick + Beer–Lambert water optics (§12.2F) → `ripple-tank` only
- Blackbody thermal emission (§12.2F) → `pixel-sand` and `fire-smoke-volumetric-fog` (2 files, both thermal/incandescent)
- Boussinesq buoyancy (§12.2D) → `fire-smoke-volumetric-fog` only
- Henyey–Greenstein forward scatter (§12.2F) → `fire-smoke-volumetric-fog` only
- Structure-tensor orientation (§12.2A) → `optical-flow-dream` only
- MacCormack advection (§12.2D) → `optical-flow-dream` only

---

## 1. gen-julia-set-classic

```
SHADER: gen-julia-set-classic
IDENTITY: classic quadratic escape-time Julia set z ← z² + c with smooth iteration colouring, exterior distance estimate, spiral orbit traps, pseudo-3D orbit twist, held-pointer complex C steering, and click-ripple perturbations.
KEEP VERBATIM: C Real, C Imaginary, Zoom, Iterations (exact non-unit ranges [-1.5..1.5], [-1.5..1.5], [0.2..4], [16..160]); held mouseC mix; clickWarp; z² + c escape loop; spiral orbit trap; pseudo-3D orbit twist; log|z| stripeAcc; exterior distance estimate deEdge; raw HDR display RGBA history in A/C; acesToneMap on writeTexture.
MECHANISM INTERROGATION:
  tactic 3 (promote an intermediate): the running complex derivative dz is already updated every iteration, yet only scalar length(dz) is used for de, discarding dz's complex phase; in Douady–Hubbard potential theory, complex division z / dz (kept twist-coherent with z) gives the exact 2D exterior normal of the Green's potential G(z) for sculpted 3D relief lighting, while escaped atan2(z.y, z.x) traces binary-decomposition external rays landing on the Julia boundary.
  tactic 1 & 2 (deepen complex dynamics inside filled Fatou basins): points inside the filled Julia set (interior = 1 - escapedMask) currently render as flat dark navy; tracking period-2/3 orbital step convergence |z_n - z_{n-2}| and argument inside the existing loop reveals chambered Fatou attracting-cycle shells and phyllotactic flower petals inside Douady-rabbit / basilica basins.
ADD (2 native ideas):
  1. Douady–Hubbard complex-potential 3D normal (z / dz) & binary-decomposition external rays — keeps dz rotation-coherent with twist and promotes complex quotient z / dz into an analytic 3D equipotential surface normal for raking specular/Lambertian relief plus subtle external-ray field lines landing on the fractal boundary.
  2. Fatou interior attracting-cycle convergence shells & basin petals — tracks orbital period-2 contraction |z - zPrev2| and complex argument inside the existing loop so non-escaping Fatou basins bloom with chambered Boettcher shells and subtle jewel-toned petal geometry while keeping deep contrast against the exterior filaments.
FORBID: changing slider ranges, replacing z² + c with a different fractal, adding a spring cursor, ACES inside dataTextureA.
A PACKING: raw HDR display RGBA history in A/C (unchanged; acesToneMap on writeTexture).
```

---

## 2. gen-interference-moire-field

```
SHADER: gen-interference-moire-field
IDENTITY: crossed rotated analytic line gratings with 6.8% density detune beat, phase warping, two-source Young path-difference rings, polarization colour banding, sub-wavelength micro-fringes, held pointer lens, and click pulses.
KEEP VERBATIM: Line Density, Crossing Angle, Warp Strength, Color Phase; q1/q2 crossed rotations; 1.068 density detune beat; phaseWarp; Young two-source path difference; polarization palette banding; microFringes; held circular wave + click pulses; raw HDR display RGBA history in A/C; acesToneMap on writeTexture.
MECHANISM INTERROGATION:
  tactic 1 & 2 (deepen grating interferometry): pure sin(φ) gratings only produce diffuse 1st-order fringes; real multi-beam Ronchi / Fabry–Pérot transmission gratings obey the Airy transmittance 1 / (1 + F·sin²(Δφ/2)), sharpening bright constructive moiré superlattice contours as Line Density increases and brightening stationary-phase saddle caustics where local fringe gradient slows down.
  tactic 2 (optical physics — §12.2F Cauchy / chromatic grating dispersion): a physical line grating diffracts R (650 nm), G (550 nm), and B (450 nm) with wavelength-proportional phase dispersion Δφ_λ, splitting steep warped moiré saddles and held-lens zones into authentic spectral diffraction orders while unwarped nodal lines stay crisp.
ADD (2 native ideas):
  1. Fabry–Pérot multi-beam Airy finesse & stationary-phase moiré caustics — sharpens the crossed-grating difference phase into high-finesse multi-beam transmission fringes and highlights hyperbolic saddle caustics where the local moiré beat wavevector cancels.
  2. Tri-band spectral diffraction-order dispersion (§12.2F Cauchy / grating dispersion) — evaluates R/G/B grating interference across 650/550/450 nm phase offsets scaled by Warp Strength and pointer lens curvature so moiré fringes split into physical rainbow diffraction orders at high shear.
FORBID: replacing the crossed line gratings with Voronoi/raymarching, adding a spring cursor, ACES inside dataTextureA.
A PACKING: raw HDR display RGBA history in A/C (unchanged; acesToneMap on writeTexture).
```

---

## 3. liquid-v1

```
SHADER: liquid-v1
IDENTITY: clean baseline ambient capillary height-field liquid over the source image with persistent height/velocity/foam/coverage in raw A/C, ambient cross-waves, held pointer push, click wave rings, Beer tint, Fresnel, and caustics.
KEEP VERBATIM: Ambient Parallax, Foreground Motion, Depth Waver, Contrast (and their existing intensity / speed / scale / detail scalings); raw A/C (height, velocity, foam, coverage) packing; initialization at height 0.12; ambient + crossWave forcing; held pointer push + click rings; Beer absorption, Fresnel, caustics, acesToneMap on writeTexture.
MECHANISM INTERROGATION:
  tactic 1 & 3 (deepen wave stencil & wire unused readDepthTexture): laplacian is currently an axis-biased 5-point stencil, and sourceDepth (readDepthTexture) is loaded on the penultimate line only for writeDepthTexture while sliders named Ambient Parallax and Depth Waver never touch scene depth! Upgrading to the continuum-matched isotropic 9-point Laplacian (§12.2D) removes grid diamond artifacts on click rings, while coupling readDepthTexture into shallow-water wave shoaling makes ripples slow and steepen over foreground depth contours.
  tactic 2 (optical physics — §12.2F Snell vector refraction & dual-lobe specular glint): replacing the linear UV offset with true 3D Snell vector refraction refract(incident, normal, eta) with subtle water dispersion (η_R/η_G/η_B) and depth-scaled parallax — paired with a crisp raking sun/sky specular highlight gated by Contrast — gives the water surface genuine optical clarity.
ADD (2 native ideas):
  1. Isotropic 9-point wave Laplacian (§12.2D) & bathymetric scene-depth shoaling — adds diagonal neighbour taps so capillary and click rings propagate isotropically without X/Y grid facets, while foreground readDepthTexture ridges gently shoal wave phase speed and refract ripples around scene depth.
  2. Chromatic Snell vector refraction (§12.2F) with depth parallax & raking sun glint — traces 3D Snell refracted rays per RGB water index scaled by liquid height + scene depth parallax, topped with a sharp grazing water-meniscus sun highlight modulated by Contrast.
FORBID: ACES on dataTextureA (corrupts raw height/velocity/foam/coverage state), a spring cursor, changing param mappings.
A PACKING: raw (height, velocity, foam, coverage) in A/C (unchanged; acesToneMap on writeTexture only).
```

---

## 4. sim-sand-dunes

```
SHADER: sim-sand-dunes
IDENTITY: persistent desert dune height-field simulation storing (height, loose grains, downslope velocity, moisture) in raw A/C over the source image, with angle-of-repose slipface avalanches, windward ripples, moisture darkening, held sand deposition, and click impact craters.
KEEP VERBATIM: Gravity Strength, Wind Speed, Sand Viscosity, Erosion Rate; raw A/C (height, loose grains, downslope velocity, moisture); seed initialization; repose/avalanche/stoss/lee/slipface mechanics; windRipple + strata; dry/wet sand palette; held sand pour + click rings; aces on writeTexture only.
MECHANISM INTERROGATION:
  tactic 1 & 2 (aeolian dune physics one step further): loose * wind * (l.g - r.g) uses symmetric central differencing, whereas real desert saltation fetches loose sand from upwind stoss slopes and drops it in the sheltered recirculation wind-shadow pocket just leeward of sharp dune brinks (lap < 0, lee > 0), building asymmetric crescentic barchan crests and leeward slipfaces; foreground readDepthTexture silhouettes also cast sheltered wind-shadow sand drifts.
  tactic 5 & 7 (desert mineralogy & micro-facet optics): real wind-scoured troughs concentrate dark heavy-mineral magnetite/garnet lag while winnowed dry quartz crests sparkle with directional micro-facet sun glints (quenched where moisture binds damp sand).
ADD (2 native ideas):
  1. Upwind saltation fetch & brink-separation lee wind-shadow deposition — samples upwind loose sand along Wind Speed direction and traps saltating grains in separated leeward wind-shadow pockets behind sharp dune brinks (and readDepthTexture obstacles), sculpting crisp asymmetric dune crests.
  2. Heavy-mineral trough lag & dry-quartz micro-facet sun glints — segregates dark iron-garnet mineral lag into wind-eroded troughs/ripple valleys while dry sunlit quartz crests catch raking micro-grain specular sparkles suppressed by local moisture.
FORBID: ACES on dataTextureA (corrupts raw 4-field dune state), a spring cursor, changing param roles.
A PACKING: raw (height, loose grains, downslope velocity, moisture) in A/C (unchanged; aces on writeTexture only).
```

---

## 5. poincare-tiling (multipass: `poincare-tiling-map` + `poincare-tiling-layer`)

```
SHADER: poincare-tiling
IDENTITY: two-pass Physics Lab hyperbolic Poincaré disk tiling (`poincare-tiling-map` → dataA/dataC → `poincare-tiling-layer`) compositing a primary symmetry-folded hyperbolic disk mapping of the source image with a rotating Möbius secondary layer.
KEEP VERBATIM: 2-node multipass graph (`map` → `layer`); Curvature, Symmetry, Animation Speed, Tile Scale; cmul / cdiv / mobius helpers; discrete sector count n = max(3, floor(sym * 10) + 3); primary tiled source read in Pass 1 + secondary rotating Möbius layer composite in Pass 2.
MECHANISM INTERROGATION:
  floor & bug audit: both files paste the 13-binding header, omit aspect-ratio correction (stretching the disk into an ellipse), ignore pointer input despite "mouse-driven" in JSON, ignore bass/treble despite declared param audio mappings, output un-tonemapped RGB with hardcoded 1.0 alpha, and Pass 1 only folded Euclidean polar angle without hyperbolic geodesic circle inversions or true disk automorphisms (z - a)/(1 - conj(a)·z). Fixing bindings, aspect, audio/mouse wiring, ACES, and semantic alpha is the plumbing floor.
  tactic 1 & 3 (deepen hyperbolic geometry & promote A.a handoff): applying a true SU(1,1) Poincaré disk automorphism steered by orbit + held pointer followed by iterated hyperbolic geodesic circle inversions tiles the disk out to |z| → 1 into genuine {p, q} Escher-style hyperbolic polygons, while Pass 1's unused dataTextureA.a channel can hand off signed geodesic arc distance + reflection parity to Pass 2!
  tactic 2 (conformal Poincaré metric optics in Pass 2): Pass 2 reads base.rgb and packed geodesic arc/parity base.a from dataTextureC, layers a dual counter-rotating disk automorphism warped by hyperbolic-metric click waves, gilds polygon geodesic arcs scaled by the Poincaré conformal factor (1 - |z|²), and frames |z| > 1 with an obsidian-brass astrolabe horizon bezel.
ADD (2 native ideas):
  1. Iterated {p, q} hyperbolic geodesic circle-inversion tessellation & SU(1,1) disk automorphism (`poincare-tiling-map`) — transforms aspect-corrected disk coordinates by a true disk-preserving Möbius isometry (steered by time and held pointer) and iteratively inverts across orthogonal hyperbolic geodesic circles, packing tiled linear RGB in A.rgb and geodesic arc distance + reflection parity in A.a.
  2. Conformal (1 - |z|²) gilded geodesic arcs, hyperbolic-metric click ripples & astrolabe horizon bezel (`poincare-tiling-layer`) — reads Pass 1's geodesic distance/parity from C.a to render crisp conformal-metric polygon borders and alternating parity sheen, warps the secondary Tile Scale Möbius layer with Poincaré-metric click wavefronts, and frames the unit circle in a recessed astrolabe bezel with hyperbolic dome depth.
FORBID: changing the 2-node multipass graph topology, adding a spring cursor, tone-mapping Pass 1's handoff RGB before Pass 2 composites it.
A PACKING: Pass 1 writes linear tiled RGB + packed geodesic edge/parity in dataTextureA; Pass 2 reads dataTextureC, writes ACES display RGBA to writeTexture, hyperbolic dome relief to writeDepthTexture, and linear composite RGBA to dataTextureA.
```

---

## 6. cymatic-sand

```
SHADER: cymatic-sand
IDENTITY: damped Chladni soundboard simulation storing (sand density, transport velocity, resonant energy, strike memory) in raw A/C, where standing-wave plate modes gather bronze sand grains onto nodal lines while audio, held bow/pointer, and click strikes excite harmonics.
KEEP VERBATIM: Frequency Mode, Harmonic Mix, Grain Density, Audio Sensitivity; raw A/C (density, velocity, resonant energy, strike memory); seed initialization; chladni(p, n, m) modes w0/w1/w2, node mask, beatEnv; click strikes + held pointer; bronze grain + spectral resonance glow; aces on writeTexture only.
MECHANISM INTERROGATION:
  tactic 1 & 2 (deepen Chladni transport — §12.2D Continuity flux): currently sand is added/subtracted locally via nodePile - antinodeEject without conservative spatial drift down the acoustic radiation potential; evaluating the analytic plate-vibration gradient ∇(W²) and pairing it with neighbour flux transport (§12.2D) sweeps grains physically out of vibrating antinode bellies into sharp, steric-limited nodal ridges.
  tactic 3 & 5 (promote neighbour density gradient & real Chladni apparatus optics): l.r, r.r, t.r, b.r are already loaded every pixel — promoting (l.r - r.r, t.r - b.r) constructs a 3D heaped-sand ridge normal for raking bronze specular/diffuse shading over a brushed dark-brass soundboard plate (with clamped corner bolts and jumping Faraday grain glints in active antinodes, replacing binary salt-and-pepper noise).
ADD (2 native ideas):
  1. Acoustic radiation-gradient transport (-∇W²) & conservative neighbour grain flux (§12.2D Shallow-water / granular continuity) — computes the analytic Chladni vibrational energy gradient to advect sand conservatively from antinode bellies into crisp, steric-capped nodal ridges.
  2. 3D heaped nodal-ridge normals, brushed-brass soundboard & antinode saltation glints — shades sand piles in 3D relief from already-loaded neighbour densities over a dark brushed-brass Chladni plate with corner clamp nodes and shimmering airborne grains in vibrating antinodes.
FORBID: ACES on dataTextureA (corrupts raw 4-field Chladni state), a spring cursor, changing param mappings.
A PACKING: raw (density, velocity, resonant energy, strike memory) in A/C (unchanged; aces on writeTexture only).
```

---

## 7. ripple-tank (multipass: `ripple-tank-step` × 4, `ripple-tank-inject`, `ripple-tank-pass2`, `ripple-tank-pass3`)

```
SHADER: ripple-tank
IDENTITY: flagship 4-node / 7-pass Physics Lab dispersive water ripple tank (`step`×4 → `inject` → `pass2` capillary gather → `pass3` chromatic render) with held driven dipper, click rings, audio rain, controllable shore/wall reflection, caustics, and A-only `(height, velocity, foam, oscillator phase)` state.
KEEP VERBATIM: exact 4-node / 7-pass multipass graph (`writesDataB == false`); Wave Speed, Damping, Source Strength, Boundary Reflect; raw A/C (height, velocity, foam energy, oscillator phase); 13-tap isotropic wave Laplacian in step; held harmonic dipper + click splashes + 3-drop audio rain in inject; surface-tension dispersion in pass2; chromatic refraction + spectral phase + aces + state pass-through in pass3.
MECHANISM INTERROGATION:
  tactic 1 & 2 (PSSC ripple-tank wave physics — §12.2D Deep-water / bathymetric dispersion): ripple-tank.json declares "depth-aware", yet step ignores readDepthTexture and uses a hard height*wall clamp at edges that partially reflects even at Boundary Reflect = 0! Coupling readDepthTexture into shallow-water bathymetric wave speed c(x) makes waves refract and focus over submerged foreground depth shoals like classic PSSC acrylic tank lenses, while Rayleigh velocity-sponge absorption near the border gives true non-reflecting beaches at low Boundary Reflect and crisp mirror walls at 1.0 (plus branchless twin-harmonic meniscus wake in inject).
  tactic 2 & 8 (optical focal caustics & §12.2F Fresnel–Schlick + Beer–Lambert in pass2/pass3): pass3 currently computes caustic from abs(curvature), lighting defocusing concave troughs identically to focusing convex crests! Computing the 2D ray-sheet focal Jacobian det(I + d_f·D²h) (with diagonal taps in pass3) concentrates bright chromatic caustic cusps strictly under focusing crests while dimming defocused troughs, paired with Fresnel–Schlick sky reflection and Beer–Lambert turquoise water-depth extinction.
ADD (2 native ideas):
  1. Bathymetric scene-depth wave refraction (§12.2D Dispersion), Rayleigh sponge shore & sympathetic dipper harmonics (`step`, `inject`) — modulates local wave speed by readDepthTexture shoals so wavefronts bend around submerged scene depth, replaces edge height-clipping with velocity-damped Rayleigh shore absorption vs. wall reflection, and makes inject cleanly branchless with a twin-pin interference harmonic at high Source Strength.
  2. Ray-sheet Jacobian focal caustics (`det(I + d_f·D²h)`) & Fresnel–Schlick / Beer–Lambert tank optics (§12.2F) (`pass2`, `pass3`) — distinguishes focusing convex crests from defocusing concave troughs via the 2D Hessian Jacobian determinant to project authentic PSSC floor caustics through Beer–Lambert water absorption and Fresnel–Schlick grazing sky reflections.
FORBID: altering multipass.graph nodes/repeats/roles, writing dataTextureB, modifying state in pass3's dataTextureA commit, adding a spring cursor.
A PACKING: raw (height, velocity, foam energy, oscillator phase) across all 4 passes (unchanged; aces on writeTexture in pass3 only).
```

---

## 8. pixel-sand

```
SHADER: pixel-sand
IDENTITY: cellular-continuous granular sand automaton storing (density, vx, vy, kinetic energy) in raw A/C over the source image, with gravity fall, diagonal angle-of-repose rest, curl swirl, floor bounce, held pointer vortex/lift, click shock shelves, and warm-to-hot kinetic glow.
KEEP VERBATIM: Gravity, Particle Density, Curl Force, Bounce; raw A/C (density, vx, vy, kinetic energy); t < 0.12 seed; 6-neighbour loads (l, r, t, b, ul, ur); avalanche + sheet + diagRest + inflow/outflow transport; held pointer swirl/lift + click shelves; warm/hot/cool + kinetic sparkle; aces on writeTexture only.
MECHANISM INTERROGATION:
  bug & floor audit: Particle Density (`u.zoom_params.y`) was ONLY read during the first 0.12 s initialization — dragging the slider afterward had zero effect! Also `pixel-sand.json` claims "depth-aware" while `readDepthTexture` was never read, and `floor(time * 0.2)` caused a jarring 5-second full-screen grain-mask snap.
  tactic 1 & 2 (deepen granular physics — depth ledges & divergence-free curl): reading `readDepthTexture` at current and below pixels turns foreground depth silhouettes into physical 3D ledges where falling sand piles up, bounces (`Bounce`), and spills over shoulders, while replacing the unidirectional plane-wave `(cos, sin)` with a true divergence-free 2D streamfunction curl swirls airborne grains into genuine eddies.
  tactic 4 & 8 (live Particle Density hopper & §12.2F Blackbody shear incandescence): wiring `Particle Density` to a continuous top-edge hourglass sand emitters + steady-state grain supply makes the slider responsive at any time, while resting grains inherit subtle `readTexture` sand-art pigment and high-shear avalanching grains (`|∇v|` + `energy`) glow along a smooth Planckian blackbody ember curve without frame-quantized strobing.
ADD (2 native ideas):
  1. Scene-depth 3D collision ledges & divergence-free streamfunction curl eddies — collides falling grains with foreground `readDepthTexture` ledges (triggering restitution bounce and lateral avalanche spill) and upgrades `Curl Force` to an incompressible 2D streamfunction curl field.
  2. Live top-hopper `Particle Density` emitter, source-pigment sand & frictional shear blackbody (§12.2F) — continuously pours/regulates sand from top hopper streams according to `Particle Density`, tints settled sand strata with `readTexture` pigment, and heats high-shear avalanches along a smooth blackbody ember ramp (eliminating the 5-second `floor(time * 0.2)` strobe).
FORBID: ACES on dataTextureA (corrupts raw 4-field granular state), a spring cursor, changing param mappings.
A PACKING: raw (density, vx, vy, kinetic energy) in A/C (unchanged; aces on writeTexture only).
```

---

## 9. fire-smoke-volumetric-fog

```
SHADER: fire-smoke-volumetric-fog
IDENTITY: coupled Eulerian combustion & plume field storing (smoke density, flame temperature, soot, lateral momentum) in raw A/C over heat-shimmered scene input, composited through a 7-slice Beer–Lambert blackbody fire-and-smoke volume.
KEEP VERBATIM: Fire Intensity, Smoke Density, Turbulence, Color Temperature (saved params byte-exact); raw A/C (smoke density, temperature, soot, lateral momentum); buoyant rise + 4-neighbour diffusion + decay; held pointer torch + click fire rings; heat-refracted scene read; 7-layer Beer–Lambert fire + smoke volume; aces on writeTexture only.
MECHANISM INTERROGATION:
  floor & bug audit: (a) `writeDepthTexture` was completely missing! (b) `readDepthTexture` was unread despite "depth-aware" in JSON; (c) when mouse was not held (`zoom_config.w <= 0.5`), there was ZERO heat/smoke source anywhere, causing the entire effect to decay to a blank passthrough screen within 2 seconds; (d) `round(rise)` integer pixel snapping froze slow plumes; (e) `hash21(p + time * 2.0)` created TV-static snow across the 7 fog slices; (f) Slider 4 (`Color Temperature`, `zoom_params.w`) was wired only to turbulence instead of blackbody colour temperature!
  tactic 1 & 2 (§12.2D Boussinesq buoyancy + baroclinic vorticity): replacing integer `round(rise)` with sub-pixel 4-tap exact `textureLoad` bilinear advection driven by Boussinesq thermal buoyancy `(α·temp − β·soot)` and baroclinic torque `(e.y - w.y)` spins rising plumes into rolling mushroom-cap vortices, fed by a persistent bottom ember hearth + image-luma ignition pockets + hover/held torch.
  tactic 2 & 8 (§12.2F Henyey–Greenstein scatter + Blackbody temperature + depth occlusion): gating each of the 7 volumetric slices `z` against `readDepthTexture` occludes fog behind foreground objects, replaces TV-static slice hashes with smooth billowing fBM strata, scatters warm neighbour flame light through surrounding smoke via Henyey–Greenstein forward scatter, and maps `Color Temperature` across a true Planckian blackbody ramp (`deep coal crimson → amber → blue-white blowtorch`).
ADD (2 native ideas):
  1. Sub-pixel Boussinesq buoyant advection (§12.2D), baroclinic plume roll-up & persistent hearth ember bed — replaces integer-snapped `round(rise)` with exact 4-tap bilinear `dataTextureC` advection, adds horizontal thermal-gradient baroclinic vorticity to curl smoke edges, and seeds a live bottom ember bed + bright-luma hearth so flames and fog billow continuously even without mouse-down.
  2. Depth-occluded 7-slice volume, Henyey–Greenstein flame in-scattering (§12.2F) & Planckian `Color Temperature` blackbody (§12.2F) — tests volumetric slices against `readDepthTexture` (and writes `writeDepthTexture`), replaces frame-hash snow with coherent billowing strata, scatters internal flame glow into nearby smoke, and wires `Color Temperature` to a physical Planckian blackbody spectrum.
FORBID: ACES on dataTextureA (corrupts raw density/temp/soot/momentum state), omitting writeDepthTexture, frame-hash slice static, a spring cursor.
A PACKING: raw (smoke density, temperature, soot, lateral momentum) in A/C (unchanged; aces on writeTexture only).
```

---

## 10. optical-flow-dream (`optical-flow-estimate.wgsl`)

```
SHADER: optical-flow-dream
IDENTITY: canonical single-pass optical-flow dream field (`public/shaders/optical-flow-estimate.wgsl`) estimating temporal luma motion between live input and exact `dataTextureC` history to advect chromatic dream trails with held pointer vortices and click tear fronts.
KEEP VERBATIM: Flow Scale, Decay, Chroma Smear, Dream Mix; linear HDR dream RGB + semantic coverage alpha in A/C; temporal luma optical flow from readTexture vs exact dataTextureC; held pointer swirl + click tear fronts; RGB split along flow; directional hue glow; aces on writeTexture; flow-modulated writeDepthTexture.
MECHANISM INTERROGATION:
  tactic 1 (deepen optical-flow estimator — §12.2A Structure-tensor orientation): single-pixel 2-tap normal flow `-∇I · I_t / (|∇I|² + ε)` suffers from the aperture problem and half-pixel forward-difference chatter; building a 3×3 spatio-temporal Lucas–Kanade structure tensor `J = Σ [Ix², IxIy; IxIy, Iy²]` and `-Σ [IxIt, IyIt]` resolves true 2D corner/texture velocity and yields local edge coherence `coh` + tangent orientation without any new state!
  tactic 1 & 7 (deepen advection — §12.2D MacCormack sub-pixel advection & edge-tangent curl ribbons): `vec2<i32>((uv - flow) * res)` truncates sub-pixel flow to zero (freezing slow motion into blocky steps); replacing integer truncation with exact-`textureLoad` bilinear MacCormack predictor-corrector advection (clamped to the 4-tap neighbourhood extremum) and deflecting streamlines subtly along coherent edge tangents (`coh`) lets dream ribbons glide smoothly around foreground silhouettes with curved 3-channel chromatic dispersion.
ADD (2 native ideas):
  1. 3×3 regularized Lucas–Kanade spatio-temporal structure tensor (§12.2A) — solves the 2×2 windowed optical-flow tensor over `readTexture` and exact `dataTextureC` to eliminate single-pixel aperture chatter and extract local edge orientation + coherence `coh`.
  2. Sub-pixel clamped MacCormack dream advection (§12.2D) & edge-tangent curl deflection — replaces nearest-integer `advPx` snapping with exact-`textureLoad` bilinear predictor-corrector advection (extremum-clamped for HDR stability) and bends chromatic R/G/B dream trails smoothly along coherent scene contours.
FORBID: binding 13 (`historyTexture` — must stay canonical 13-binding single-pass), filtering sampler on `dataTextureC`, ACES inside `dataTextureA`, a spring cursor.
A PACKING: linear HDR dream RGB + semantic trail coverage in A/C (unchanged; aces on writeTexture only).
```
