# gen-fireworks-horse-tail — Algorithmist upgrade note (tracker #333)

## Weaknesses found
1. **Normalized-pointer bug (known fireworks bug class):** `mouseUV = (u.zoom_config.yz - res*0.5)/min(res)` treated the 0–1 canvas mouse uv as *pixels* — mouse brocade cascade spawned at the wrong location. Fixed: `(zoom_config.yz - 0.5) * res / min(res)`.
2. **Fake drift physics:** `tailPos` used a hardcoded linear sideways drift (`age*0.015`) plus pure t² gravity — streamers slide sideways at constant speed forever (no wind cause, no terminal velocity), the classic "dead physics" look.
3. **No temporal-coherent noise:** streamers perfectly straight except the fake linear drift; no coherent sway, no per-shell gusts; brocades never lean.
4. **Dead sky:** static star field, no twinkle.
5. **Flat depth:** `writeDepthTexture` written as literal `0.0` (contract violation).

## Techniques applied (Algorithmist domain)
- **Physically-grounded ballistic + linear drag:** shared `sparkPos(o,v,age,g,k)` closed-form integrator (`a = -k·v + g`); streamers now fall toward a **terminal velocity** like real brocade stars. Per-spark `dragK = 0.10 + seed*0.22`. Initial drift velocity `dir*0.15` and gravity scale `fall*0.9` chosen so `k→0` reproduces the original look (soul preserved).
- **Temporal-coherent curl-style sway:** per-spark `sway(seed, age)` value-noise lateral perturbation growing with age (capped at 2.5s) replaces the fake constant drift; amplitude is driven by the Stream Width slider so wider streams sway wider.
- **Per-shell coherent gust:** `shellWind(center, time, seed)` — slowly evolving shared wind so entire brocades lean together (`gust · age²` integration).
- **Temporal-coherent starfield:** hash phase-locked sinusoidal twinkle.

## Slider wiring (all 4 LIVE, semantics unchanged)
- p1 **Tail Length** → `tailLen`: burst energy and streamer count per spark (`6 + tailLen*8` samples) + trail decay.
- p2 **Stream Width** → `spread`: streamer cone width, mouse cascade width, AND now the lateral sway amplitude.
- p3 **Gold Intensity** → `gold`: warm-gold vs silver palette mix.
- p4 **Fall Speed** → `fall`: gravity scale in the drag integrator (terminal fall rate).

## Contract compliance
- Canonical 13-binding header verbatim; Uniforms struct exactly `config, zoom_config, zoom_params, ripples`. ✅
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard. ✅
- `writeTexture`, `writeDepthTexture`, `dataTextureA` (and B) written **every frame**. ✅
- Only `textureSampleLevel`/`textureLoad`/`textureStore`; no `textureSample`, no derivatives, no reserved identifiers. ✅
- Audio ONLY from `plasmaBuffer[0].x` (bass→energy/tail length) and `.z` (treble→silver micro-dust). No fake spectrum. ✅
- Feedback: single `textureLoad(dataTextureC, pixel, 0)` temporal blend with tailLen-driven decay. ✅
- Semantic alpha: luma-derived intensity, not hardcoded. ✅
- Real generated depth: `depth = (1 - exp(-heat*1.5)) * 0.85` from accumulated streamer/flash/dust heat. ✅
- extraBuffer: unused. ✅
- JSON: additive only (`features` list populated); `updatedParams` verified byte-exact vs `git show HEAD:`. ✅

## Gate result
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/gen-fireworks-fan-shell.wgsl public/shaders/gen-fireworks-horse-tail.wgsl
✅ gen-fireworks-horse-tail — naga OK, bindgroup compatible
```
