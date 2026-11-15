# Coordinator Review — gemini/wave-sand-ten (2026-11-15)

Idea cards and §12.1 mechanism interrogations were written in `BRIEFS.md` prior to any WGSL modification. Every numbered addition is marked in WGSL with a `// ── Idea n:` comment inside the existing main path. Saved `params` and `multipass` graph definitions were verified byte-exact against `HEAD` across all ten JSON definitions. Ten legacy pasted binding headers were migrated cleanly via `migrate_to_prelude.py` before idea implementation.

| Shader | Verdict | §12.2 Formulae Used | Why it passes |
|---|---|---|---|
| `gen-julia-set-classic` | **PASS** | *(Douady–Hubbard potential + Fatou cycle dynamics)* | Rotation-coherent `z / dz` shades 3D equipotential normals + binary external rays; period-2 orbital step tracking reveals chambered Fatou interior shells and petals. Raw HDR A/C and non-unit slider ranges preserved. |
| `gen-interference-moire-field` | **PASS** | Cauchy / grating dispersion (§12.2F) | Multi-beam Fabry–Pérot Airy finesse sharpens constructive moiré contours and stationary-phase saddle caustics; 650/550/450 nm phase dispersion splits high-shear fringes into diffraction orders. |
| `liquid-v1` | **PASS** | Isotropic 9-point Laplacian (§12.2D); Snell vector refraction (§12.2F) | 9-point wave stencil removes diamond bias while `readDepthTexture` shoals ripples; 3D chromatic Snell refraction with depth parallax + `Contrast`-controlled sun glint deepen water optics. Raw 4-field A/C preserved. |
| `sim-sand-dunes` | **PASS** | *(Aeolian upwind saltation + mineral lag)* | Upwind loose-grain fetch + lee brink / depth wind-shadow pocket build asymmetric dune crests; magnetite trough lag and dry-quartz micro-facet glints (quenched by moisture) ground desert optics. Raw 4-field A/C preserved. |
| `poincare-tiling` (2 passes) | **PASS** | *(Hyperbolic `{p, q}` circle inversion + conformal Poincaré metric)* | Pass 1 applies aspect-true SU(1,1) disk automorphisms + iterated orthogonal geodesic circle inversions, handing off arc distance + parity in `A.a`; Pass 2 renders conformal `(1 - |z|²)` gilded arcs, Poincaré-metric click waves, and an astrolabe bezel. |
| `cymatic-sand` | **PASS** | Shallow-water / granular continuity flux (§12.2D) | Analytic `-∇(W²)` radiation gradient sweeps grains conservatively from antinodes into steric-capped nodal ridges; neighbour density gradients shade 3D bronze ridges over a lathe-brushed brass soundboard. Raw 4-field A/C preserved. |
| `ripple-tank` (4 passes) | **PASS** | Deep-water / bathymetric dispersion (§12.2D); Fresnel–Schlick + Beer–Lambert (§12.2F) | `step` couples `readDepthTexture` into bathymetric wave refraction + Rayleigh sponge shore; `inject` is branchless with a twin-pin Young dipper harmonic; `pass2` uses 9-tap capillary curvature; `pass3` projects ray-sheet Jacobian floor caustics (`det(I + d_f·D²h)`) through Beer–Lambert / Fresnel tank water while committing raw state unchanged. |
| `pixel-sand` | **PASS** | Blackbody thermal emission (§12.2F) | Foreground `readDepthTexture` silhouettes form 3D bounce/spill ledges and `Curl Force` uses an incompressible streamfunction curl; previously post-init-dead `Particle Density` drives live top-hopper sand streams, eliminating the 5 s `floor(time * 0.2)` strobe. Raw 4-field A/C preserved. |
| `fire-smoke-volumetric-fog` | **PASS** | Boussinesq buoyancy (§12.2D); Henyey–Greenstein + Blackbody (§12.2F) | Exact 4-tap bilinear Boussinesq advection + baroclinic `(e.y - w.y)` roll-up + live bottom ember hearth fix idle fade-to-blank and integer `round(rise)` freezing; 7 slices are occluded by `readDepthTexture`, write `writeDepthTexture`, scatter flame light via HG phase, and wire `Color Temperature` to a Planckian ramp. Raw 4-field A/C preserved. |
| `optical-flow-dream` | **PASS** | Structure-tensor orientation (§12.2A); MacCormack advection (§12.2D) | 3×3 regularized Lucas–Kanade tensor over `readTexture` and exact `dataTextureC` resolves aperture chatter and extracts edge coherence `coh`; extremum-clamped bilinear MacCormack advection eliminates integer `advPx` snapping and bends chromatic dream trails along contours. |

### §9 & §12.7 Checklist Verification

- [x] `BRIEFS.md` written before WGSL edits and includes §12.1 mechanism interrogations
- [x] Each numbered idea is pointable in WGSL (`// ── Idea n:`)
- [x] `KEEP VERBATIM` holds on all 10 shaders / 14 WGSL files (modes, kernels, multipass graphs, saved `params` byte-exact)
- [x] Diffs are substantive effect mechanisms, not header/ACES/spring boilerplate
- [x] No §12.2 formula row appears on more than two files across the batch
- [x] Each formula consumes quantities the file already had — no new solver, binding, or spring
- [x] A packing matches how C is read on all 14 WGSL files (raw sim state un-tonemapped; linear HDR history un-tonemapped; ACES on `writeTexture` only)
- [x] No `fwidth`/`dpdx`, no unguarded `pow` base, no negative input into ACES, no reserved keywords
- [x] Naga 14/14, `wgsl_precommit_gate.py` 14/14, `audit_extrabuffer` 0 new violations, `audit_dead_sliders` 0 dead sliders

Real-GPU visual QA and thumbnail refresh remain external (headless Cloud VM has no hardware GPU).
