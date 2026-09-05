# Balanced Mixed Eight — Ownership and Briefs — 2026-08-27

## Ownership

This dated batch owns only the following pre-gated, single-pass shader and
definition pairs:

1. `alpha-hdr-bloom-chain`
2. `magma-fissure`
3. `paper-burn`
4. `cyber-hex-armor`
5. `pp-chromatic`
6. `sequin-flip`
7. `rorschach-inkblot`
8. `alpha-depth-fog-volumetric`

The cohort was absent from the live claim/state files when work began. No
renderer, bind-group, multipass, public TypeScript API, preset value, ID, or URL
is owned by this batch. `waveform-glitch` remains excluded because its unrelated
baseline WGSL parser failure is outside this cohort.

## Shared contract

- Preserve bindings 0–12 and `@workgroup_size(16, 16, 1)`.
- Read feedback C only with bounded `textureLoad`; write feedback A only.
- Do not write B or `extraBuffer`.
- Preserve every saved `params` object and value; add indexed
  `updatedParams` only.
- Use real `plasmaBuffer[0].xyz` bass, mids, and treble response.
- Provide pointer-position, held, and bounded age-checked click-front response.
- Apply ACES to presentation and emit effect-specific semantic alpha.
- Preserve depth pass-through and the existing A packing for stateful effects.

## Effect briefs

- Bloom: temporal multi-ring spectral bloom; A remains raw HDR RGB plus
  overexposure.
- Magma: neighbor-diffused branching heat, cooling crust, and heat haze; A
  remains heat in R.
- Paper: anisotropic fibers, ember-front diffusion, char width, and ash; A
  remains burn state in R.
- Armor: articulated plates, bevels, seams, and circuit traffic; A becomes
  display history.
- Chromatic: five-wavelength Cauchy dispersion, movable lens center, and
  caustic persistence; A becomes display history.
- Sequins: articulated disk flips and GGX microfacet backs; A becomes display
  history.
- Rorschach: mirrored curl-noise advection with chromatic diffusion; A remains
  display history.
- Fog: seven depth layers, turbulent extinction, and live warm-to-cool color
  temperature; A remains display RGB plus transmittance.
