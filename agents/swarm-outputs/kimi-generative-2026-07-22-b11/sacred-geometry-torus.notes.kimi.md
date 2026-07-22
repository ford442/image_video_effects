# sacred-geometry-torus — Visualist upgrade notes (2026-07-22, b11)

**Role:** Visualist

## Key changes

- **Fibonacci dot lattice (phyllotaxis):** added `phyllotaxis()` helper — golden-angle (2.39996 rad) point lattice projected onto the torus disc, dot i at `spacing·√(i+½)`; fixed 20-dot budget, branchless soft-masked by `latticeCount` driven by Phi Layers slider. Dots bloom hardest at knot strand intersections (`latticeOnStrand`).
- **Cosine-palette strand hue cycling:** added canonical IQ palette (`iqPalette`); intensity-weighted mean strand index (`strandT`) computed during the knot-tap loop gives each strand a slow hue offset (`strandT + time*0.03 + bass*0.05`), mixed at 0.35 so sacred gold stays dominant.
- **Trail clamp + polish:** temporal accumulation from `dataTextureC` now clamped pre-tint at 1.2 (`TRAIL_CLAMP`, luma-echo-warp lesson); added restrained crossing-bloom lift (`smoothstep(1.1, 2.2, …)` on pattern+lattice, scaled by Glow).
- **Slider rewiring (same ids/defaults — saved-preset contract intact):**
  - Knots → knot weave frequency (unchanged, already meaningful)
  - Spin → strand rotation speed + lattice swirl rate
  - Glow → strand brightness + crossing bloom strength
  - Phi Layers → phi-harmonic node layers + phyllotaxis dot count (`latticeCount` = mix(2, 20, w))
- `dataTextureA` channel 3 now carries `latticeOnStrand` (was `phiLayers * 0.1`); depth/presence also account for the lattice. Canonical 13-binding layout and `@workgroup_size(16,16,1)` preserved; no binding 13 added.

## Line count delta

- Before: 155 → After: 219 (**+64**, within the +50…+90 target; brief target 205–245 ✓)

## Gate result

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/sacred-geometry-torus.wgsl` → **exit 0**, naga OK, bindgroup compatible, 0 warnings.

## QA flags

- All new constants are eyeballed (lattice spacing 0.11, dot falloff 900+400·treble, crossing thresholds 1.1/2.2, bloom lift 0.22, hue-cycle rate 0.03, palette mix 0.35) — tuned by reasoning, not by eye.
- This VM has no GPU adapter (WebGPU unavailable), so **visual QA is deferred**; validation is naga static analysis + bindgroup compatibility only. Recommend a visual pass on real hardware to confirm lattice density, crossing bloom restraint, and hue-cycle mix feel right.
