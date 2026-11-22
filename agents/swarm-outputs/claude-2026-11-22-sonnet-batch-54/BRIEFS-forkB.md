# BRIEFS — fork B — quantum-foam family (written BEFORE WGSL edits)

Family: Tier-C graph  pass1 (field -> A) -> [A->C] -> pass2 (particles -> B and A) -> [B->C] -> pass3 (composite -> writeTexture).
Params (graph slot, from pass-1 JSON, byte-exact): foam_scale, flow_speed, diffusion_rate, octave_count.

## SHADER: quantum-foam-pass1
IDENTITY: voronoi foam cells over a curl-warped, depth-layered flow field, interference wavefronts; packs warpX, warpY, pattern, cellBoundary into A.
KEEP VERBATIM: 3 depth-layer parallax warp, voronoi + hybridPattern mix, noise4d, three-wave interference, bass/treble gains, voids + wavefront ridges (2026-10-17 ideas), A packing (warpX, warpY, pattern, ridgeBoundary), zoom_params roles x scale / y speed / z diffusion / w octaves, mouse-X depth parallax.
RESCUE: R3 — fbm/curl/voronoi hashed time and position without interpolation = white noise in space AND time. Replace with smooth, time-coherent noise (same signature fbm(p,t,oct)/curlNoise(p,t)); voronoi feature points orbit continuously (no re-hash with time) and use TWO coordinates (HEAD put them on a line y=0.7x).
ADD:
  1. Pair lifetimes — each voronoi cell nucleates and annihilates on its own phase (life = sin^2 of a per-cell clock); the bright core breathes with life and a collapsing cell leaves a transient void. Native: virtual pairs popping in/out of the vacuum.
  2. Flow-sheared cells — the voronoi metric is stretched along the local curl direction (Flow Speed sets the stretch). Native: foam bubbles elongate in shear (direction, not just magnitude).
FORBID: springs, ripple shockwaves, IQ palettes, replacing the voronoi/curl structure.
A PACKING: raw field (warpX, warpY, pattern, ridgeBoundary). No ACES.

## SHADER: quantum-foam-pass2
IDENTITY: particle advection through the pass-1 field: chromatic dispersion by warp/curl, quaternion colour rotation, scintillating emission, spectral power curve; hands (colour, emission) to pass 3 through B.
KEEP VERBATIM: dispersion RGB offsets, comet tail, scintillation (bass), spectralPower, B (and A) write of (finalColor, emission), diffusion slider role, mouse reads for emission threshold / chroma spread (HEAD behaviour, flagged not changed).
RESCUES: R1 — globalIntensity was u.config.y (= rippleCount): no clicks = photo, N clicks = N x. Fixed full intensity. R2 — 'history' was textureLoad(C) = pass 1's warp field blended in as colour; now an exact textureLoad of readTexture one step upstream along the warp (honest advection; C holds no true history in this graph). R4 — rotationSpeed = zoom_config.x*2 = 2*time (angle ~ t^2): bounded, wrapped phase.
ADD:
  1. Bubble lens — the gradient of the pattern field (4 exact C loads) bends the photo like a refracting foam bubble (promoted intermediate: pattern -> lens normal).
  2. Hawking temperature ramp — emission colour follows an ember -> white -> blue-white temperature ramp by flare strength, mixed into the existing plasma hue.
FORBID: ripples, springs, a second noise field, changing the B/A hand-off packing.
A PACKING: B and A = (finalColor.rgb, emission). Not display. No ACES.

## SHADER: quantum-foam-pass3
IDENTITY: volumetric glow along the emission gradient + Beer veil + haze, vignette, grade, ACES, gamma. FINAL pass.
KEEP VERBATIM: flow-smear 3x3 glow, Beer veil, haze, vignette, grade, ACES (display only), gamma (open call, see NOTES), C loads, zoom_params y/z roles.
RESCUE: R1 — globalIntensity = u.config.y (< 0.01 early return = pure photo without clicks): constant full intensity, early return removed.
ADD:
  1. Gravitational redshift — the dense core of the glow (existing `thick`) shifts amber/red, thin halo keeps its hue.
  2. Bass-swollen glow (plasmaBuffer[0].x) — the glow reach and gain breathe with bass. (HEAD pass 3 had no audio.)
FORBID: springs, ripples, bloom stacks, changing the Beer veil.
A PACKING: colour only (writeTexture). ACES on display RGB.

## Card amendments made while implementing (measured, see NOTES-forkB.md)
- pass1 RESCUE grew: besides fbm/voronoi, the warp coefficient into voronoi was x2.0 (slope ~3.8 = fold-over, cells dissolved) -> x0.35; warp octaves capped at 3; nested curlNoise(baseP + curl*lv) replaced by per-layer decorrelated curl lookups.
- pass2 RESCUE R5 added: flare threshold 0.3+0.5*mouseY vs drive 99th pct 0.47 meant 0.05% of pixels ever emitted (glow dormant). Threshold now 0.26+0.1*mouseY, band 0.35.
- pass2 RESCUE R4b: quaternion `rotatedColor` was computed and discarded; now mixed into the comet at 0.25*saturate(pattern).
- pass3 Idea 1 is keyed to its own glow-density `coreHeat = saturate(length(glowColor)*3.5)` rather than `thick` (thick tops out ~0.2 here, so a tilt keyed to it was invisible).
