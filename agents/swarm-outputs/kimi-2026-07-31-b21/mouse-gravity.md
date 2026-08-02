# Swarm Output: mouse-gravity (Batch 21)

**Agent:** Kimi (Interactivist) | **Date:** 2026-07-31

## Lines
- Before: 105 → After: 166 (+61, target +50..+90 ✅; 155–195 range ✅)

## Slider Map (roles unchanged, same ids/defaults/order)
- `u.zoom_params.x` — Gravity Strength (0.5): well pull, `* 2.0 * (1.0 + bass*0.4) * (1.0 + mouseDown*0.3)`
- `u.zoom_params.y` — Event Radius (0.2): falloff radius, `* 0.5 * (1.0 + mids*0.3)`, clamped ≥0.01
- `u.zoom_params.z` — Chrom. Aberration (0.3): r/b split, `* 0.05 * (1.0 + treble*0.8)`
- `u.zoom_params.w` — Core Darkness (0.8): singularity black mix + ring gate

## Techniques Added
1. **Spring-damper singularity (priority 1):** critically-damped spring, omega=6.0 (heavy/massive feel), raw mouse = target only. extraBuffer map: [133..134] sprung pos, [135..136] velocity, [137] init flag, [138] last time. Integrated by thread (0,0); all threads read sprung `wellPos`.
2. **Click gravity pulses:** ripple loop guarded `min(u32(u.config.y), 50u)`; each live ripple (age ≤2s) is a secondary well at its click point, same `exp(-dist/radius)` form, strength `0.6*exp(-age*2.0)`, combined multiplicatively via `clickWarp`.
3. **Photon ring shimmer:** `smoothstep(0.02, 0.0, abs(dist - radius*0.35))` accretion ring, tinted by treble bins `plasmaBuffer[7].x`, gated by `darkness * (1.0 - core)` so it only shows against a dark core; cool blue-white tint.
4. **mouseDown deepening:** `strength * (1.0 + mouseDown * 0.3)` folded into the strength param line.

## Verbatim Preserved
- All dev thinking-out-loud comments (gravity reasoning, zoom-in/out musings, OOB/sampler note, depth passthrough question)
- Header/bindings block (13 bindings, @workgroup_size(16,16,1))
- Distortion falloff `1.0 - strength * exp(-dist / radius)` (now wrapped multiplicatively with clickWarp)
- r/g/b aberration offset structure (`distortion -/± aberration`)
- Core smoothstep darkness mix, lensing-mask alpha, warped-depth read via uvG
- dataTextureA = DISPLAY color; writeTexture/writeDepthTexture/dataTextureA written every frame

## JSON Changes
- Added ONLY `updatedParams` (4 entries, index 0–3, matching brief) + `"updated": true`. No other keys touched.

## Deviations
- `toMouse`/uvR/uvG/uvB now anchor to sprung `wellPos` instead of raw `mousePos` (required for the mass effect; structure identical). `mousePos` kept verbatim as spring target.
- Ripple strength scaled by 0.6 so stacked clicks don't fully invert the warp (brief didn't forbid scaling; form + fade + multiplicative combine per spec).

## Gate
```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/mouse-gravity.wgsl
Passed: 1 | Failed: 0 | Warnings: 0 | extraBuffer violations: 0 — ✅ naga OK, bindgroup compatible
```
