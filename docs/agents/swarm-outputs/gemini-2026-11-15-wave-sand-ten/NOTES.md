# Notes — gemini/wave-sand-ten (2026-11-15)

Idea cards and §12.1 mechanism interrogations were written first in `BRIEFS.md`. Saved `params` (ids, names, defaults, min/max/step, mappings, audio fields) and `multipass` graph definitions are byte-exact across all ten JSON definitions. Ten legacy pasted binding headers (`sim-sand-dunes.wgsl`, `poincare-tiling-map.wgsl`, `poincare-tiling-layer.wgsl`, `cymatic-sand.wgsl`, `ripple-tank-inject.wgsl`, `ripple-tank-pass2.wgsl`, `ripple-tank-pass3.wgsl`, `pixel-sand.wgsl`, `fire-smoke-volumetric-fog.wgsl`, `optical-flow-estimate.wgsl`) were migrated first via `python3 scripts/migrate_to_prelude.py --files ...`; that swap is infrastructure and is not counted toward any Idea Card.

No `extraBuffer[133..138]` spring was added to any file.

**§12.2 formulae newly applied (each appears at most once across the batch, except Blackbody on the two genuinely thermal shaders):**
- `gen-interference-moire-field`: Cauchy / grating spectral dispersion (§12.2F)
- `liquid-v1`: Isotropic 9-point Laplacian (§12.2D); Snell vector refraction (§12.2F)
- `cymatic-sand`: Shallow-water / granular continuity flux (§12.2D)
- `ripple-tank`: Deep-water / bathymetric dispersion (§12.2D); Fresnel–Schlick + Beer–Lambert water optics (§12.2F)
- `pixel-sand`: Blackbody thermal emission (§12.2F)
- `fire-smoke-volumetric-fog`: Boussinesq buoyancy (§12.2D); Henyey–Greenstein forward scatter (§12.2F); Blackbody thermal emission (§12.2F)
- `optical-flow-dream`: Structure-tensor orientation (§12.2A); MacCormack advection (§12.2D)

---

## gen-julia-set-classic

Kept: `C Real`, `C Imaginary`, `Zoom`, `Iterations` (all non-unit slider ranges byte-exact); held `mouseC` mix; `clickWarp`; `z² + c` iteration; spiral orbit trap (`Idea 1`); pseudo-3D orbit twist (`Idea 2`); `log|z|` stripe coloring; exterior distance estimate `deEdge`; raw HDR display RGBA history in A/C; `acesToneMap` on `writeTexture`.
In the diff: Douady–Hubbard complex-potential 3D normal & binary external rays (`// ── Idea 3`) keep `dz` rotation-coherent with the orbit twist and evaluate `z / dz` to shade exterior equipotential contours with 3D specular/diffuse relief and subtle binary-decomposition external rays. Fatou interior attracting-cycle convergence shells & basin petals (`// ── Idea 4`) track orbital period-2 contraction `min(|z - zPrev|, |z - zPrev2|)` and phase inside the existing loop so filled Fatou basins bloom with chambered Boettcher shells and 3-fold petal geometry.
A packing: raw HDR display RGBA history in A/C (unchanged; `acesToneMap` on `writeTexture`).

## gen-interference-moire-field

Kept: `Line Density`, `Crossing Angle`, `Warp Strength`, `Color Phase`; crossed `q1`/`q2` rotations; 6.8% density detune beat; `phaseWarp`; two-source Young path-difference rings; polarization banding (`Idea 1`); sub-wavelength micro-fringes (`Idea 2`); held circular wave + click pulses; raw HDR display RGBA history in A/C; `acesToneMap` on `writeTexture`.
In the diff: Fabry–Pérot multi-beam Airy finesse & stationary-phase saddle caustics (`// ── Idea 3`) sharpen crossed-grating transmission via `1 / (1 + F·sin²(Δφ/2))` and illuminate hyperbolic moiré saddle caustics where local beat wavevectors cancel. Spectral diffraction-order dispersion (`// ── Idea 4`, §12.2F Cauchy / grating dispersion) evaluates 650/550/450 nm phase dispersion scaled by `Warp Strength` and pointer lens curvature so warped moiré fringes split into physical diffraction orders.
A packing: raw HDR display RGBA history in A/C (unchanged; `acesToneMap` on `writeTexture`).

## liquid-v1

Kept: `Ambient Parallax`, `Foreground Motion`, `Depth Waver`, `Contrast` and their existing `intensity` / `speed` / `scale` / `detail` scalings; raw `(height, velocity, foam, coverage)` in A/C; `0.12` height initialization; `ambient` + `crossWave` forcing; held pointer push + click rings; Beer absorption, Fresnel, caustics, `acesToneMap` on `writeTexture`.
In the diff: isotropic 9-point wave Laplacian & bathymetric scene-depth shoaling (`// ── Idea 1`, §12.2D) add the four diagonal `dataTextureC` taps to remove X/Y diamond bias on ripples and couple `readDepthTexture` into shallow-water wave shoaling and phase modulation. Chromatic Snell vector refraction with depth parallax & raking sun glint (`// ── Idea 2`, §12.2F) computes 3D Snell refracted lateral rays across RGB water indices (`0.756 / 0.748 / 0.738`) scaled by water height + foreground scene depth, topped with a sharp sun highlight controlled by `Contrast`.
A packing: raw `(height, velocity, foam, coverage)` in A/C (unchanged; `acesToneMap` on `writeTexture` only).

## sim-sand-dunes

Kept: `Gravity Strength`, `Wind Speed`, `Sand Viscosity`, `Erosion Rate`; raw `(height, loose grains, downslope velocity, moisture)` in A/C; seed initialization; repose/avalanche/stoss/lee/slipface mechanics; `windRipple` + `strata`; dry/wet sand palette; held sand deposition + click rings; `aces` on `writeTexture` only.
In the diff: upwind saltation fetch & brink-separation lee wind-shadow deposition (`// ── Idea 3`) sample upwind loose grains along `windSign` and trap saltating sand in sheltered leeward wind-shadow pockets behind sharp dune brinks and foreground `readDepthTexture` silhouettes. Heavy-mineral magnetite trough lag & dry-quartz micro-facet glints (`// ── Idea 4`) concentrate dark iron-garnet mineral lag into wind-scoured troughs while dry sunlit stoss crests catch raking micro-grain specular glints quenched by `moisture`.
A packing: raw `(height, loose grains, downslope velocity, moisture)` in A/C (unchanged; `aces` on `writeTexture` only).

## poincare-tiling (multipass: `poincare-tiling-map` + `poincare-tiling-layer`)

Kept: 2-node multipass graph (`map` → `layer`); `Curvature`, `Symmetry`, `Animation Speed`, `Tile Scale`; `cmul` / `cdiv` / `mobius` complex arithmetic; discrete sector count `max(3, floor(sym * 10) + 3)`; primary tiled source sample in Pass 1 + secondary rotating Möbius layer composite in Pass 2.
Floor fixes (not counted as ideas): migrated pasted headers to `_prelude.wgsl`, corrected aspect ratio so the Poincaré disk is circular rather than stretched, wired pointer (`zoom_config.yz` / `.w`) and declared `bass`/`treble`/`overall` audio bands, added `acesToneMap` and semantic alpha.
In the diff: iterated `{p, q}` hyperbolic geodesic circle-inversion tessellation & SU(1,1) disk automorphism (`// ── Idea 1`, `poincare-tiling-map.wgsl`) transform disk coordinates via `(z - a) / (1 - conj(a)·z)` steered by orbit + held pointer and iterate Coxeter sector folding + orthogonal geodesic circle inversions out to `|z| → 1`, packing geodesic arc distance and reflection parity into `dataTextureA.a`. Conformal `(1 - |z|²)` gilded geodesic arcs, hyperbolic-metric click waves & astrolabe horizon bezel (`// ── Idea 2`, `poincare-tiling-layer.wgsl`) unpack `C.a` to render conformal-width polygon arcs and parity facet tints, propagate Poincaré-metric click wavefronts across the counter-rotating secondary Möbius layer, and frame `|z| > 1` in a recessed astrolabe bezel with dome depth.
A packing: Pass 1 writes linear tiled RGB + packed geodesic edge/parity in `dataTextureA`; Pass 2 writes linear composite RGBA to `dataTextureA` and `acesToneMap` RGBA to `writeTexture`.

## cymatic-sand

Kept: `Frequency Mode`, `Harmonic Mix`, `Grain Density`, `Audio Sensitivity`; raw `(density, radial velocity, resonant energy, strike memory)` in A/C; seed initialization; `chladni(p, n, m)` modes `w0`/`w1`/`w2`, `node` mask, `beatEnv`; click strikes + held pointer; bronze grain + spectral resonance glow; `aces` on `writeTexture` only.
In the diff: acoustic radiation-gradient transport & conservative neighbour grain flux (`// ── Idea 3`, §12.2D) evaluate the analytic plate-vibration gradient `-∇(W²)` to sweep sand conservatively out of vibrating antinode bellies into steric-capped nodal ridges. 3D heaped nodal-ridge normals, brushed-brass soundboard & antinode saltation glints (`// ── Idea 4`) promote already-loaded neighbour densities `(l.r - r.r, t.r - b.r)` into 3D sunlit bronze ridge normals over a lathe-brushed dark-brass Chladni soundboard with corner clamp bolts and jumping antinode grain glints.
A packing: raw `(density, radial velocity, resonant energy, strike memory)` in A/C (unchanged; `aces` on `writeTexture` only).

## ripple-tank (multipass: `ripple-tank-step` × 4, `ripple-tank-inject`, `ripple-tank-pass2`, `ripple-tank-pass3`)

Kept: exact 4-node / 7-pass multipass graph (`writesDataB == false`); `Wave Speed`, `Damping`, `Source Strength`, `Boundary Reflect`; raw `(height, velocity, foam energy, oscillator phase)` in A/C; 13-tap isotropic wave Laplacian in `step`; held harmonic dipper + click splashes + 3-drop audio rain in `inject`; surface-tension capillary refinement in `pass2`; chromatic refraction + spectral phase + `aces` + unchanged state pass-through in `pass3`.
In the diff: bathymetric scene-depth wave shoaling, Rayleigh sponge shore & sympathetic twin-dipper harmonics (`// ── Idea 1`, §12.2D Dispersion, in `step` + `inject`) modulate wave speed by `readDepthTexture` shoals (`c ∝ sqrt(h_b)`), replace hard edge clipping with Rayleigh velocity-sponge beach absorption vs. mirror wall reflection, and make `inject` branchless with a twin-pin Young interference harmonic at high `Source Strength` (plus 9-tap isotropic capillary curvature in `pass2`). Ray-sheet Jacobian focal caustics & Fresnel–Schlick / Beer–Lambert tank optics (`// ── Idea 2`, §12.2F, in `pass3`) evaluate the 2D Hessian determinant `det(I + d_f·D²h)` per RGB focal plane so convex crests project bright chromatic floor caustics while concave troughs dim, paired with Beer–Lambert turquoise water extinction and Fresnel–Schlick sky reflection.
A packing: raw `(height, velocity, foam energy, oscillator phase)` across all 4 passes (unchanged; `aces` on `writeTexture` in `pass3` only).

## pixel-sand

Kept: `Gravity`, `Particle Density`, `Curl Force`, `Bounce`; raw `(density, vx, vy, kinetic energy)` in A/C; `t < 0.12` seed; 6-neighbour loads (`l, r, t, b, ul, ur`); avalanche + sheet + `diagRest` + inflow/outflow transport; held pointer swirl/lift + click shelves; kinetic sparkle; `aces` on `writeTexture` only.
In the diff: scene-depth 3D collision ledges & divergence-free streamfunction curl (`// ── Idea 3`) collide falling grains with foreground `readDepthTexture` silhouettes (triggering restitution `Bounce` and lateral slope spill) and upgrade `Curl Force` to an incompressible 2D streamfunction curl field. Live top-hopper `Particle Density` emitter, source-pigment sand & frictional shear blackbody (`// ── Idea 4`, §12.2F) wire `Particle Density` (`u.zoom_params.y`, previously dead after `0.12 s`) to continuous top hourglass streams, tint settled sand with `readTexture` pigment, heat high-shear avalanches (`|∇v|`) along a smooth blackbody ramp, and remove the 5-second `floor(time * 0.2)` grain strobe.
A packing: raw `(density, vx, vy, kinetic energy)` in A/C (unchanged; `aces` on `writeTexture` only).

## fire-smoke-volumetric-fog

Kept: `Fire Intensity`, `Smoke Density`, `Turbulence`, `Color Temperature` (saved params byte-exact; aligned stale `x-meta.upgrade.params` names to match); raw `(smoke density, temperature, soot, lateral momentum)` in A/C; buoyant rise + 4-neighbour diffusion + decay; held pointer torch + click fire rings; heat-refracted scene read; 7-layer Beer–Lambert fire + smoke volume; `aces` on `writeTexture` only.
In the diff: sub-pixel Boussinesq buoyant advection, baroclinic plume roll-up & persistent hearth ember bed (`// ── Idea 1`, §12.2D) replace integer-snapped `round(rise)` with exact 4-tap bilinear `dataTextureC` advection, add horizontal thermal-gradient `(e.y - w.y)` baroclinic torque to curl smoke flanks, and feed a live bottom ember hearth + bright-luma ignition pockets so fire and fog billow continuously without requiring mouse-down. Depth-occluded 7-slice volume, Henyey–Greenstein flame in-scattering & Planckian `Color Temperature` blackbody (`// ── Idea 2`, §12.2F) gate volumetric slices against `readDepthTexture` (and add the missing `writeDepthTexture` write), replace frame-hash TV snow with smooth billowing fBM strata, scatter internal flame radiance through smoke via Henyey–Greenstein phase, and wire `Color Temperature` (`u.zoom_params.w`) to a coal-to-blowtorch Planckian ramp.
A packing: raw `(smoke density, temperature, soot, lateral momentum)` in A/C (unchanged; `aces` on `writeTexture` only).

## optical-flow-dream (`optical-flow-estimate.wgsl`)

Kept: `Flow Scale`, `Decay`, `Chroma Smear`, `Dream Mix`; linear HDR dream RGB + semantic trail coverage in A/C; canonical 13-binding single-pass path (no binding 13); temporal luma optical flow from `readTexture` vs exact `dataTextureC`; held pointer swirl + click tear fronts; RGB split along flow; directional hue glow; `aces` on `writeTexture`; flow-modulated `writeDepthTexture`.
In the diff: 3×3 regularized Lucas–Kanade spatio-temporal structure tensor (`// ── Idea 1`, §12.2A) solves the windowed 2×2 optical-flow system over `readTexture` and exact `dataTextureC` to resolve single-pixel aperture chatter and extract local edge orientation + coherence `coh`. Sub-pixel clamped MacCormack dream advection & edge-tangent curl deflection (`// ── Idea 2`, §12.2D) replace integer `advPx` truncation with exact-`textureLoad` bilinear predictor-corrector advection (clamped to the 4-tap neighbourhood box for HDR stability) and guide chromatic R/G/B dream ribbons smoothly along coherent scene contours.
A packing: linear HDR dream RGB + semantic trail coverage in A/C (unchanged; `aces` on `writeTexture` only).
