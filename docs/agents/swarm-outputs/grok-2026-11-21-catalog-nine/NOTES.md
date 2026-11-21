# Notes — catalog nine (2026-11-21)

Idea Cards were written first in `BRIEFS.md`. Saved `params` were not renamed or re-defaulted. ACES stays on the display path. Where A was already a raw field, that write stayed raw.

Formulae, each new on one file:

- Schmitt-trigger lock (§12.2B) and field interlace (§12.2B) on `vhs-tracking` only.
- Cauchy dispersion (§12.2F) on `chroma-lens` only.
- Block DCT quantization (§12.2B) on `datamosh-brush` only.
- Dropout bursts (§12.2B) on `digital-decay` only.

No shared spring, shockwave, or palette was added. Springs and click paths that were already in a file were left in place.

Three shaders had a pasted binding header (`chroma-lens`, `steamy-glass`, `voronoi`). They now `#include "_prelude.wgsl"`. That migration is not the upgrade.

`tensor-flow-sculpt`, `physarum`, and `voronoi` gained an `x-meta.upgrade.params` block aligned to the saved params. No existing param was edited. `physarum` gained `"upgraded-rgba"` because the display write is now ACES. The sim fields in A are not tone-mapped.

## tensor-flow-sculpt

- Kept: Sculpt Depth, Freq Separation, Curvature Scale, Anim Speed, the structure tensor and eigenpair, Hessian curvature, geodesic flow, ripple sculpt force, frequency split, contour LIC, principal-axis chroma, ridge glow, dome/saddle sheen, clay creep, flowStr 0.3, persistence 0.6.
- Added: anisotropic yield — the principal-axis geodesic term scales with coherence; rake striations — grooves parallel to the tool, gated by coherence and |mean curvature|, after the sheen.
- A packing: ACES display RGBA. Unchanged. C is that display history, mixed post-ACES.

## physarum

- Kept: Agent Radius, Deposit Opacity, Sense Distance, Trail Decay, seed-on-zero, semi-Lagrangian mass, winner-take-all heading, Jacobian pile-up, three-sensor steer, mouse pull, ripple twist, 3×3 trail blur, vein-above-ring display, transmittance. The mass and heading update was not rewritten.
- Added: leading-edge glint — trail ahead minus trail behind along the stored heading; food bite — dense veins on bright food dull that food. Deposit Opacity still owns coverage.
- A packing: raw sim state (trail, mx, my, 0). Unchanged. ACES is on the display write only.

## vhs-tracking

- Kept: Tracking Error, Noise Level, Color Drift, Scanlines and their roles (walk sigma, azimuth, dropout rate, chroma phase magnitude), the sprung cursor, capstan, head-switch skew, azimuth blur, line-alternate hue flip, head band, dropout mask, DOC line repeat, chroma smear.
- Added: Schmitt-trigger tracking lock (§12.2B) — |walk| past `hi` holds and creeps home until it falls under `lo`; the bit is stored in the row state's second channel, which nothing read. Field interlace (§12.2B) — luma is sampled a fraction of a line off the chroma line, scaled by Tracking Error.
- A packing: raw row state (walk, tracking lock, chroma phase, head band). The dropout mask stays a same-frame display term.

## plasma

- Kept: Orb Radius, Orbit Speed, Plasma Intensity, Shadow Depth, eight orbiting metaballs, wisp noise, velocity trail, photo shadow, arc filaments, luma corona.
- Added: bowed filaments — fbm offsets the segment along its normal, pinched to zero at both orbs; field afterglow — A.a is a decaying envelope of the field, and where it remains above the current field and the previous pixel was brighter than the photo, that color lingers.
- A packing: ACES display RGB, decaying field envelope in A.a. writeTexture alpha stays coverage.

## chroma-lens

- Kept: Magnification, Aberration, Lens Radius, Edge Blur, the barrel curve that is 1 at the rim, seven spectral taps, wavelength colors, tangential plus sagittal blur, rim runners, click fronts, held radius growth.
- Added: Cauchy spacing (§12.2F) — the ±abbStrength offset follows n(λ)=1+B/λ², still −1 at red and +1 at violet; zonal spherical aberration — an r²(1−r²) dip in the existing curve, zero at the center and at the rim.
- A packing: pre-tone-map lens colour RGBA. Unchanged. C is not read. writeTexture stays ACES.

## datamosh-brush

- Kept: Brush Size, Block Crush, Decay Rate, Effect Threshold (still the ghost alpha), the spring and its smear, click corruption, DC hold, mosquito ring, macroblock edge tint. C stays display color.
- Added: block DCT quantization (§12.2B) — inside the brush, color is rounded to a step from Block Crush, after the DC hold; held motion vector — a second sample uses `floor(time × Decay Rate)` as the hash key, mixed into the per-frame glitch.
- A packing: ACES display RGBA. Unchanged.

## steamy-glass

- Kept: Fog Density, Fade Speed, Wipe Radius, Blur Amount, steam relaxation, droplet growth, nucleation runoff, beaded wipe rim, click clear, refraction, Beer transmittance. The four sim fields stay the four sim fields.
- Added: low-pane linger — the return toward Fog Density is weaker at the top and stronger at the bottom; contact line — a steep droplet gradient that is not a solid bead darkens the glass.
- A packing: raw sim (steam, droplets, runoff, wipe memory). Unchanged. ACES on writeTexture only.

## voronoi

- Kept: Cell Density, Jitter, Ridge Strength, Palette Shift, the 3×3 Worley, tectonic drift, pointer pull, six-ripple swirl, cell-center photo sample, palette mix, ridge ink, treble sparkle. The palette index into `plasmaBuffer` stays; it is Palette Shift.
- Added: feature gather — the lattice shifts by the photo luma gradient, scaled by Ridge Strength, before Worley; seed pits — a small darkening where F1 is near zero.
- A packing: ACES display RGBA. Unchanged. C is not read.

## digital-decay

- Kept: Corruption Rate, Block Size, Ghost Decay, Depth Influence, the spring hotspot, click burst, block displacement, bit flips, block tear, stuck row. C stays the ghost color. Zero corruption still forces the clean source.
- Added: dropout bursts (§12.2B) — a sparse row paints an exponential tail along x, rate and length from Corruption Rate; pointer shear — rows in the held hotspot shift by the spring's x velocity. No new spring.
- A packing: ACES display RGBA. Unchanged.
