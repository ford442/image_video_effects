# Upgrade Notes — Grok (`cursor/batch-13`, 2026-10-27)

Twelve mouse-driven force shaders: shockwaves, elastic surfaces, magnetism, gravity, ripples. Idea cards are in `BRIEFS.md` (written first). Each file keeps its previous mechanism and gains two ideas. Saved `params` are byte-exact.

Eight pasted headers were migrated with `migrate_to_prelude.py` (`sonic-boom`, `elastic-strip`, `elastic-surface`, `magnetic-edge`, `magnetic-rgb`, `slinky-distort`, `mouse-magnetic-pixel-sand`, `quantized-ripples`). `luma-force`, `pixel-repel`, `neon-ripple-split`, and `mouse-gravity` already included the prelude. That swap is not the upgrade.

`magnetic-rgb`, `slinky-distort`, `mouse-magnetic-pixel-sand`, and `quantized-ripples` display writes are now ACES. Stored residue, echo history, and the haptic field are not. `slinky-distort` keeps linear colour in A so the echo is not tone-mapped twice.

`sonic-boom` no longer reads `plasmaBuffer[2/4/6]`. `elastic-strip` no longer reads `plasmaBuffer[band+1]`. Those shimmers are bands of `plasmaBuffer[0]`. Dead-bin fixes, not ideas. `sonic-boom` now loads the ring tail with `textureLoad`.

`x-meta.upgrade.params` was added, mirroring saved params, on `luma-force`, `pixel-repel`, `magnetic-rgb`, `slinky-distort`, `mouse-magnetic-pixel-sand`, and `quantized-ripples`. `quantized-ripples` gained `upgraded-rgba` because the display write is ACES and the ideas are in the file. Saved `params` were not renamed or re-defaulted. `neon-ripple-split` and `slinky-distort` keep their shader mapping where it disagrees with the JSON labels.

Real-GPU visual QA was not run. This VM has no hardware GPU.

Gates: Naga 12/12, precommit gate 12/12, extraBuffer clean, dead sliders clean on these 12 (0 new), `generate_shader_lists.js`. Vitest 169 files: 1435 passed, 1 skipped. `SKIP_WASM_BUILD=1 npm run build` succeeded.

## Per shader

### sonic-boom
- Kept: PHI ring stack, sprung center in `extraBuffer[133..137]`, click bursts, diamonds, condensation, Doppler split. A stays ACES display RGBA. C.r stays the ring tail.
- Added: the primary ring is steep outside the radius and soft inside, and that shoulder pulls; a moving spring is loud in the wake and quiet ahead.
- Formula: none.

### elastic-strip
- Kept: V/H axis swap, damped oscillator, nested bevel, soap film, held drag, click pluck packets. A stays ACES display RGBA.
- Added: second and third harmonics with a node at the pluck point; stretched strips desaturate toward luma.
- Formula: none.

### elastic-surface
- Kept: Verlet step, 4-neighbour Laplacian, mouse push/pull, ripple impulses, Poisson offset. A stays raw `(disp.xy, vel.xy)`.
- Added: a 2-texel Laplacian snaps short waves; compressed sheet wrinkles along the tangent and catches the specular.
- Formula: none.

### luma-force
- Kept: luma gradient, curl, isoline vortex, 5-tap memory, spectral fringe. A stays raw `(mem.xy, |drive|, contrast)`.
- Added: memory accepts new drive slowly on a strong gradient; the luma drive compresses above mid-grey.
- Formula: none.

### pixel-repel
- Kept: four superellipse lobes, 7-tap spectral fringe, pile-up crest, drag wake, pointer texels `(0,0)` and `(1,0)`.
- Added: spectral taps snap to a cell that grows with Strength and blends back with Smoothing; positive divergence darkens the photo.
- Formula: none.

### neon-ripple-split
- Kept: shader mapping (x shear, y speed, z glow, w frequency), crest RGB split, seam, gravity well, bass envelope at A `(0,0)`. Other texels stay linear pre-ACES.
- Added: a slower envelope groups the carrier; the seam and crest glow desaturate the photo under the tube.
- Formula: none.

### mouse-gravity
- Kept: lens factor, frame-drag swirl, tidal stretch, Doppler photon ring, click wells, pointer-state texels.
- Added: a caustic of the lensed photo where the magnification factor crosses zero, once that curve has cleared the core; the well mixes a little of the previous frame.
- Formula: none.

### magnetic-edge
- Kept: gradient normal/tangent mix, spring in `extraBuffer[133..138]`, flux lines, signed click shock. A stays ACES display RGBA.
- Added: a moving spring bends the pull toward its velocity on an edge; last frame's edge alpha keeps more of the picture after the magnet leaves.
- Formula: none.

### magnetic-rgb
- Kept: red in, green swirl, blue out, bass surge, divergence alpha, filing noise. C unread.
- Added: filings follow a short bar so lines leave one side of the cursor and enter the other; line spacing tightens where the field is strong.
- Formula: none. ACES on the display write.

### slinky-distort
- Kept: shader roles (x coils, y amplitude, z depth weight, w tightness), spiral phase, torsion, treble compression, lagged echo, advanced alpha.
- Added: coil frequency rises toward the cursor; one side of each wrap darkens and the crest stays the highlight.
- Formula: none. A stays linear. ACES on the display write only.

### mouse-magnetic-pixel-sand
- Kept: luma susceptibility, radial pull, ripple polarity, chain taps, residue decay. A stays `(residue rgb, settled)`.
- Added: the live pull is zero until the field clears a small threshold; a Grain Size pitch cuts gaps between filing links.
- Formula: none. ACES on the display write only.

### quantized-ripples
- Kept: three decay shapes, click-to-click velocity, level quantization, touch sine. A stays raw `(effectStrength, shimmer, roughness, alpha)`. C unread.
- Added: a second harmonic travels at `1/sqrt(2)` the phase speed; the level count drops on the crest.
- Formula: deep-water dispersion (§12.2D). Only this file. ACES on the display write only.
