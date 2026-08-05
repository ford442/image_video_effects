# gen-phase-transition-memory-weave — Interactivist upgrade notes (Batch 36, #329)

205 → 295 lines (+90). Gate: **PASS** (naga OK, bindgroup compatible, workgroup OK, 0 extraBuffer violations).

## What changed

**Bug fixes (contract compliance)**
- Shader previously **never wrote dataTextureA** — now writes state every frame
  (`r=order, g=memory weave, b=flow magnitude`).
- Depth was flat `0.0` → real relief depth: `0.1 + order*0.5 + lattice*crystalFrac*0.25
  + press*mouseForce*0.15` (clamped, near=1 on crystalline lattice).
- Alpha was hardcoded `1.0` → semantic alpha from final luminance + phase-boundary
  coverage, premultiplied write.

**Feedback / emergent (the core upgrade — TRUE hysteresis)**
- The old shader *claimed* hysteresis but was stateless. Now the order field relaxes
  toward a **4-tap diffused copy of its own previous frame** (dataTextureC,
  non-filtering `textureLoad`):
  `order = mix(newOrder, laplacian(prevOrder), mix(0.55, 0.96, viscosity))`.
  Viscosity is now genuinely the "material memory" slider.
- Emergent behavior: the diffusion + relaxation loop makes phase domains **coarsen
  over time** (spinodal-decomposition-like), phase changes lag inputs (supercooling
  vibe), and the memory-weave ghost channel (`g`) is itself temporal
  (`mem = mix(memoryPattern, prevMem, memK)`).

**Mouse (toolkit: spring-smoothed follow, velocity-aware stirring, nucleation)**
- Spring state in extraBuffer[133..136] (k=70, d=11, h=0.016, clamped), prev-down in
  [137], **temporally smoothed bass in [138]** (drives slow, lagging phase thresholds —
  a second hysteresis timescale). Single writer + arrayLength guard.
- Mouse affects ≥2 parameters: (1) **click-hold nucleates crystalline order** locally
  (Gaussian well, treble-boosted), (2) **mouse velocity stirs/melts** the fluid phase
  (negative order force + amplified local flow + cyan stirred-wake highlight).

**Click fronts (guarded)**
- Ripple loop with `min(u32(u.config.y), 50u)`, finite ages (0–4 s), spatially local
  expanding **crystallization fronts** that raise order along the ring and feed a
  bounded `boundaryBoost` into the phase-boundary glow. All intensities non-negative.

**Audio**
- plasmaBuffer bands preserved; bass now routed through the smoothed-bass state for
  order thresholds. Guarded FFT bins 1–8 (extraBuffer[6..13]): high bins sharpen
  lattice scale, low bins boost fluid shimmer amplitude.

## Sliders (all LIVE, unchanged contract)
- p1 Viscosity → temporal relaxation constant (real hysteresis strength) + flow advection
- p2 Phase Scale → pattern scale (unchanged mapping)
- p3 Transition Sharpness → crystalline fraction exponent (unchanged)
- p4 Glow Intensity → final exposure + lattice glow (unchanged)

## Perf estimate
Adds 5 `textureLoad`s + O(1) state/FFT math per pixel over the previous version; the
noise budget (≈9 smoothNoise calls) is unchanged. ≈1.15× previous cost — trivially
60 fps at 1080p.

## JSON
Additive only: tags `+ mouse-driven, hysteresis, feedback`. `updatedParams` byte-exact.
