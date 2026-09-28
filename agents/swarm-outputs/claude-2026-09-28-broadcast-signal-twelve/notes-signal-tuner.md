# signal-tuner — implementer notes (2026-09-28)

Files: `public/shaders/signal-tuner.wgsl`, `shader_definitions/interactive-mouse/signal-tuner.json`.

## Kept verbatim
Aspect-corrected falloff radius 0.5 (`smoothstep(0.5, 0.0, dist)`), row sine with `freqRadius = mix(0.3, 1.0, mouseInfluence)`, `beat_pulse`, click-ring loop (age = time - rp.z, cap `min(u32(u.config.y), 50u)`, ring/`rippleTune`/`rippleRing` maths), UV jitter from the Static Noise slider, R/B split `audioAmp * influence * 0.5 * (1 + treble*0.25)`, depth write, and all four slider roles (x frequency 5..100, y interference amp*0.1, z drift speed*5, w static).

## A packing
Pre-ACES linear display RGB + semantic alpha in `dataTextureA`; `dataTextureC` read back exactly (`textureLoad(dataTextureC, gid, 0)`) as that linear colour for the in-zone ghost history. ACES applied only on `writeTexture` (line 169).

## Ideas (line ranges in the WGSL)
1. **Off-station snow** — lines 141-148. Per-pixel hash snow (`snowSeed`, `snowGrain` re-rolled ~30 Hz) mixed into the colour by `snowMix = noiseAmt * influence * (0.25 + 0.75*|waveNorm|) * snowGate * 0.9`; `snowGate` density is treble-flickered (`step(0.55 - treble*0.25, grain)`). Strongest where the row wobble is at its crest, zero outside the tuning zone. Snow also adds carrier opacity to alpha (line 162).
2. **RF multipath ghost** — lines 127-136. A second source sample offset to the right (`finalUV - ghostDelay`, so the copy appears right of the direct image) with `ghostDelay = mix(0.015, 0.075, Frequency) * (1 + bass*0.2)`. Added at `influence * (0.22 + audioAmp*1.5)`, 60 % desaturated, inherits the wobble because it is sampled at `finalUV`. Not history: same frame, delayed path.
3. **Detune beat bands** — lines 106-113 (envelope + row shift) and 138-139 (brightness). The effective row frequency `freqEff = freq * freqRadius` beats against a virtual raster pitch `RASTER_FREQ = 48` rad/uv; `beatProximity` peaks when they coincide, `beatEnv = cos(uv.y * beatDelta*0.5 - time*speed*0.35 + rippleTune)` drifts through the zone, squared for band shape; it modulates brightness by up to ±35 % and nudges rows by up to 0.008 uv. Default frequency 0.5 → freq 52.5, so at the cursor (freqRadius 1) the beat is near-maximal and slows as the cursor moves; beat bands vanish away from the cursor (`influence`).

## Floor fixes
- Removed the whole extraBuffer spring/envelope block (lines 59-93 at HEAD): it read re-zeroed slots. Pointer now `u.zoom_config.yz` (line 68); `env` replaced by `bass` in `beat_pulse` and `audioAmp`.
- Removed `plasmaBuffer[regionBin]` (never written). The `(1 + fftRegion*0.4)` noise factor became `(1 + treble*0.4)`; the split factor keeps HEAD's `1 + treble*0.25` (the dead `fftRegion*0.20` term dropped).
- `hash(uv * time)` → `hash(uv + vec2(time*0.37, time*1.13))` (line 116).
- History mix: HEAD blended only 15 % new colour everywhere (`mix(prev, new, 0.15 + …)`), lagging the whole video. Now `historyWeight = influence*0.55 + pulse*0.15*influence`, i.e. 0 away from the cursor/rings, up to 0.7 inside (lines 153-154).
- ACES on display only; A stores linear. Alpha = source alpha × depth factor + snow/ghost carrier, blended toward C's alpha only inside the zone (lines 160-163) — HEAD's luma-derived alpha floor of 0.4 is gone.

## Deviations from the card
None material. The beat band uses a fixed virtual raster pitch (48 rad/uv ≈ 7.6 cycles across the frame) rather than the literal screen scanline count, because `freq` maxes at 100 rad and could never approach `res.y` lines; the card's intent (moiré when wobble ≈ raster) is preserved at a pitch the slider can actually reach.

## JSON changes
- `params`: byte-exact (python dump diff before/after identical).
- `updatedParams`: unchanged (already aligned: 4 entries, same defaults/ranges).
- `description`: rewritten to name the three ideas and the in-zone-only history.
- `features`: unchanged set (`mouse-driven`, `audio-reactive`, `temporal`, `upgraded-rgba`, `click-reactive`, `depth-aware`) — all true.

## Gate / audits
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/signal-tuner.wgsl` → PASS (naga OK, bindgroup compatible, 0 extraBuffer violations).
- `python3 scripts/audit_extrabuffer.py --files …` → AUDIT PASS (0 violations).
- `python3 scripts/audit_dead_sliders.py --files signal-tuner` → AUDIT PASS (0 dead sliders).

## GPU risks (not visually verified — the VM has no WebGPU)
- ACES on a previously un-tone-mapped output brightens midtones slightly (ACES(0.5) ≈ 0.62) — batch-wide, expected.
- `uv = gid / res` (no half-texel) was kept from HEAD so the base sampling does not shift; the ghost/snow use the same convention.
- Snow re-rolls at ~30 Hz via `floor(time*29/31/47)`; at very low frame rates it will look like slow flicker rather than snow.
- The RF ghost is clipped at the left edge by `smoothstep(0, 0.02, finalUV.x - ghostDelay)` so it does not smear the clamped edge texel.
