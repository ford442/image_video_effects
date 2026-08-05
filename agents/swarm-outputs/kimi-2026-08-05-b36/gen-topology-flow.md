# gen-topology-flow — Visualist upgrade (Batch 36, tracker #327)

202 → 265 lines (+63). Gate: **PASS** (naga OK, bindgroup compatible, 0 extraBuffer violations).

## What changed

**Lighting (new):**
- Relief lighting from the Morse gradient: surface normal
  `normalize(vec3(-grad*0.12, 1, ...))` lit by a warm afternoon key
  (1.25, 1.02, 0.78) + cool sky fill (0.28, 0.48, 0.95) — two temperatures.
- Split-toned palette: abyssal indigo valleys → verdant mids → ember-gold peaks
  (keeps the original blue→green→red soul, refined into cool-shadow/warm-highlight
  harmony).

**HDR / grading (new):**
- Flow lines are now HDR energy: color up to ~1.7+ × bass charge, mix cap raised
  to 0.6 — bloom-ready above 1.0.
- Critical points became HDR emitters: peaks +gold beacon (≤ ~2.6 with treble),
  saddles +warm gold hinge, valleys deep indigo sink with cool treble charge.
- ACES tone map applied for presentation only; `dataTextureA` stores the HDR
  history (clamped to 4.0 — fixes the original unbounded
  `0.3/(1-0.98) ≈ 15×` feedback fixed-point).

**Atmosphere (new):** cool haze pooling in valleys
(`smoothstep(0.45,0,h)`, slow drifting tint) — atmospheric depth on a 2D field.

**Audio (new):** bass → trail persistence + flow-line charge; mids → flow speed
× (1+mids*0.45) and exposure; treble → critical-point sparkle; guarded FFT bins
1–8 → contour-line shimmer trace. No hash-based fake spectrum.

**Mouse (new, bounded):** gaussian stir bump at cursor
(`exp(-d²*5) ≤ 1`, spatially local) + soft lantern glow, click-amplified
(finite, guarded by mouseDown). Mouse y used top-down, no flip.

**Fixes:**
- Added the mandatory resolution bounds guard (was missing entirely).
- Alpha: was hardcoded 1.0 → semantic ink/energy coverage
  `clamp(0.72 + 0.28*energy, 0, 1)` where energy = flow + critical + click stir.
- Depth kept relief-based and clamped to [0,1]: peaks = 1.0 (near), valleys = 0.
- `normalize(grad)` epsilon-guarded against the zero-gradient critical points
  (was potential NaN exactly where criticals are detected).

## Preserved
Canonical 13-binding header, Uniforms struct fields, heightField/gradient/
Laplacian/critical-detection core, particle streamline advection, contour lines,
trail feedback. All 4 sliders live in updatedParams index order (x=flow speed,
y=complexity, z=particle density, w=trail persistence). JSON: only `features`
array populated (additive); `updatedParams` byte-exact.

## Perf estimate
Dominant cost unchanged (up to 300 particles × 20 steps × gradient). Additions
are O(1) per pixel (one textureLoad, a few exp/smoothstep). ≈ +1–2% GPU cost.
