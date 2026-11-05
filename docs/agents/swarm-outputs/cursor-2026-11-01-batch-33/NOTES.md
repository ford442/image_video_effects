# Notes — cursor/batch-33 holographic projection and interference (2026-11-01)

Twelve shaders. Cards are in `BRIEFS.md`. Saved `params` arrays are unchanged. `holographic_interference` keeps the underscore in the id and the file.

Where a file was reading the pointer or the audio from `extraBuffer[133..]` or `plasmaBuffer[1..]`, the picture now uses the live mouse and `plasmaBuffer[0].xyz`. The host clears `extraBuffer` above 132 every frame, and only `plasmaBuffer[0]` is bass/mids/treble. Silence and a released pointer still match the old picture. No new spring was added. Broken spring writers were removed on contour, failure-iridescence, interferometry, and prism.

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| holographic-contour | 60-step twisted lattice, grid ∩ sphere, dotSize / edgeThresh / levels / inkDensity, 0.3 mix with C, ripple ring | pre-ACES linear display RGBA. ACES on writeTexture only. Depth is march distance | Sobel contour ink; reference-beam fringes |
| holographic-crystal | square section, cutoff 0.7, grooves, stepped orders, dispersion phase, spec, click warp, Facets / Tilt / Interference / Dispersion | ACES display RGBA | lit bevel; diagonal caustic |
| holographic-failure-iridescence | thin-film wavelength loop, glitch rows, tears, chroma split, Film IOR, turbulence | pre-ACES linear display RGBA. ACES on writeTexture only | dewetted holes; false reconstruction |
| holographic-flicker | three laser lines, phosphor decay, vertical-hold slip, hex emblem, chroma split, blackout | ACES display RGBA | wavelength speckle; red phosphor smear |
| holographic-glitch | peel fold, shear, ±1 orders, peel shadow, emitter blackout, three history taps | pre-ACES linear RGB + transmission alpha | carrier nulls; scan/grating moiré |
| holographic-interferometry | two-beam cosine, spectral reconstruct, speckle scale, parallax sample, four sliders | pre-ACES linear display RGBA. ACES on writeTexture only | equal-phase contours; coherence envelope |
| holographic-prism | Snell, facet count, hex/circle morph, wavelength caustic, click rings | ACES display RGBA | Cauchy dispersion (§12.2F); TIR flash |
| holographic-projection | speckle boil, Bragg wavelength, refresh band, scan, glitch blocks, four sliders | ACES display RGBA | zero-order leak; replay window |
| holographic-projection-failure | emitter cone, stale tears, lock line, bit crush, block faults, four sliders | pre-ACES linear RGB + carrier alpha | field interlace (§12.2B); dropout burst (§12.2B) |
| holographic-projection-gpt52 | Bragg sinc, thin-film order, scan, Pepper's ghost, Scan Speed left on its 0..5 range | pre-ACES linear display RGBA. ACES on writeTexture only | pendellösung; diffracted walk |
| holographic-shatter | shard grid, flight, click impacts, grating, two-beam ghost, scan sweep, depth alpha | pre-ACES display RGBA | lit bevel; open crack |
| holographic_interference | three-source loop, object path, reference angle, IQ tint at 0.3, carrier, four sliders | ACES display RGBA. C is not read | visibility envelope; wavenumber speckle |

Formula use: Cauchy (§12.2F) only on `holographic-prism`. Field interlace and dropout (§12.2B) only on `holographic-projection-failure`. No other §12.2 row.

`holographic-contour` x-meta names were aligned to the saved param names. The `params` array was not edited. The WGSL still uses the shipped scalar roles (lattice scale, edge gate, fringe frequency, ink).

Floor: `#include "_prelude.wgsl"` on all twelve. Six pasted headers were migrated before the idea edit. 16×16. Exact `textureLoad` of C where C is read. `holographic-contour` and `holographic-prism` now pass Naga (`target` was reserved); both were removed from `wgsl_validation.json` and the ratchet dropped by two.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new on these twelve, catalogs regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
