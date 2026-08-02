# Swarm Completion: magnetic-luma-sort (kimi, b26)

**Date:** 2026-08-02
**Shader:** `magnetic-luma-sort` (interactive-mouse)
**Role:** Algorithmist

## Summary of Changes

Rewrote `public/shaders/magnetic-luma-sort.wgsl` per the brief:

1. **Priority 1 — dead `finalColor` removed.** The two lines
   `var finalColor = mix(historyColor, srcColor, 0.1);` and
   `finalColor = max(srcColor * 0.2, historyColor * decay);` computed a value
   nothing ever read; both deleted. All surrounding dev commentary preserved
   verbatim; a short new note marks where the experiment was removed. No
   behavior change — `mixed` was always the winner.

2. **Spring-damper attractor.** Critically-damped spring eases the magnet
   toward the raw mouse (raw mouse stays the spring target). State in
   `extraBuffer[133..137]` ONLY (pos.xy, vel.xy, prevTime); every thread
   integrates the same prior state, thread (0,0) writes back. First frame
   (prevTime <= 0) snaps to the cursor. omega = 14.0, dt clamped [0.001, 0.05].

3. **Click vortex pulses.** Ripple loop guarded by
   `min(u32(u.config.y), 50u)`; each live ripple (age 0–3s) adds a decaying
   second attractor at its click point: smoothstep(0.25, 0.0, dist) falloff
   (~0.25 radius) * exp(-rippleAge * 2.0), respecting the attract/repel sign.
   Composed with the main pull (`pull = dir * speed + Σ ripple contributions`)
   BEFORE the offset (`offset = -pull`).

4. **Dead audio wired (plasmaBuffer was declared, never sampled).**
   - Bass (`(plasmaBuffer[1].x + plasmaBuffer[2].x) * 0.5`, clamped) lowers the
     effective luma threshold: `threshold * (1.0 - bass * 0.3)` — beats loosen
     the sort. Gate shape itself kept verbatim.
   - Per-row FFT drift: 8 horizontal bands, each scales its speed by
     `1.0 + plasmaBuffer[(band % 8u) + 1u].x * 0.4`.
   - Definition metadata now truthfully includes `audio-reactive`.

5. **Sliders** wired via `u.zoom_params.x/y/z/w` using the existing JSON param
   ids/names/defaults/ranges, unchanged (saved-preset contract): Pull Strength
   (x*0.05), Luma Threshold (y), Trail Decay (z), Attract/Repel (w, step 0.5).

## Contract Items Preserved Verbatim

- Canonical 13-binding layout (0–12), no renumbering, no binding 13.
- `@workgroup_size(16, 16, 1)`.
- Feedback contract SACRED: `dataTextureC` read as history at the upstream
  offset (`historyUV = uv + offset`, sampled via `textureSampleLevel(..., 0.0)`);
  `dataTextureA` written with `mixed` (same value as `writeTexture`) — no
  tonemapping on the A write.
- `writeTexture`, `writeDepthTexture`, `dataTextureA` written every frame.
- ALL dev thinking-out-loud comments kept verbatim ("Read history (trail)…",
  "Dampen speed by distance? Maybe infinite reach is better.", "Let's try a
  blend:…", "Alternative: If the pixel is bright enough…", "Let's stick to the
  feedback loop approach.", "If luma is low…", etc.).
- `get_luma` helper, threshold speed gate, aspect correction
  (`dirToMouse.x *= aspect`), attract/repel step (`if (repel > 0.5) { dir = -dir; }`)
  — all verbatim.
- Trail Decay range 0.5–0.99 exact in JSON; all 4 param ids/names/defaults
  unchanged.
- extraBuffer touched in [133..137] only (within the [133..255] shader-owned
  region); engine FFT [5..132] and reserved [0..4] untouched.
- Engine truth respected: config=[time, rippleCount, resW, resH],
  zoom_config=[time, mouseX, mouseY, mouseDown].

## Line Count

116 → **188** (+72, within the +50/+90 envelope; target 166–206 ✓)

## Validation

- `naga public/shaders/magnetic-luma-sort.wgsl` → **Validation successful**
  (no errors, no warnings).
- `shader_definitions/interactive-mouse/magnetic-luma-sort.json` — additive
  `updatedParams` mirror index 0–3 + `updated: true`, plus the truthful
  `audio-reactive` feature; source `params` remain exact and JSON parses clean.
- Did NOT run `wgsl_precommit_gate.py` (coordinator runs it centrally); no git
  commands; no other files modified.
