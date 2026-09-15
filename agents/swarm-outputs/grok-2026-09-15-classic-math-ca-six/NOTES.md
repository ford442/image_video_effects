# Classic math / CA leftover six — NOTES (2026-09-15)

Per shader: kept verbatim, packing, which ideas are in the diff.

## gen-rgb-diffraction

- KEEP: 6 slits, 6-fold fold, sinc² envelope, R/G/B lambdas, slider roles, hsv shimmer.
- ADD 1: `blazeEnv = 1 + blaze * proj` inside `slitIntensity`.
- ADD 2: second slit pass at `freq * 2` (m=±1 ghosts).
- A packing: ACES display RGBA; exact `textureLoad` C.
- Floor: ACES, audio clamp, pointer tilt, click phase kick. No springs.

## gen-verlet-cloth-wind

- KEEP: 64×64 height/vel, pinned top, Laplacian springs, wind noise, silk lighting, held poke.
- ADD 1: `warpRidge`/`weftRidge` from lattice UV.
- ADD 2: `storedLap` in A.b; crease shade from |laplacian|.
- A packing: lattice raw (h, v, lap, 0); off-lattice ACES display RGBA.
- Floor: A written every texel; click gusts; mids/treble. No new springs.

## gen-sierpinski-tetrahedron

- KEEP: 4-vertex IFS, edge capsules, shell trap, jewel + Schlick, slider roles, warp/curl/worley.
- ADD 1: face-centroid trap `F[4]`.
- ADD 2: `genIdx` jewel layer.
- A packing: raw (minTrap, trapIdx, density, alpha); ACES on writeTexture only.
- Floor: deleted extraBuffer[0..5] (engine+FFT); live plasmaBuffer[0]; clickPulse from mouse_down.

## gen-cellular-automata-tapestry

- KEEP: Gray-Scott 3×3, feed/kill sliders, luma-modulated rates, A/B in A.xy.
- ADD 1: warp/weft from nextA/nextB.
- ADD 2: Pearson spots/worms/maze glaze from (kill−feed).
- A packing: raw (nextA, nextB, weave, 1). Dropped chemical-as-color C mix (packing lie).
- Floor: native colormap (no plasmaBuffer[idx]); dt from bass not config.y; held nutrient; click B inoc; ACES on display.

## gen-turing-morphogenesis

- KEEP: closed-form activatorInhibitor, spots/stripes/labyrinth, organicColor, mouse deposit.
- ADD 1: inhibitor halo from gAI.y around spots.
- ADD 2: chemical-front ridges at |gDiff|≈0.
- A packing: ACES display RGBA.
- Floor: bounds guard; mids/treble; alpha no longer multiplied by possibly-zero depth.

## gen-buddhabrot-aura

- KEEP: z²+c loop, 4-sample φ offsets, orbit trap, escape density, aura/bloom, slider roles.
- ADD 1: Nebulabrot early/mid/late → RGB.
- ADD 2: anti-Buddhabrot interior for non-escaping orbits.
- A packing: ACES display RGBA; exact textureLoad C.
- Floor: audio clamp; click c-kick. No springs.
