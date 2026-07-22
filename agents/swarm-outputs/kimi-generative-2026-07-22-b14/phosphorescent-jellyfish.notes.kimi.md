# phosphorescent-jellyfish — Kimi upgrade notes (b14, 2026-07-22)

## Line delta
- Before: 180 lines → After: 263 lines (**+83**, within the +50–90 target; 230–270 range ✓)

## Key changes per brief technique

1. **HDR blowout taming (priority 1)**
   - Added `huePreserveClamp(c, ceiling)` — scales the whole color vector down when its peak channel exceeds `HDR_CEILING = 2.0`, preserving hue/saturation instead of clipping channels to white.
   - Added `acesToneMap()` (Narkowicz ACES fit) applied to the clamped HDR stack.
   - Display path (`writeTexture`) gets the tonemapped color; `dataTextureA` (feedback source) still receives the **HDR** value, so the temporal feedback loop's energy and steady-state gain are untouched.

2. **Per-jelly spectrum**
   - Jelly `j` now reads `plasmaBuffer[min(u32(j) + 1u, bandMax)]` (`bandMax` guarded via `arrayLength`), so each jelly's bell pulse / tentacle wave / photophore sparkles ride its own FFT band (`band.x/.y/.z`) instead of the global bass/mids/treble mix. Global bands still drive the chromatic feedback (unchanged).

3. **Jet propulsion dart**
   - Mouse attraction is now gated on `u.zoom_config.w` (mouse-down); swarm drifts free otherwise. The `normalize(toMouse + 0.001)` epsilon guard is preserved.
   - Click ripples (`u.ripples[i]`, count `min(u32(u.config.y), 50u)`, `age = time - rp.z` in `[0, 1.2]`) startle the **single nearest** jelly, kicking it away from the click with a quadratic-decay impulse (`awayDir * kick² * 0.35`). Base orbital positions are precomputed in a pass-1 array so the nearest-jelly test is deterministic per pixel.

4. **Slider params**
   - Same 4 mappings, now visibly driving real constants: `zoom_params.x` → swarm population (1–5), `.y` → bell radius (0.08–0.2), `.z` → trail persistence (0.85–0.99, **mapping not retuned** per caution), `.w` → HDR glow intensity (0.5–3.0).
   - JSON: added `updatedParams` (4 entries, index 0–3, mirroring ids/names/defaults/min/max/step) and `"updated": true`. Nothing else touched.

## Contract compliance
- Canonical 13-binding layout kept, no new/renumbered bindings; binding 13 not declared (unused).
- `@workgroup_size(16, 16, 1)` ✓; writes `writeTexture` / `writeDepthTexture` / `dataTextureA` every frame ✓.
- `textureSampleLevel(..., 0.0)` for sampler reads ✓; no WGSL reserved identifiers.
- Chromatic 3-tap feedback blend weights untouched (`0.2 + bass * 0.05` mix, per-channel `cStr` taps).

## QA flags
- Depth output now clamped to [0,1] (was unbounded `bellGlow + tentGlow`) — safer for downstream depth consumers.
- `arrayLength(&plasmaBuffer)` guard assumes buffer length ≥ 1 (engine always provides slot 0).
- Ripple coords assumed uv01 space, matching engine convention used by `alpha-*` shaders.

## Caveat
- **No GPU in this VM** (headless, no WebGPU adapter) — visual QA (ACES rolloff look, dart feel, per-band pulsing) deferred to real hardware. Validated via `wgsl_precommit_gate.py` (naga + bindgroup): exit 0, 0 warnings; JSON parses clean.
