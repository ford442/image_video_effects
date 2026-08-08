# Interactivist note — gen-neon-plasma-biomechanical-hive (tracker #344)

## Weaknesses found
- **Severe uniform-truth violations**: all 4 "parameters" were read from
  `u.zoom_config` — `breathing_speed = zoom_config.x` (**time**, so the
  breathing-rate sin exploded to nonsense frequencies), `neon_intensity =
  mouseX`, `spore_density = mouseY`, `magnetic_pull = mouseDown` (binary 0/1).
  Meanwhile `zoom_params.x/y` (the real sliders) were misused as a fake mouse
  offset. Sliders were effectively dead/scrambled.
- **Fake audio**: `audio = u.config.y * 2.0` — rippleCount used as audio level.
- **No `dataTextureA` write at all** (contract requires every-frame write),
  **flat depth 0.0**, **hardcoded alpha 1.0**.
- **No feedback / no persistence / no click response** — zero temporal
  reactivity; spores drifted at `time*0.3–0.5` (slow, soulless for a swarm).
- `applyGenerativePrimaryControls` hijacked `zoom_params` a second time
  (generic intensity/contrast) — removed; sliders now drive shader-specific
  constants directly.

## Techniques applied (Interactivist domain)
Fast-motion techniques (⚡ directive):
1. **Fast cursor-chasing spore swarm** — spores became closed-form orbital
   agents (per-cell smooth sin flight at 2.0–4.5 rad/s, temporal-coherent, no
   hash strobing) with **spring-damped pursuit** of the cursor attractor
   (`clamp(attract - p, ±0.45)` = clamped max velocity).
2. **Cursor pursuit with velocity lead** — spring-smoothed cursor tracked in
   `extraBuffer[135..136]`; `(mouse − smoothMouse)/dt` gives cursor velocity
   (**clamped to 8 uv/s**), a 0.12 s lead makes the gravity well anticipate
   flicks (whip-fast but stable). Frame-rate-independent (`dt` from persistent
   prev-time slot, clamped 1–100 ms; `1 − exp(−dt·12)` spring).
3. **Bass-transient shockwave** — envelope-follower kick detector
   (`extraBuffer[133..134]`, 0.3 s retrigger gap) fires an expanding ring
   (3.5 uv/s) with **bounded `exp(−2.5·age)` decay** that whips the camera,
   flashes the neon veins white, and boosts spore glow.
4. **Click shockwaves** — guarded ripple loop (`min(u32(config.y),50u)`)
   adds radial ring impulses per click, same bounded exp decay.
5. **Velocity-advected HDR feedback trails** — previous frame fetched via
   `textureLoad(dataTextureC, …)` upstream along the shock/velocity vector
   (clamped fetch), decayed ×0.86·0.55, **HDR clamped ≤ 6.0** (Batch-36 lesson).
Also: 2× faster flythrough (speed scales with p1), bass/kick-widened chromatic
aberration, real audio everywhere (`plasmaBuffer[0].xyz` + guarded FFT bins
1–8 for vein shimmer).

## Slider wiring (all 4 live, byte-exact JSON params)
- p1 **Hive Breathing Speed** (0.1–5) → breathing rate **and** flythrough
  speed + vein scroll speed (governs SPEED).
- p2 **Neon Intensity** (0–10) → vein glow emission.
- p3 **Spore Density** (0–1) → spore swarm glow density.
- p4 **Magnetic Pull** (0–5) → cursor gravity-well strength (×0.8, force
  clamped ≤2.0; mouseDown boosts ×1.6).

## Contract compliance
- Canonical 13-binding header verbatim; Uniforms struct exactly
  `config, zoom_config, zoom_params, ripples`; truthful comments. ✔
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard. ✔
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame. ✔
- Audio ONLY `plasmaBuffer[0].xyz` + guarded FFT bins 1–8
  (`arrayLength(&extraBuffer) > 13u`, read-only). ✔
- Ripple loop guarded `min(u32(u.config.y), 50u)`. ✔
- Persistent state ONLY `extraBuffer[133..137]`, single-writer
  (`gid.x==0u && gid.y==0u`) + `arrayLength >= 139u` guard. ✔
- Feedback reads via `textureLoad` only; HDR history in dataTextureA,
  ACES only on writeTexture presentation. ✔
- Semantic alpha = hive emission intensity (`luma(hdr)*0.6 + shock*0.25`,
  0.04–0.95). ✔ Real generated depth = raymarched hit distance `t/20`. ✔
- Stability: velocities clamped (pull ≤2, mouse vel ≤8, chase ≤0.45), feedback
  energy bounded ≤6.0, smooth sin motion only (no strobing), dt-based
  integration. ✔ Soul preserved: same voronoi hive, 3-pass CA raymarch,
  gunmetal + cyan/magenta neon, spore glow. ✔

## JSON
`updatedParams` byte-exact (verified vs `git show HEAD:`). Additive only:
description extended truthfully, `features` populated (was `[]`) with
fast-motion tags.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK,
bindgroup compatible, 0 extraBuffer violations), exit 0.
