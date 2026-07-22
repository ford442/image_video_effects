# Notes: topological-acoustic-knots (b14, Algorithmist)

**Date:** 2026-07-22
**Agent:** Kimi (swarm, b14)

## Line delta

- Before: 180 lines → After: 247 lines (**+67**, within the +50–90 target; final count inside 230–270 band).

## Key changes per technique

1. **Honest 'Defect Density' (p1 / zoom_params.x):** removed p1 from the tone-gain
   (`acesToneMap(hdr * (0.8 + p1*0.3))`) and rewired it to the Kibble-Zurek quench
   amplitude: `quenchNoise = (hash12(...) - 0.5) * bass * 0.18 * (0.5 + p1)`. The
   slider now literally controls how many defect pairs nucleate per bass hit.
2. **Annihilation cascades (p3 / zoom_params.z):** added 4 diagonal neighbor reads
   (ne/nw/se/sw — purely additive; the order-dependent n/s/e/w line integral is
   untouched). East/west plaquette winding estimates are computed; where their
   signs oppose (`chargeEast * chargeWest < -0.0005`), p3 damps the local charge
   (`chargeRaw * (1 - annihilation*0.55)`) and melts the order parameter
   (`Sann = S * (1 - annihilation*0.5)`), which is what gets stored to
   dataTextureA.
3. **Defect census + cascade pulse (extraBuffer[133..135]):** thread (0,0) runs a
   coarse 16×16 census of last frame's defect-density field (dataTextureC .a),
   keeps a smoothed count in [133], previous count in [134]. A sharp drop
   (> 0.6) = annihilation cascade → pulse injected into [135] (decays ×0.90/frame).
   All threads read [135] and add it as a brief global exposure pulse
   (`hdr * (0.85 + cascadePulse * 0.7)`).
4. **Sweeping polarizer (extraBuffer[136]):** polarizer angle is now accumulated
   persistently (`+0.004 + mids*0.035` per frame by thread (0,0)) instead of the
   fixed `time * 0.3`, so schlieren polarization bands sweep and accelerate with
   mids energy.

## Contract compliance

- Canonical 13-binding layout unchanged; no new/renumbered bindings.
- `@workgroup_size(16, 16, 1)` kept; writeTexture/writeDepthTexture/dataTextureA
  written every frame; all sampler reads use `textureSampleLevel(..., 0.0)`.
- dataTextureA write is raw signed Q-tensor state (Qxx, Qxy, S, defectDensity) —
  never clamped/tonemapped.
- Angle-periodicity math preserved EXACTLY (`0.5*atan2(2*Qxy, 2*Qxx)`, sin/cos
  neighbor averaging); charge line integral neighbor order untouched.
- extraBuffer state confined to indices [133..136] ⊂ [133..255]; [0..4] reserved
  and [5..132] FFT bins untouched.
- No WGSL reserved identifiers introduced.
- JSON: added `updatedParams` (4 entries, index 0–3, names/defaults/min/max/step
  mirroring existing params) and `"updated": true`. Nothing else changed; param
  ids/defaults untouched (preset contract).

## QA flags

- extraBuffer reads/writes across threads are intentionally racy-but-benign
  (single writer thread (0,0), others read previous-frame-ish values) — standard
  pattern for this engine's persistent-state shaders.
- Census is a 256-tap coarse estimate; count is smoothed (mix 0.25) so the
  cascade trigger threshold (drop > 0.6) may need tuning on real audio input.
- p2 (mobility) and p4 (mouse pinning) wiring was already shader-specific and
  was left as-is.

## No-GPU caveat

Validated via `scripts/wgsl_precommit_gate.py` (naga OK, bindgroup compatible,
0 workgroup errors/warnings, exit 0) and JSON parse check. This VM has **no GPU
adapter** — visual QA (schlieren sweep feel, cascade pulse visibility,
annihilation melt look) is **deferred to real hardware**.
