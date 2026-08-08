# Interactivist note — gen-sentient-aether-flora-biosphere (tracker #345)

## Weaknesses found
- **Uniform-truth violations**: `audio_react = u.zoom_params.w * u.config.y` —
  **click count used as an audio proxy** in both petal pulsing and color
  shifting (and it consumed slider p4 for it).
- **Dead sliders**: p1 (`bloom_intensity`) and p2 (`flora_density`) were
  declared in `map()` and **never used** — 2 of 4 sliders inert.
- **Static spores**: the "drifting aether-spores" had *no motion at all* —
  fixed grid, only growing near the mouse. No feedback, no persistence, no
  click response; flora sway was a lone slow `0.2·sin(time)` twist.
- **No `dataTextureA` write**, **flat depth 0.0**, **hardcoded alpha 1.0**.
- `applyGenerativePrimaryControls` double-hijacked `zoom_params` — removed.

## Techniques applied (Interactivist domain)
Fast-motion techniques (⚡ directive):
1. **Fast growth-front propagation that self-organizes along its own
   history** — the decayed feedback field (`textureLoad(dataTextureC)`,
   velocity-advected upstream along the radial flythrough flow + click shock
   vector, clamped fetch) is read as `growthEnergy` and advances the petal
   pulse phase (`time·3 + growth·2.5 + x/z`), so bloom waves race along the
   flora's own luminous history. Energy bounded (luma clamp ≤1.5, HDR ≤6.0).
2. **Bass-transient bloom shockwave** — envelope-follower kick detector in
   `extraBuffer[133..134]` (0.3 s retrigger) whips petals open
   (`+0.6·exp(−2.5·age)` bounded decay), launches a radial **spore burst**
   (`(h−0.5)·kickEnv·0.8`), and flashes bloom emission.
3. **Fast cursor-chasing spore swarm** — spores gained closed-form smooth-sin
   flight (speed scales with p2, 1.5–5 rad/s per agent, temporal-coherent) +
   **spring-damped pursuit** of a cursor gravity well riding 5 units ahead of
   the camera at the pursuit point (`clamp(±0.4)` velocity clamp), with
   **velocity-lead anticipation** from the spring-smoothed cursor in
   `extraBuffer[135..136]` (vel clamped ≤8 uv/s, dt-based, fps-independent).
4. **Click growth-seed shockwaves** — guarded ripple loop
   (`min(u32(config.y),50u)`): each click emits an expanding ring that distorts
   the view and feeds the bloom impulse (bounded exp decay).
5. **Velocity-advected HDR trails** — decay ×0.85·0.5, **clamped ≤6.0**.
Also: fast flythrough (1–4× by p2) with smooth (non-strobing) sway, whip-fast
stem twist (sway + cursor + bass), real audio (`plasmaBuffer[0].xyz` + guarded
FFT bins 1–8 for petal color shimmer).

## Slider wiring (all 4 live, byte-exact JSON params)
- p1 **Intensity** (0–1) → SSS strength + bloom-flash emission + spore
  emission count (20→160).
- p2 **Speed** (0–1) → flythrough speed, twist sway rate, spore flight speed,
  petal pulse amplitude (governs SPEED — central to the fast-motion pass).
- p3 **Scale** (0–1) → flora domain repetition (7.0→3.5) **and** spore field
  frequency (1.2→3.5).
- p4 **Mouse Influence** (0–1) → cursor gravity-well strength, swarm chase
  amount, twist/look-at range.

## Contract compliance
- Canonical 13-binding header verbatim; Uniforms struct exactly
  `config, zoom_config, zoom_params, ripples`; truthful comments. ✔
- `@compute @workgroup_size(16, 16, 1)` + resolution bounds guard. ✔
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame. ✔
- Audio ONLY `plasmaBuffer[0].xyz` + guarded FFT bins 1–8 (arrayLength guard,
  read-only). ✔ Ripple loop guarded. ✔
- Persistent state ONLY `extraBuffer[133..137]`, single-writer
  (`gid.x==0u && gid.y==0u`) + `arrayLength >= 139u`. ✔
- Feedback via `textureLoad` only; HDR history in A, ACES only on
  presentation. ✔
- Semantic alpha = bioluminescent emission (0.04–0.95). ✔ Real generated
  depth = raymarched hit distance `t/max_t`. ✔
- Stability: all velocities clamped, feedback ≤6.0, bloom impulse ≤1.5,
  smooth sin only (no hash strobing), dt-clamped integration. ✔ Soul
  preserved: same twisted-stem/petal SDF flora, SSS shading, fog, spore
  volumetrics, green/magenta bioluminescent palette. ✔

## JSON
`updatedParams` byte-exact (verified vs `git show HEAD:`). Additive only:
description extended truthfully, `features` populated (was `[]`) with
fast-motion tags.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files …` → **PASS** (naga OK,
bindgroup compatible, 0 extraBuffer violations), exit 0.
