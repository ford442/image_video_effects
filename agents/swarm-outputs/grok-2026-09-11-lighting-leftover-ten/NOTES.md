# Lighting leftover ten — notes

Per shader: kept verbatim, packing, which ideas are in the diff.

## neon-pulse-edge
KEEP: 3×3 Sobel, HSV from edge angle, four params, mouse boost, plasma XYZ.
A packing: raw edgeMag/depth/gx/gy (not ACES).
Ideas in diff: tangent tube taps (`tangent` loop); `loadEdge` exact-C afterglow.

## sim-volumetric-fake-em
KEEP: E/B fields, ripple orbit charges, JSON param roles, chromatic B split.
A packing: ACES display RGBA every pixel. extraBuffer[133..134] previous mouse (guarded).
Ideas: Beer–Lambert `opticalDepth`/`beer` on bent path; `exbKick` perpendicular.

## sim-volumetric-fake
KEEP: animated lightPos, radial blur, four params.
A packing: ACES display RGBA (new A write).
Ideas: `blocked` vs lightDepth; hashed `mote` sparks on taps.

## volumetric-god-rays
KEEP: density/decay/weight/exposure, 48-sample Mie walk, bass dust.
A packing: switched from raw accumulated RGB to ACES display RGBA (C unused as color).
Ideas: luma extinguishes `illuminationDecay`; `sunDisk` gated by mouse highlight.

## neon-flashlight
KEEP: held squeeze, click fronts, cone ribs, sweep. Remapped sliders to JSON radius/intensity/threshold/ambient.
A packing: ACES display RGBA.
Ideas: umbra/penumbra; `specCatch` on edges inside cone.

## neon-strings
KEEP: harmonics, packet, clickImpulse, exact-C afterimage, blackbody, four params.
A packing: ACES display RGBA.
Ideas: node darkening at 1/2 and 1/3; nut/bridge `endPin`.

## neon-edges
KEEP: five-scale Sobel/Mach, blackbody, tube-current wave, four params.
A packing: switched raw field pack → ACES display RGBA (C unused).
Ideas: inverse-square `invSq` spotlight; `isotherm` Kelvin steps.

## neon-edge-glow
KEEP: neon/mercury spectra, mouse tube bend, electrodes, four params.
A packing: switched field pack → ACES display RGBA.
Ideas: `darkSheath` around tube; 60 Hz `mains` squared-sine.

## anamorphic-flare
KEEP: horizontal streak helper, hex ghosts, central glow. Params remapped to width/intensity/color/threshold.
A packing: ACES display RGBA (new A write). Bounds guard added.
Ideas: `highlightGate` from photo at light; blue-line ghost offset +Y.

## neon-echo
KEEP: per-channel tau, cursor drift, injection, blackbody age, four params.
A packing: raw persistence RGB in A; ACES on writeTexture.
Ideas: `textureLoad` C; P7 yellow-green `p7Tail`.
