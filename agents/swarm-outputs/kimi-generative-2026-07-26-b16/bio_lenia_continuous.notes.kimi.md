# Completion Notes: bio_lenia_continuous (Batch 16)

## Line Delta
- **Before:** 192 lines
- **After:** 266 lines (+74, within the +50–90 / 242–282 target)

## Key Changes per Brief Technique

### 1. Spawn Gate Fix (priority 1)
- Removed `mouseClickCount = u.config.y` (ripple count — stuck > 0 forever after first click, causing continuous spawning).
- Mouse seeding now gated on `u.zoom_config.w > 0.5` (true mouse-DOWN state).
- Upgraded the hard `newState = 1.0` overwrite to a soft radial brush: `1.0 - smoothStep(0.0, 0.05, toMouse)` scaled by 0.5, still clamped.

### 2. Real Audio → Growth "Seasons"
- Removed mislabeled `audioPulse = u.zoom_config.w` (that was mouse-down, not audio).
- Real mids routed from `plasmaBuffer[0].y` (clamped 0–1) into a slow growthCenter wobble: `growthCenterA = growthCenter + (audioMids - 0.5) * 0.08 * season`, where `season = sin(time * 0.23) * 0.5 + 0.5` — a gentle climate drift on species A's bell center.
- Mids also boost both species' spore-rain probabilities (replacing the old audioPulse uses).

### 3. Second Species (dataTextureA.g)
- Species B state packed into the free `.g` channel of `dataTextureA`; read back via `dataTextureC.g` (`sampleStateB`).
- Own bell-family constants derived from the slider-driven base: `radiusB = radius * 0.6`, `growthCenterB = growthCenter + 0.06`, `growthWidthB = growthWidth * 1.3`, `dtB = dt * 0.85` — a smaller, hungrier, slightly slower niche.
- B's neighborhood accumulates inside the EXISTING O(r²) kernel loop (same taps, own kernel weight) — loop structure not restructured.
- Cross-feeding: dense A inhibits B (`smoothStep(0.45, 0.85, A) * 0.35` subtracted from B growth); sparse A edges fertilize B; dense B grazes A back (`dt * 0.25`), so fronts visibly swap territory.
- Both states clamped to [0, 1]; A's `bell()`/`growth()`/`clamp(newState, 0.0, 1.0)` chain preserved verbatim.

### 4. Click Seed Bombs
- Ripple loop guarded with `min(u32(u.config.y), 50u)`.
- Each live ripple (age 0–3s) drops a circular species-B blob at `ripple.xy`: radius swells with age (`0.03 + age * 0.015`), strength decays with age (`1.0 - age / 3.0`), soft smoothStep falloff.

## Slider Wiring (saved-preset contract — ids/names/defaults unchanged)
| Slider | Mapping | Drives |
|--------|---------|--------|
| param1 "Radius" (0.3) | zoom_params.x | kernel radius 5–20 px (A), 60% of that for B |
| param2 "Growth Center" (0.4) | zoom_params.y | bell center 0.15–0.4 (A), +0.06 offset for B, audio season wobble applied on top |
| param3 "Growth Width" (0.2) | zoom_params.z | bell width 0.01–0.05 (A), ×1.3 for B |
| param4 "Time Step" (0.3) | zoom_params.w | dt 0.1–0.3 (A), ×0.85 for B |

Mapping formulas identical to the original — already shader-specific, no rewire needed; B's constants derive from them so every slider visibly affects both species.

## Binding Contract Compliance
- Canonical 13-binding layout unchanged; no bindings added/renumbered; binding 13 not declared.
- `@workgroup_size(16, 16, 1)` preserved.
- Writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame (depth now `max(stateA, stateB)`).
- `textureSampleLevel(..., 0.0)` for sampler reads; no storage reads via sampler.
- dataTextureA is pure sim state — never tonemapped/clamped beyond [0,1] sim clamp; `.r` primary-species layout verbatim.
- extraBuffer untouched (no persistent shader state needed).
- No reserved keywords used as identifiers; no new bindings.

## Gate Status
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/bio_lenia_continuous.wgsl`
- **GREEN: Passed 1/1, 0 warnings, bindgroup compatible** (naga step skipped — binary not installed in this environment, environmental only).

## QA Flags
- Ripple `xy` assumed to be UV-space (matches `liquid-jelly-fluid.wgsl` convention of `length(uv - ripple.xy)`); consistent with mousePos also being UV-space in this shader.
- Two-species kernel loop roughly doubles texture taps in the hot loop (B reuses the same sample coordinates, so cache-friendly); radius slider at max (20 px) remains the dominant cost — inherent to the design.
- Visual check not possible in headless VM (no GPU adapter); validated via gate + contract review only.
- JSON definition written verbatim from the brief block (updatedParams index 0–3, `updated: true`).
