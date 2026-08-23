# Batch 64 coordinator review — 2026-08-23

Status: **STRUCTURALLY CLOSED** on tracker #511–520.

## Claim

Claimed by draft PR before work began, per the requester's instruction. The
claim commit carried `BRIEFS.md` plus the tracker heading reserving #511–520.

## Scope correction

The request named `glass-refraction.wgsl`, which does not exist in
`public/shaders/`. Candidates were `glass_refraction_alpha` (artistic, 275L,
underscore variant of the requested name) and `glass-refraction-prismatic`
(advanced-hybrid, 215L). The requester confirmed `glass_refraction_alpha`
before any work started.

## Severity ranking of what was found

1. **Audio-buffer corruption (2 shaders, 11 slots).** `optical-feedback` and
   `magnetic-interference` wrote interactive state into `extraBuffer[0..8]`,
   the engine's audio and FFT region. This is cross-shader corruption: any
   other shader in the chain reading `extraBuffer[0..2]` for bass/mid/treble,
   or `[4]` for `historyHead`, got whatever these two last wrote. Both
   migrated; baseline entries retired rather than re-triaged.
2. **`optical-feedback` dt bug.** `u.config.y` (rippleCount) used as delta time
   in a spring integrator: frozen at rest, divergent under clicks.
3. **Three unwired feature claims.** `ambient-liquid` advertised
   `reaction-diffusion` with no state; `glass_refraction_alpha` bound
   `plasmaBuffer` and never read it while calling the mouse button "audioPulse".
4. **Three mask-as-colour hazards** (`cyber-lens`, `bubble-lens`,
   `crystal-facets`) — A held masks nothing read, poisoning C.
5. **One unguarded ripple loop**, two **per-frame hash strobes**, one **dead
   `exitT`** leaving absorption on the wrong path length.

## Verification

Gate 10/10 (naga 30.0.1 + bindgroup + workgroup + extraBuffer); extraBuffer,
dead-slider and audio-mapping audits pass; shader-list URL and uniform-layout
checks pass; lists regenerate clean; Jest and production build green.

Real-GPU visual QA remains external — no WebGPU device in this container. The
claims verified here are structural: compilation, binding contracts, state
ownership, magnitudes and slot ranges.
