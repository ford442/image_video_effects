# Coordinator Review — gemini/circuit-void-ten (2026-11-15)

Idea cards and §12.1 mechanism interrogations were written in `BRIEFS.md` prior to any WGSL modification. Every numbered addition is marked in WGSL with a `// ── Idea n:` comment inside the existing main path. Saved `params` were verified byte-exact across all ten JSON definitions. Six legacy pasted binding blocks were migrated cleanly via `migrate_to_prelude.py` before idea implementation.

| Shader | Verdict | §12.2 Formulae Used | Why it passes |
|---|---|---|---|
| `circuit-breaker` | **PASS** | Schmitt-trigger lock (§12.2B) | Annular via pads and 45°-routed traces consume existing `gridUV` and `(edgeX, edgeY)`. Breaker latch uses `A.a`/`C.a` hysteresis to open-circuit overloaded cells. No spring. |
| `aerogel-smoke` | **PASS** | Vorticity confinement (§12.2D); Beer–Lambert (§12.2F) | Sub-pixel exact `stateAt` advection fixes `round()` stalling; curl consumes existing neighbour velocities; dichroic extinction couples directly to `Blue Scatter`. Raw A/C preserved. |
| `double-exposure-hdr` | **PASS** | Halation (§12.2A) | Shadow-silhouette emulsion reserve keys Plate 2 into Plate 1 shadows; halation reuses the outer ring of the existing 12-tap bloom loop with core bleach before ACES. |
| `voxel-depth-sort` | **PASS** | *(domain geometry + C inertia)* | Swept 3D prism shaft adds X/Y isometric side walls inside block gaps; upslope neighbour height casts step-shadows; `C.x` gives column settle. Existing `extraBuffer[133..138]` spring kept untouched. |
| `double-exposure-zoom` | **PASS** | Cauchy dispersion (§12.2F) | Radial 3-tap shutter-zoom blur + Cauchy scale radiate from `mouse`; previously unwired `edgeMask` now gates Plate 2 clamped borders with a warm film-rebate edge. |
| `magma-fissure` | **PASS** | Isotropic 9-point Laplacian (§12.2D) | 9-point stencil removes axial crack bias; $T^4$ cooling + `(flow, perpFlow)` joints fracture crust into basalt plates with ember seams; buoyant `-y` haze. `[newHeat, 0, 0, 1]` preserved. |
| `cross-conv-mouse-bilateral` | **PASS** | Drying (§12.2C) | Linear painted strokes persist and dry in `dataTextureC` (O(1) fast-path preserved when outside brush); 7×7 bilateral range weight now respects chroma-opponent and depth edges. 3 saved params untouched. |
| `gen-prismatic-serpent-river` | **PASS** | Fresnel–Schlick (§12.2F) | Counter-phased companion strand weaves over/under with contact shadows; signed `laneY - slither` normal bends scales into V-chevrons and adds Fresnel flank sheen. |
| `aurora-rift-2` | **PASS** | *(auroral stopping physics)* | Asymmetric lower stopping edge + upward ray tail produce vertical $\text{N}_2^+$ → O-green → O-red altitude spectrum; `cos(foldPhase)` brightens tangent pleats; `curtainCoordinate` + `Depth Weight` mask foreground silhouettes. |
| `gen-synaptic-void-weaver` | **PASS** | Orbit trap (§12.2E); Step-count AO (§12.2E) | `map().y` now carries `smin` soma junctions + `p.xz` orbit trap from the existing IFS loop; 5-tap SDF AO carves fractal folds; dead `vec4(0.0)` A write replaced with ACES refractory trail. |

### §9 & §12.7 Checklist Verification

- [x] `BRIEFS.md` written before WGSL edits and includes §12.1 mechanism interrogations
- [x] Each numbered idea is pointable in WGSL (`// ── Idea n:`)
- [x] `KEEP VERBATIM` holds on all 10 files (modes, kernels, saved `params` byte-exact)
- [x] Diffs are substantive effect mechanisms, not header/ACES/spring boilerplate
- [x] Every §12.2 formula row used appears **at most once** across the entire batch (max allowed: 2)
- [x] Each formula consumes quantities the file already had — no new solver, binding, or spring
- [x] A packing matches how C is read on all 10 files (raw fields un-tonemapped; linear canvas un-tonemapped; display history ACES-mapped)
- [x] No `fwidth`/`dpdx`, no unguarded `pow` base, no negative input into ACES
- [x] Naga 10/10, `wgsl_precommit_gate.py` 10/10, `audit_extrabuffer` 0 violations, `audit_dead_sliders` 0 dead sliders

Real-GPU visual QA and thumbnail refresh remain external (headless Cloud VM has no hardware GPU).
