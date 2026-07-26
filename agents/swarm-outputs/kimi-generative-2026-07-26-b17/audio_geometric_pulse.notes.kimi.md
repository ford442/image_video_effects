# audio_geometric_pulse — Batch 17 upgrade notes (Kimi / Algorithmist)

## Line delta
- Before: 211 lines → After: **276 lines** (+65, within target 261–301)

## Changes per technique

### 1. FIXED fake audio (priority 1)
- `let audioPulse = u.zoom_config.w;` (mouse-DOWN flag) → `let audioPulse = plasmaBuffer[0].x;` (bass band).
- Only the **source** changed; every downstream use (pulse radius, rotation speed, neon thickness/intensity, center burst, band rings, audioColor hue) is untouched.
- plasmaBuffer is now actually read: bass `[0].x`, mids `[0].y` (small warm shimmer on center burst), treble `[0].z` (symmetry modulation), per-bin `[1..5].x` (band rings).

### 2. Click SDF rings
- Loop over `u.ripples` guarded by `min(u32(u.config.y), 50u)`.
- Each click (ripple.xy in 0..1 frame space, converted to aspect-corrected uv; ripple.z = click time) spawns an expanding **rotating sdHexagon ring** (radius 0.05 + age·0.35) that fades with `life²` over 2.5 s. Color cycles via `audioColor(fract(age*0.4 + ri*0.13), audioPulse*0.5)`; brightness scales with bass.

### 3. Treble symmetry modulation + spring-damped center
- Symmetry slider base (`3.0 + x*9.0`) is now modulated by `treble * 2.0`, clamped to 3..14 segments, then cast to i32. The kaleidoscope fold math (`mod_val` + segment mirror) and all four SDFs are preserved **verbatim**.
- Mouse center offset is spring-damped in `extraBuffer[133..136]` (pos.xy, vel.xy). Underdamped spring (`vel = (vel + (target-pos)*0.18) * 0.82; pos += vel`) with cold-start snap. Only invocation (0,0) writes — no races. All reads/writes in the [133..255] safe zone only.

### 4. Frequency band rings — real FFT
- The 5 band rings previously keyed everything off the mouse flag; now each ring reads its own bin `plasmaBuffer[1+b].x` for radius excursion (+0.04), thickness, hue drift, and brightness.

## Slider wiring (saved-preset contract preserved)
| index | mapping | name | WGSL use |
|---|---|---|---|
| 0 | zoom_params.x | Symmetry (0.5) | kaleidoscope segment count 3–12 + treble ±2 |
| 1 | zoom_params.y | Shape Morph (0.5) | circle/hexagon/triangle SDF morph blend |
| 2 | zoom_params.z | Pulse Speed (0.3) | pulseSpeed 1–5 (radius pulse + center burst) |
| 3 | zoom_params.w | Complexity (0.4) | numShapes 3–8 concentric shapes |

All ids/names/defaults/min/max/step/mapping unchanged; `updatedParams` index 0–3 added exactly as the brief's JSON (written verbatim to `shader_definitions/generative/audio_geometric_pulse.json`).

## Binding compliance
- Canonical 13-binding layout preserved verbatim (0 sampler … 12 plasmaBuffer read). No binding added/renumbered; no historyTexture.
- `@workgroup_size(16, 16, 1)` kept.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame.
- `textureSampleLevel(..., 0.0)` for the depth sampler read; no storage texture reads.
- No WGSL reserved keywords used as identifiers; ripple loop guarded with `min(u32(u.config.y), 50u)`.
- extraBuffer: only [133..136] written, guarded by `global_id.x == 0u && global_id.y == 0u`.

## QA flags
- `wgsl_precommit_gate.py --files …` — **PASS** (1 passed, 0 failed, 0 warnings). Note: naga binary not installed in this VM, so naga validation was skipped by the gate itself (environment limitation, bindgroup + workgroup checks still ran green).
- `audit_extrabuffer.py --files …` — **AUDIT PASS** (0 violations, 0 dynamic, 0 out-of-range).
- `audit_dead_sliders.py --files audio_geometric_pulse` — **AUDIT PASS** (0 dead sliders).
- No other files touched (no src/**, no other shaders, no gate scripts).
