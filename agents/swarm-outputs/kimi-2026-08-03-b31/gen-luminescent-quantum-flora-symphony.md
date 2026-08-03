# Changelog — gen-luminescent-quantum-flora-symphony (b31, optimizer)

## Critical bug fix
- Uniforms struct was already close to canonical but the shader only wrote
  `writeTexture` and used a hard-coded `1.0` alpha, no depth, no dataTextureA.
  Verified/locked the canonical 4-field struct (`config, zoom_config,
  zoom_params, ripples`) and the verbatim 13-binding header.
- Remapped mouse usage: was `u.zoom_config.yz * 2.0` (0..2 range) — now
  `(u.zoom_config.yz - 0.5) * 2.0` (centered scene plane, y=0 top, no flip).

## Geometry / features added
- **Smooth-union SDF scene (3D complexity)**: capsule stem + emissive core
  bulb + KIFS petal lattice, blended with polynomial `smin`; branchless
  material pick via `select` (stem/petal/core IDs).
- **2D tessellation layer**: hex-grid spore lattice (`hexBorder`) drifting
  over the backdrop, shimmer driven by treble and a real engine FFT bin
  (`extraBuffer[5..36]`, read-only, arrayLength-guarded).
- **Adaptive budget**: fold count 3..6 and march steps 40..72 both scale with
  Petal Complexity (LOD); raymarch epsilon grows with t; early exits on hit,
  spore saturation, and max distance.
- All 4 sliders LIVE: Petal Complexity → fold offset + fold count + step
  budget; Gravity Twist → localized swirl strength; Spore Density →
  volumetric spore accumulation + hex lattice brightness; Core Intensity →
  core emissive + Fresnel rim gain.
- Real depth (`1.0 - t/MAX_DIST` on hit, far-plane on miss), semantic
  luma-based alpha, ACES tonemap, `dataTextureA` written every frame
  (color + spore density in .w).

## Perf estimate (steps/px)
- March: 40–72 iterations (adaptive), each ~1 map() = 3 SDF primitives +
  3..6 cheap folds. Hit pixels add 6 extra map() calls for the normal.
- Roughly comparable to the old fixed 64-step loop at default slider values,
  with early exits typically cutting 30–50% of iterations on background px.

## Gate
- `wgsl_precommit_gate.py` — PASS (naga OK, bindgroup compatible, no
  extraBuffer violations). Lines: 103 → 192 (+89, within target).

## Rating prediction
- 7.5/10 — was a flat, unlit single-material march; now a shaded, layered,
  audio-reactive SDF bloom with a tessellated spore field and real depth.
