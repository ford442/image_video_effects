# Agent Notes — kaleido-portal-interactive (Batch 17, Visualist)

**Date:** 2026-07-30
**Files touched:**
- `public/shaders/kaleido-portal-interactive.wgsl` (rewritten/upgrade)
- `shader_definitions/interactive-mouse/kaleido-portal-interactive.json` (added `updatedParams` + `"updated": true` only)

## Lines

- WGSL: **96 → 166** (+70, inside the 146–186 target window)
- JSON: 44 → 76 (only the `updatedParams` array and `"updated": true` appended; existing params untouched — same ids, names, defaults, order)

## Techniques implemented

### 1. HDR border glow tamed (PRIORITY 1)
- Was: `borderGlow = border * (5.0 + bass * 2.0)` added raw → up to ~7.0 unclamped in the rgba32float chain.
- Now: soft-knee `borderGlowRaw / (1.0 + borderGlowRaw * 0.35)` (7.0 → ~2.03), then `min(..., 1.5)` cap on the glow contribution. Bass still multiplies inside the raw term, so the border keeps pumping with the beat.
- Added a gentle safety-net reinhard on the final color that only compresses channels above 1.0 (`col / (1 + max(col - 1, 0) * 0.3)`), so LDR content passes through untouched.

### 2. Spring-damper portal glide
- Critically-damped spring on the portal center: stiffness `k = 90.0`, damping `c = 2·sqrt(k)` (damping ratio exactly 1.0 — no oscillation, smooth glide).
- Raw mouse (`u.zoom_config.yz`) remains the spring target; the springed center replaces `mouse` before the fold math.
- State: `extraBuffer[133..134]` = center, `[136..137]` = velocity, `[135]` = last time, `[138]` = init flag (first frame snaps center to mouse, zero velocity).
- `dt = clamp(time - lastTime, 0.0, 0.05)` so tab-switch pauses can't explode the spring. All invocations compute identical values, so the racy-but-identical extraBuffer writes are benign.

### 3. Click counter-rotation bursts
- Ripple loop guarded by `min(u32(u.config.y), 50u)`.
- Each ripple live for 2s (`age = time - ripple.z`, `0 < age < 2`) contributes an angular velocity spike: `sign · exp(-age·2.5) · (1 - age·0.5) · 6.0`, where `sign` alternates per ripple index (`(i & 1) == 1` → −1) so successive clicks kick the mandala into opposite spins.
- The per-frame burst velocity is integrated into a persistent spin phase in `extraBuffer[139]` (`spinPhase += burstVel * dt`), so the spin winds down smoothly instead of snapping back; `spinPhase` is added to the fold angle alongside `time * rotationSpeed`.

## Slider mapping (u.zoom_params, ids/defaults unchanged)

| Slider | id | Drives |
|---|---|---|
| Radius | x | Portal radius `mix(0.1, 0.5, x) * (1 + bass·0.12)` — bass-pulsed portal size |
| Segments | y | Kaleidoscope segment count `floor(mix(3, 16, y) + treble·2)` — treble adds facets |
| Rotation | z | Base rotation speed `z * (0.5 + mids·0.6)` — mids-modulated spin |
| Hardness | w | Portal edge feather `mix(0.01, 0.2, w)` — also widens the glow band |

(These mappings were already shader-specific; kept them and they now additionally interact with the spring center and spin phase.)

## Contract compliance / CAUTION adherence

- Canonical 13-binding layout preserved exactly; no binding added/renumbered; no binding 13.
- `@workgroup_size(16, 16, 1)` kept.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- All sampler reads use `textureSampleLevel(..., 0.0)`.
- Angle-fold kaleidoscope math (segmentAngle fold, aspect-corrected `rel`/`relCorrected`, `newDir * rad`, aspect divide-back, clamped `kaleidoUV`) preserved **verbatim** — the only change inside the fold block is `+ spinPhase` on the angle line, and `mouse` now resolves to the springed center.
- `dataTextureA` packing unchanged: `(mask, border, segments / 16.0, finalAlpha)`.
- extraBuffer used only in `[133..139]` (within [133..255]); no reserved/engine bins touched.
- No reserved WGSL keywords as identifiers (`rawMouse`, `springCenter`, `burstVel`, `spinPhase`, ...).
- No changes to Renderer.ts / types.ts / bindgroups; no packages installed; no other shader or JSON modified.

## Gate result

```
python3 scripts/wgsl_precommit_gate.py --files public/shaders/kaleido-portal-interactive.wgsl
Files checked: 1 | Passed: 1 | Failed: 0 | Workgroup errors: 0 | extraBuffer violations: 0
✅ public/shaders/kaleido-portal-interactive.wgsl — naga OK, bindgroup compatible
```

JSON validated with `python3 -m json.tool` (parses clean).

## Deviations

- None against the brief. Minor note: the spin phase is integrated from burst velocity (`spinPhase += burstVel * dt` in `extraBuffer[139]`) rather than applying the decaying offset directly — this gives the intended "kick into a spin that winds down" feel without an angle snap when the 2s window ends.
