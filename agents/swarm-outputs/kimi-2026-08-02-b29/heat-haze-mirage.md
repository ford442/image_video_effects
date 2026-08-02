# Swarm Completion: heat-haze-mirage (b29)

**Status:** ✅ Complete
**Lines:** 119 → **170** (target 169–209, +51)
**Naga:** `naga public/shaders/heat-haze-mirage.wgsl` → **Validation successful** (clean, no errors/warnings)

## Changes

1. **FIXED THE AUDIO SOURCE (priority 1):** replaced dead `extraBuffer[0]/[1]/[2]` reads (reserved zeros) with `plasmaBuffer[0].x/.y/.z` — bass/mid/treble are now live. The bass ×2.0 heatIntensity boost, the mid glow term, and `dataTextureB.w` stored bass all carry real signal. This was the only reserved-zone access in the file.
2. **Spring-damped heat source:** critically-damped spring (ω=3.0, dt=1/60) eases the mouse hot spot; state lives in `extraBuffer[133..136]` (pos.xy, vel.xy) — the first/only extraBuffer state this shader touches. Cold-start guard (`time < dt*2`) snaps to the cursor on frame 0. Raw mouse remains the spring target; a small fbm2 thermal sway (±0.015) makes the hot spot wander like real hot air.
3. **Aspect-corrected mDist:** `(uv - heatPos) * vec2(aspect, 1.0)` — the heat column is now circular instead of elliptical.
4. **Click heat bursts:** ripple loop guarded by `min(u32(u.config.y), 50u)`; each live ripple adds `exp(-age*1.5) * smoothstep(0.2, 0.0, aspect-corrected dist)` to heatFactor (~2s decay, 3s cutoff), no mouseDown needed.
5. **Per-band FFT shimmer:** 8 vertical bands; `plasmaBuffer[(band % 8u) + 1u].x * 0.3` boosts displacement amplitude per band — shimmer varies across the spectrum.
6. **Treble wired:** `chromaShift *= (1.0 + treble * 0.5)` (previously treble was read but unused).
7. **Stale comment fixed:** `config.y = ClickCount` → `y=RippleCount`.
8. **JSON:** applied the brief's JSON verbatim (added `updatedParams` index 0–3 + `updated: true`; 4 param ids/names/defaults/min/max/step unchanged).

## Contracts preserved (CAUTION block)

- `hash` / `vnoise` / `fbm2` helpers — verbatim.
- `risingUV` advection, `heatBase` column, vertical-bias `heatDisp = vec2(disp.x, disp.y * 0.3)` — verbatim.
- Chromatic r/g/b tap structure, warm tint `(1.04, 1.01, 0.97)`, glow `(0.05, 0.03, 0.01)` — verbatim.
- `hazeAcc = mix(vec4(col, a), prev, 0.85)` — A write / C read contract, mix form kept.
- `dataTextureB` packing `(heatDisp, heatFactor, bass)` — verbatim.
- Canonical 13-binding layout, `@workgroup_size(16, 16, 1)`, writes writeTexture + writeDepthTexture + dataTextureA every frame.
- extraBuffer: touches indices **[133..136] ONLY** (no reserved [0..4], no engine FFT [5..132]).
  Note: the spring inherently read-modify-writes its own persistent state in [133..136]; no reads occur outside the shader's own state zone.
- 4 slider mappings via `u.zoom_params.x/y/z/w` unchanged (already shader-specific: heat intensity, rise speed, wave scale, chroma shift).

## Files touched

- `public/shaders/heat-haze-mirage.wgsl` (rewritten)
- `shader_definitions/image/heat-haze-mirage.json` (brief JSON applied verbatim)

## Coordinator closeout

- Final lines: **119 → 177 (+58)**. Replaced the every-pixel spring write race with invocation `(0,0)` ownership and an explicit `[137]` initialization flag.
- Click heat now uses a bounded maximum rather than summing up to 50 events; relief depth is clamped while raw `hazeAcc` A and diagnostic B packing stay intact.
- Final focused gate, dead-slider/strict-buffer audit, JSON/list parity, Jest, and production build: pass.
