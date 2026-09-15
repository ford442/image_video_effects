# Classic math / CA leftover eight — NOTES

Per `docs/SHADER_UPGRADE_BATCH.md` §9. Cards in BRIEFS.md (written first).

## gen-rgb-diffraction
- Kept: 6 slits, 6-fold fold, λ 1.0/0.82/0.68, four sliders
- Ideas in diff: blaze `max(dot(p̂, axis),0)²` in `slitIntensity`; `sinc2(r·freq·λ)` Airy rings
- Floor: ACES, exact C load, plasma clamp, mouse as grating tilt
- A packing: ACES display RGBA

## gen-verlet-cloth-wind
- Kept: 64×64 (h,v) Verlet, pinned y=0, laplacian, bilinear upsample, four sliders
- Ideas in diff: weft/warp tension from |dx|/|dy|; hem flutter near y=63
- Floor: A written for non-lattice display texels; lattice stays raw
- A packing: lattice raw (h,v,stretch,1); else ACES display RGBA

## gen-sierpinski-tetrahedron
- Kept: V/E IFS, orbit traps, jewelColor, C.r minTrap mix, four sliders
- Ideas in diff: inverse-rotated vertex lamps; mid-edge beads on capsules
- Floor: deleted extraBuffer[0..5] audio/mouse springs (engine FFT zone)
- A packing: raw (minTrap, trapIdx, density, alpha)

## gen-3d-sierpinski-chaos
- Kept: chaos game, pickVertex, warmup, saturation exit, held-mouse orbit
- Ideas in diff: 40% die bias to cursor-nearest vertex; iteration-age hue
- Floor: deleted extraBuffer[133] env and extraBuffer[5..12] FFT reads; ACES
- A packing: ACES display RGBA

## gen-chromatic-zonohedron
- Kept: 3-axis zonoFacet/zonoSDF, four sliders, mouse pan
- Ideas in diff: hue from winning generator; vertex stars where f0≈f1≈f2
- Floor: A was (sdf,hue) while C mixed prev.rgb — now display RGBA
- A packing: ACES display RGBA

## gen-quasicrystal-iridescence
- Kept: n-fold quasicrystal + thinFilmColor; slider dual-use x/y as thickness/IOR
- Ideas in diff: Bragg ridges at qc zeros; phason phase from mouse
- Floor: ACES, plasma, exact C mix
- A packing: ACES display RGBA

## gen-turing-morphogenesis
- Kept: closed-form activatorInhibitor, fk spots/stripes/labyrinth, mouse deposit
- Ideas in diff: activator>inhibitor ridges; fk=0.01/0.02 pattern seams
- Floor: bounds guard, mids/treble, semantic alpha
- A packing: ACES display RGBA (patternDensity in A.a as before)

## gen-buddhabrot-aura
- Kept: 4-sample φ offsets, |z|²>4 escape, orbitTrapColor, four sliders
- Ideas in diff: trichrome early/mid/late dwell; anti-Buddhabrot interior ghost
- Floor: exact C load
- A packing: ACES display RGBA

## Gates
Naga 8/8, extraBuffer 0 new, dead sliders 0, catalog 1,367 (unchanged — existing IDs), Jest 689 pass / 6 fail = pre-existing WASM `bridge/api.js`, SKIP_WASM_BUILD=1 build green. Real-GPU QA external.
