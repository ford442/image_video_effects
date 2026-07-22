# emergent-calligraphic-weave — Upgrade Notes (Kimi)

**Role:** Visualist
**Date:** 2026-07-22
**Shader:** `public/shaders/emergent-calligraphic-weave.wgsl`
**Definition:** `shader_definitions/generative/emergent-calligraphic-weave.json`

## Key Changes

1. **Removed generic `applyGenerativePrimaryControls` boilerplate.** The old
   intensity/speed-pulse/contrast helper no longer wraps the final color; all
   four sliders now drive real brush constants of this shader's algorithm.
2. **Slider rewiring (ids/defaults/mapping unchanged — preset contract kept):**
   - `zoom_params.x` Field Complexity → curl-field frequency (`fieldFreq` 1.2–5.5)
     **and** stroke width (`strokeWidth` 0.022→0.006; complex field = finer strokes).
   - `zoom_params.y` Stroke Persistence → ink viscosity / temporal decay
     (`viscosity` 0.78–0.97 + mids) **and** dry-brush threshold
     (`dryThresh` 0.30–0.52; wetter ink = less dry-brush).
   - `zoom_params.z` Pattern Coherence → coherence feedback gain (0.005–0.14),
     encouraging larger connected stroke structures.
   - `zoom_params.w` Field Chaos → turbulence amplitude (`chaosAmp` 0.05–1.4)
     injected into the orientation field.
3. **Curl-noise stroke direction field.** Added `vnoise()` (lattice-interpolated
   hash12) and `curlField()` — a divergence-free field from the perpendicular
   gradient of a drifting scalar potential. The base stroke direction is bent
   along this flow (`curlWeight` scaled by Field Complexity), so strokes sweep
   like brushed calligraphy instead of lying on a static hash field. Mouse
   influence still overrides the flowed angle near the brush.
4. **Dry-brush edge sparkle.** Treble-driven (`plasmaBuffer[0].z`) ink-grain
   sizzle, gated by `step(1.0 - treble*0.45, sparkleGrain)` and masked by
   `edgeMask * dryBrush` so it only fires on dry stroke edges. Feeds both the
   stroke accumulator (`+ sparkle*0.15`) and the final color as a warm
   paper-grain glint (`+ vec3(0.85,0.8,0.65) * sparkle*0.6`), plus a small
   alpha contribution.
5. **Preserved core algorithm & soul:** Bézier stroke sampling, paper grain /
   absorption from depth, fiber mask, viscosity flow + capillary bleed, brush
   temperature evaporation, treble splatter, sumi-e warm/cool palette, edge
   yellowing, chromatic aberration, ACES tone map — all intact. Edge detection
   was hoisted earlier so both ink flow and sparkle share it.

## Line Delta

- Before: 160 lines → After: **215 lines** (**+55**, within the +50 to +90 target; 210–250 range ✓)

## Validation

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/emergent-calligraphic-weave.wgsl`
  → **exit 0, naga OK, bindgroup compatible, 0 warnings**
- JSON updated with `updatedParams` (index 0–3) + `"updated": true` exactly per
  brief; validated with `python3 -m json.tool`. No other JSON fields changed.
- Canonical 13-binding layout preserved verbatim; `@workgroup_size(16, 16, 1)`;
  writes `writeTexture`, `dataTextureA`, `writeDepthTexture` every frame.

## QA Flags

- ⚠️ **No GPU in this environment** — visual QA deferred. Verified via naga
  validation + bindgroup compatibility only; the sumi-e feel (curl flow weight,
  sparkle intensity, dry-brush threshold range) should be eyeballed on real
  hardware and tuned if the sparkle reads too hot at high treble.
- `curlField` does 4 `vnoise` calls (each 4 `hash12`) per pixel — moderate
  cost; acceptable for this shader class but noted for perf review.
