# gen-fireworks-fan-shell — Algorithmist upgrade note (tracker #332)

## Weaknesses found
1. **Normalized-pointer bug (known fireworks bug class):** `mouseUV = (u.zoom_config.yz - res*0.5)/min(res)` treated the 0–1 canvas mouse uv as *pixels* — personal fan spawned at a wrong, near-origin location. Fixed: `(zoom_config.yz - 0.5) * res / min(res)`, matching the centered aspect-preserved uv space (y-down consistent on both sides).
2. **Ideal ballistic arcs, no drag:** `sparkPos` used constant-velocity + g·t²/2 — sparks fly at unchanging horizontal speed forever; no terminal behavior, no per-spark mass variation.
3. **Ruler-straight trajectories, no temporal-coherent motion:** only a single fixed-dt echo as "trail"; zero wind/turbulence; sparks look like dots on rails.
4. **Dead sky:** static hash star field, no temporal coherence (no twinkle).
5. **Flat depth:** `writeDepthTexture` written as literal `0.0` (contract violation).

## Techniques applied (Algorithmist domain)
- **Physically-grounded ballistic + linear drag:** new `sparkPos(o,v,age,g,k)` integrates `a = -k·v + g` in closed form (`v·(1-e^{-kt})/k` + terminal-velocity gravity term); `k→0` recovers the original ideal arc (soul preserved). Per-spark `dragK = 0.08 + js*0.30` — heavy sparks punch through, light ones hang.
- **Temporal-coherent wind advection:** per-shell `shellWind()` (value-noise field advected with time, seeded per burst) displaces sparks with `wind · age²` gust integration — whole fans lean and drift coherently; gain scales with mids.
- **FBM/value-noise spark flutter:** per-spark `flutter(seed, age)` wobble applied to both head and echo positions so trails are organic, not ruler-straight (echo is now domain-warped by the same field).
- **Temporal-coherent starfield:** per-star sinusoidal twinkle phase-locked to its hash (no per-frame re-hash popping).

## Slider wiring (all 4 LIVE, semantics unchanged)
- p1 **Fan Angle** → `fanAngle` hemisphere half-angle (also the mouse fan).
- p2 **Shell Power** → `energy` (speed, glow, rocket brightness).
- p3 **Spark Density** → spark count `30 + density*60` per burst.
- p4 **Hue Cycle** → palette phase offset `fract(js + hueCycle + time*0.02)`.

## Contract compliance
- Canonical 13-binding header verbatim; Uniforms struct exactly `config, zoom_config, zoom_params, ripples`. ✅
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard. ✅
- `writeTexture`, `writeDepthTexture`, `dataTextureA` (and B) written **every frame** (writes at end of main, after early-return guard). ✅
- Only `textureSampleLevel`/`textureLoad`/`textureStore`; no `textureSample`, no derivatives, no reserved identifiers. ✅
- Audio ONLY from `plasmaBuffer[0].xyz` (bass→energy, mids→fan width + wind gain, treble→spark brightness). No fake spectrum. ✅
- Feedback: single `textureLoad(dataTextureC, pixel, 0)` temporal blend (rgba32float, non-filtering). ✅
- Semantic alpha: luma-derived intensity (`clamp(length(col)*1.2+0.1, 0.12, 0.96)`), not hardcoded. ✅
- Real generated depth: `depth = (1 - exp(-heat*1.5)) * 0.85` from accumulated spark/flash/rocket heat — burst cores near, sky far. ✅
- extraBuffer: unused (no state needed). ✅
- JSON: additive only (`features` list populated); `updatedParams` verified byte-exact vs `git show HEAD:` (semantic JSON equality confirmed). ✅

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-fireworks-fan-shell.wgsl public/shaders/gen-fireworks-horse-tail.wgsl
✅ gen-fireworks-fan-shell — naga OK, bindgroup compatible
```
