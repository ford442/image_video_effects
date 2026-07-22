# neural-mandala — Interactivist Notes (kimi, batch b14)

**Date:** 2026-07-22
**Role:** Interactivist
**Brief:** `swarm-tasks/kimi-generative-briefs-2026-07-22-b14/neural-mandala.md`

## Line delta

- Before: 177 lines → After: 235 lines (**+58 net**, 72 insertions / 14 deletions vs HEAD)
- Target was +50 to +90 (227–267 total) — **in range** ✅

## Key changes per technique

1. **Mouse re-centering + spring (headline):** While the mouse is held
   (`u.zoom_config.w >= 0.5`), the mandala center is pulled toward
   `u.zoom_config.yz` (aspect-corrected, 55% pull strength) via a damped spring
   (K=90, damping=9, dt=0.016). Spring state (pos.xy, vel.xy) persists in
   `extraBuffer[133..136]` — inside the reserved persistent range [133..255] —
   written only by invocation (0,0) to avoid racy writes. On release the spring
   eases the mandala back to screen center.

2. **Click shock rings:** Loop over `u.ripples[]` guarded by
   `min(u32(u.config.y), 50u)`. Each click emits an expanding wavefront
   (`age * 0.45` radius, exponential band falloff ×18, decay `exp(-age*1.4)`,
   3 s lifetime). The accumulated `shock` scalar perturbs every ring radius
   (`+ shock * 0.025`) as the front sweeps past, and adds a brief white-blue
   shimmer (`+ vec3(0.9,0.95,1.0) * shock * 0.35`) plus glow/depth contribution.

3. **Per-ring audio:** `ringEnergy = plasmaBuffer[u32(ri) % 8u + 1u].x` — inner
   rings ride bass bins, outer rings treble bins (same pattern as
   `coral-growth.wgsl`). `ringEnergy` now drives ring width, node size, node
   brightness, and ring color, replacing the whole-mandala global-band follow.

4. **Sub-symmetry fold:** Second `kaleido()` pass at `max(segs * 0.5, 2.0)`
   segments applied to the already-folded point, mixed in by
   `complexity * 0.55` for snowflake-like internal mirroring. Complexity keeps
   its coherent double-duty (segment count + node count) and now also controls
   fold depth.

5. **Slider rewiring (all 4 drive real constants of THIS shader):**
   - `zoom_params.x` (Ring Count): ring count 4–12 (unchanged, already direct).
   - `zoom_params.y` (Node Complexity): kaleido segments + per-ring node count
     + sub-fold mix.
   - `zoom_params.z` (Pulse Speed): `0.2 + z * 3.0` Hz ring/node pulse rate
     (was `z * 3.0` — zero slider meant a frozen mandala; now floor of 0.2).
   - `zoom_params.w` (Connection Density): inter-ring line alpha/width and
     Clifford node drift amplitude.

## Caution compliance

- dataTextureC feedback **untouched**: decay 0.92, mix `0.05 + bass * 0.01`.
- Added pre-tint clamp `min(color, vec3(1.2))` before the feedback mix
  (luma-echo-warp lesson), since shock shimmer injects extra energy into the
  feedback loop.
- Canonical 13-binding layout preserved (no added/renumbered bindings, no
  binding 13), `@workgroup_size(16, 16, 1)`, writes `writeTexture` /
  `writeDepthTexture` / `dataTextureA` every frame, sampler read uses
  `textureSampleLevel(..., 0.0)`. No WGSL reserved identifiers.

## JSON

`shader_definitions/generative/neural-mandala.json`: added `updatedParams`
(exactly 4 entries, index 0–3, mirroring existing params' names/defaults/
min/max with step 0.01) and `"updated": true`. Nothing else touched;
`json.load` passes.

## QA flags

- **Gate:** `python3 scripts/wgsl_precommit_gate.py --files public/shaders/neural-mandala.wgsl`
  → exit 0, 0 warnings, naga OK, bindgroup compatible ✅
- **No-GPU caveat:** this VM has no WebGPU adapter (canvas renders black on the
  Canvas2D fallback), so **visual QA is deferred to real hardware**. Verified
  statically only: naga validation, binding contract, ripple guard, persistent
  state range, and feedback stability clamps.
- Minor: spring state lives in extraBuffer — first frame after pipeline
  creation reads zeros (centered mandala), which is the desired default.
