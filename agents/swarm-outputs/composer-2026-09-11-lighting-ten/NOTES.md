# Lighting-effects ten — batch notes (2026-09-11)

## IDs

`divine-light`, `divine-light-gpt52`, `alpha-aurora-bands`, `aurora_borealis`, `underwater_caustics`, `cinematic-flare`, `dynamic-lens-flares`, `lens-flare-brush`, `neon-pulse-edge`, `sim-volumetric-fake-em`

## Per-shader

### divine-light
- **Kept:** 16-step march, threshold gate, golden tint, motes, halo, sparkle, ripples, four params
- **Ideas:** `hgPhase()` forward scatter per step; depth occlusion along march via `readDepthTexture`
- **A packing:** ACES display RGBA

### divine-light-gpt52
- **Kept:** spring [133..138], Cauchy RGB march, stained-glass mask, Airy rings, four params
- **Ideas:** header documents existing Cauchy / rose-window / Airy (no new overlay)
- **A packing:** ACES display RGBA

### alpha-aurora-bands
- **Kept:** spectral O/N2 lines, 5 layers, wind from mouse, substorm ripples
- **Ideas:** `foldWarp` along windDir; green-line treble shimmer on `.g` only
- **A packing:** ACES display RGBA

### aurora_borealis
- **Kept:** ribbon loop, curl, stars, curtain rays, four params
- **Ideas:** corona crown at crest; reconnection sparks when bass > `C.a` smoothed envelope
- **A packing:** ACES display RGBA; `A.a` stores bass smooth for next frame

### underwater_caustics
- **Kept:** 5-wave Gerstner, Jacobian focus, godRay, absorption, four params
- **Ideas:** dual-frequency beat (0.55× wavelength); particulate glitter in high-focus cells
- **A packing:** ACES display RGBA

### cinematic-flare
- **Kept:** Cooke triplet, streak, starburst, Mie halo, grain, four params
- **Ideas:** lens dirt speckle on axis; veiling glare between light and center
- **A packing:** ACES display RGBA

### dynamic-lens-flares
- **Kept:** ghost loop, halo ring, starburst blades, four params
- **Ideas:** veiling glare along axis; ghost breathing from bass-smoothed `C.a`
- **A packing:** ACES RGB in A; bass envelope in A.a

### lens-flare-brush
- **Kept:** brush falloff, streak, orbital ghosts, starburst, four params
- **Ideas:** wet smear from exact C along drag; caustic sparkle at ghost centers
- **A packing:** ACES display RGBA

### neon-pulse-edge
- **Kept:** Sobel, softEdgeDist from `C.r`, multi-layer bloom, four params
- **Ideas:** gradient-oriented rim along Sobel normal; treble sub-harmonic strobe
- **Floor:** ACES on output; A stores edge telemetry + display; `C.r` = edge magnitude for halo
- **A packing:** edge mag in C.r; ACES display in writeTexture/A

### sim-volumetric-fake-em
- **Kept:** E/B fields, bent radial march, ripple charges, four params
- **Ideas:** Faraday hue twist; Lichtenberg branches at high fieldMag
- **Floor:** `dataTextureA` write, ACES, exact C temporal blend
- **A packing:** ACES display RGBA

## Gates

- Naga: 10/10
- extraBuffer new: 0
- dead sliders new: 0
- SKIP_WASM_BUILD=1 build: green
- Jest: 652 pass / 6 fail (pre-existing WASM bridge)
- Real-GPU visual QA: external
