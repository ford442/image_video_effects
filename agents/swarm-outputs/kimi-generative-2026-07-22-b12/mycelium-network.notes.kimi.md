# mycelium-network — Interactivist Upgrade Notes (Kimi, 2026-07-22, b12)

**Role:** Interactivist
**Shader:** `public/shaders/mycelium-network.wgsl` (generative)
**Brief:** `swarm-tasks/kimi-generative-briefs-2026-07-22-b12/mycelium-network.md`

## Line delta

- Before: 166 lines → After: **239 lines** (**+73**, within the +50 to +90 budget; brief target 216–256 ✅)

## Key changes

1. **Click nutrient pulse packets (extraBuffer[5..8], rising edge):**
   - `[5]` = previous mouse-down state (rising-edge detector), `[6]` = last click time, `[7..8]` = last click UV.
   - Only thread `(0,0)` writes; all threads read previous-frame state (established repo pattern).
   - On rising edge of `zoom_config.w`, a visible wavefront expands from the click point (aspect-corrected radius, speed scaled by Pulse Speed slider, `exp` age decay). The packet is masked by the accumulated hypha field so it **brightens strands as it passes** rather than drawing a raw ring.
   - extraBuffer[0..4] untouched (reserved) — CAUTION honored.

2. **Growth tropism:** trunk growth direction is a normalized `mix` between the hashed trunk direction and the direction from the cell center to the mouse; lean rate = `zoom_params.z * 0.7` (Pulse Speed slider doubles as lean rate per brief). Branch angles inherit the lean via `trunkAngle` derived from the grown trunk.

3. **Bass heartbeat:** `heartbeat = pow(0.5+0.5*sin(time*(2+bass*5)), 3) * (0.25+0.75*bass)` from `plasmaBuffer[0].x` drives a gentle network-wide throb — swells strand width (`* (1.0 + heartbeat*0.2)`) and adds a soft warm color lift masked by the hypha field.

4. **Worley hyphal thickness:** added a 3×3 cellular-noise `worley()`; `thickVar = 0.6 + worley(p*0.5)*0.8` varies trunk/branch width per region so strands differ in thickness.

5. **Slider wiring (existing ids/defaults preserved, saved-preset contract intact):**
   - `density` → `zoom_params.x` → networkDensity (cell grid frequency + anti-moire LOD input) — unchanged mapping.
   - `angle` → `zoom_params.y` → branchAngle spread in the branchless loop — unchanged.
   - `pulse` → `zoom_params.z` → nutrient pulse speed **and** click-packet expansion speed **and** tropism lean rate.
   - `glow` → `zoom_params.w` → tip-glow/spore intensity **and** click-packet brightness.

## Preserved

- Core algorithm (per-cell hashed trunk + branchless 5-iteration masked branches, nutrient pulses, spore clouds, temporal feedback, CA, ACES, semantic alpha) — upgrade, not rewrite.
- Anti-moire LOD/dither block (`lod`/`lodFade`) intact verbatim.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes to `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- JSON: only appended `updatedParams` (indices 0–3) + `"updated": true` exactly as in the brief; no other field changes.

## QA

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/mycelium-network.wgsl` → **exit 0, naga OK, bindgroup compatible, 0 warnings**.
- JSON parses cleanly (`json.load` OK).
- ⚠️ **Visual QA deferred:** this Cloud VM has no GPU adapter (`navigator.gpu.requestAdapter()` returns null), so the shader was validated via naga/gate only — no on-screen verification of pulse-packet, tropism, or heartbeat behavior.
