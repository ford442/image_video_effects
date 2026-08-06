# gen-fireworks-kamuro-gold — VISUALIST upgrade note (Batch 37, tracker #335)

## Weaknesses found
- **Known bug class confirmed**: `mouseUV = (u.zoom_config.yz - res*0.5) / min(res.x, res.y)` treated the normalized 0–1 mouse UV as pixel coordinates — mouse kamuro shower was off-screen. Fixed to `(u.zoom_config.yz - 0.5) * res / min(res.x, res.y)`.
- **Flat depth**: `writeDepthTexture` wrote literal `0.0`.
- **LDR gold**: glitter colors all ≤1.0; core glow capped at ~2.5× before instant tonemap — no true white-hot overbright cores, so the "molten gold" pop was missing.
- **No atmosphere**: no ambient golden glow around the cloud, no fog; the glitter hung in a vacuum. **No split-tone grade** — shadows and highlights shared one temperature.
- **`mids` channel unused**; gold/silver mix was purely per-spark random, not audio-driven.

## Techniques applied (Visualist domain)
1. **HDR white-gold burst cores**: core flash `hexBokeh(..., 2.6 + bass)` tinted `(1.0, 0.93, 0.62)`, plus a quadratic hot-core term `g² * 0.9` on every glitter spark so bright droplets exceed 1.0 pre-ACES.
2. **Audio-reactive color temperature**: `audioTemp = clamp(treble*0.4 - bass*0.25, -1, 1)` feeds `goldCol(gold, seed, temp)` — treble shifts the gold↔silver blend toward cool silver, bass deepens the warm amber mix. `mids` drives haze intensity.
3. **Golden atmospheric haze + depth fog + split-tone grade**: warm amber ambient halo `exp(-d*2.2)` lingers around each cloud (density slider-scaled); cool haze `(0.008, 0.010, 0.026)` settles in heat-free sky; final split-tone grade warms highlights `(1.06, 1.0, 0.9)` scaled by luma and bass.
4. **Real generated depth**: accumulated `heat` from every glow → `depth = clamp(1 - exp(-heat*1.5), 0, 1) * 0.85`.

## Slider wiring (all 4 live, shader-specific)
- p1 **Glitter Density** → per-shell spark count + energy AND haze intensity.
- p2 **Fall Speed** → `kamuroPos` fall acceleration (unchanged semantics).
- p3 **Gold Mix** → `goldCol` gold↔warm base mix (unchanged semantics).
- p4 **Hang Time** → `kamuroPos` hover AND temporal `trailDecay` (unchanged semantics).

## Contract compliance
- Canonical 13 bindings verbatim; Uniforms struct exactly `config, zoom_config, zoom_params, ripples`. ✅
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard. ✅
- `writeTexture`, `writeDepthTexture` (real generated depth), `dataTextureA` written every frame (`dataTextureB` persistent buffer kept). ✅
- Audio only from `plasmaBuffer[0].xyz`; no hash-based fake spectrum. ✅
- Feedback reads via `textureLoad(dataTextureC, pixel, 0)` only. ✅
- Semantic alpha: `clamp(length(col)*1.2 + 0.1, 0.12, 0.97)` — intensity-based. ✅
- No extraBuffer writes; no `textureSample`/`dpdx`/`tan`. ✅
- JSON: `updatedParams` byte-exact vs `git show HEAD:` (verified identical); only `description` appended and `features` populated (additive). ✅

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files ...` → **PASS** (naga OK, bindgroup compatible, exit 0).
