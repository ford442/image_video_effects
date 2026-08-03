# Changelog — gen-radiant-cyber-bismuth-nebula-colossus (b31, optimizer)

## Critical bug fix
- Uniforms struct was already canonical; locked the verbatim 13-binding
  header and 4-field struct. The real bugs were contractual: shader only
  wrote `writeTexture` (no depth, no dataTextureA), hard-coded alpha 1.0,
  and had TWO DEAD SLIDERS: Nebula Density (`zoom_params.y`) and
  Iridiscent Shift (`zoom_params.w`) were declared in the JSON but never
  read. Both are now live (below). Mouse was `yz * 2.0` (0..2) — recentered
  to `(yz - 0.5) * 2.0`, y=0 top, no flip.

## Geometry / features added
- **3D complexity**: bismuth hopper-crystal octahedra (`sdOctahedron`)
  smooth-unioned into the IFS-folded box lattice — the stepped-crystal look
  bismuth is known for. Fold count is LOD-adaptive (4..6) with Fold Scale.
- **2D complexity**: kaleidoscopic 6-fold symmetry (`kaleido`) star field
  via hashed cell stars, plus a deep-space gradient backdrop.
- **Volumetric nebula**: per-step density accumulation along the march with
  saturating early exit; colored haze modulated by mids and a real engine
  FFT bin (`extraBuffer[5..36]`, read-only, arrayLength-guarded).
- **Thin-film iridescence**: cosine palette phased by Iridiscent Shift with
  a Fresnel-driven hue flip at grazing angles.
- **Soft shadows**: 8-tap LOD shadow ray toward the key light, hit pixels
  only. Mouse orbits the camera; mouse-down dollies into the storm.
- Adaptive march steps 64..96 with Nebula Density; epsilon grows with t;
  early exits on hit / nebula saturation / max distance.
- Real depth, semantic luma alpha, ACES tonemap, `dataTextureA` = color +
  nebula density (.w), written every frame.

## Slider wiring (all LIVE)
- x Fold Scale → IFS offset scale + fold-count LOD
- y Nebula Density → volumetric accumulation rate + star brightness + step budget
- z Audio Reactivity → fold wobble, emissive gain, nebula/star audio gain
- w Iridiscent Shift → thin-film palette phase

## Perf estimate (steps/px)
- March: 64–96 iterations, each 1 map() = 4..6 folds + 2 primitive evals.
- Hits add 6 map() calls (normal) + 8 (shadow). Early exits typically cut
  30–40% of iterations on miss pixels. ~1.4× the old fixed-100 loop at
  defaults, with substantially more geometry per step.

## Gate
- `wgsl_precommit_gate.py` — PASS (naga OK, bindgroup compatible, no
  extraBuffer violations). Lines: 109 → 177 (+68, within target).

## Rating prediction
- 8/10 — dead-slider contract fixed; layered lattice + crystals + volumetric
  storm + shadows make it read as a true colossus instead of a flat fold toy.
