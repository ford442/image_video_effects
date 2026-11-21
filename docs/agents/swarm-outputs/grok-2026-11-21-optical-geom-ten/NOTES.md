# Notes — optical / geometry ten (2026-11-21)

Idea Cards were written first in `BRIEFS.md`. Saved `params` were not renamed or re-defaulted. ACES stays on the display path. Where A was already a raw field, that write stayed raw.

Formulae, each new on one file: field interlace (§12.2B) on `crt-clear-zone`; energy-conserving bloom (§12.2F) on `infinite-fractal-feedback-hdr`; Airy disc (§12.2F) on `spec-importance-sampled-bokeh`. No other §12.2 row is new. Cauchy on `pp-chromatic` was already there. No shared spring, shockwave, or palette was added. Springs and click paths that were already in a file were left in place.

Seven shaders had a pasted binding header (`pp-chromatic`, `pixel-storm`, `gen-temporal-motion-smear`, `infinite-fractal-feedback-hdr`, `gen-hyperbolic-tessellation`, `solarize-warp`, `spec-importance-sampled-bokeh`). They now `#include "_prelude.wgsl"`. That migration is not the upgrade.

`gen-temporal-motion-smear` and `gen-klein-bottle-walk` had slider roles only under `x-meta`, which the app does not read. Top-level `params` were added with those same names, ranges, and defaults so the four sliders load. No existing param was edited. `gen-temporal-motion-smear` features were empty; they now list audio, temporal, depth, and upgraded-rgba. The header no longer claims mouse-driven. `infinite-fractal-feedback-hdr` and `spec-importance-sampled-bokeh` gained `"upgraded-rgba"` (and the fractal gained audio and mouse, which the shader already did). `crt-clear-zone` and the fractal gained an `x-meta.upgrade.params` block aligned to the saved params.

## pp-chromatic

- Kept: Chromatic Amount, Distortion, Vignette, Mode, the r²+r⁴ warp, five Cauchy bands, the radial/axial/tangent mode mix, longitudinal defocus, purple fringe, click fronts, spectral caustic, exact-C fringe persistence.
- Added: Petzval field curvature — focal depth bows with field angle squared, sign from Distortion; comatic smear — red and violet samples take an extra radial kick from that same field angle, green stays the reference. Both scale with Chromatic Amount.
- A packing: ACES display RGBA. Unchanged.

## crt-clear-zone

- Kept: Distortion, Aberration, Clear Radius, Scanlines, barrel, slot mask, corner misconvergence, beam raster, phosphor from C, halation, degauss wobble, purity blotches, the clear-zone mix.
- Added: field interlace (§12.2B) — odd lines sample a scanline late, scaled by Scanlines, under the mask that stays put; H-sync recovery — the picture bows at the left of each line and settles, scaled by Aberration.
- A packing: ACES display RGBA. C is the phosphor image.

## pixel-storm

- Kept: Storm Strength, Chaos, Trail Length, Radius, the spring in `extraBuffer[133..138]`, radial wind, chaos rotation, sector voices, click cells, suck-while-held, luma debris, exact-C advection.
- Added: pixel blocks — while the wind is up, Chaos snaps the sample to a grid; eye-wall jet — a tangential ring at 0.72 of Radius, added before the suck reversal.
- A packing: ACES display RGBA. Unchanged.

## gen-temporal-motion-smear

- Kept: Trail Persistence, Motion Sensitivity, Smear Directionality, Color Intensity, luma-difference times the history gradient, warm-fast / cool-slow tint, max-blend trail, hue shift from trail age. Directionality still scales blur length, and 0 still means no directional step.
- Added: shutter tent — the same eight taps, weighted so the head is full and the tail thins; upstream trail — the ghost is loaded from C one motion-step upstream. History taps are exact `textureLoad`. A bounds guard was added.
- A packing: ACES display RGBA. C is that trail.

## infinite-fractal-feedback-hdr

- Kept: Zoom Rate, Spiral Tightness, Color Shift, Feedback Strength, the spring focal point, the polar fract and 6-fold, the hue ring, click fronts, the source sample at `sampleUV`.
- Added: fractal preimage feedback — Feedback Strength mixes C at `sampleUV`, not at this pixel; energy-conserving bloom (§12.2F) — four taps around that sample spread highlight, and the core is dimmed by the same luma gate.
- A packing: clamped linear feedback RGB in A, C read as that color, ACES on `writeTexture` only. Previously A stored ACES and it was mixed back into linear.

## gen-hyperbolic-tessellation

- Kept: Tile Symmetry, Depth Color, Rotation Speed, Boundary Glow, the Möbius move, the kaleidoscope fold, ideal vertices, origin horocycles, circle-inversion geodesics, inversion-parity coloring, click glow.
- Added: Poincaré area darkening — the tile fill, not the lines or the rim glow, is multiplied by a softened (1−r²); ideal-point horocycles — circles crowded toward a boundary point that drifts with Rotation Speed, gated by Boundary Glow.
- A packing: raw HDR RGB + coverage alpha. ACES on display only. Unchanged.

## gen-klein-bottle-walk

- Kept: Walk Speed, Texture Density, Light Intensity, Color Shift, `kleinBottlePoint`, the seam flip of normal and texture u, chart lines, the pinch specular, the footprint from C, diffuse and specular.
- Added: sheet hue transport — the flipped sheet offsets hue by half a turn times Color Shift, and saturation stays on that slider; Gaussian curvature tint — saddles cool and elliptic regions warm, mixed a little into the lit color.
- A packing: ACES display RGBA. C is the footprint color.

## solarize-warp

- Kept: Twist Strength, Solarize Threshold, Effect Radius, Effect Intensity, the Sabattier highlight invert, the luma Mackie line, the spring, the conveyor, click fronts, split-tone, the flat C mix outside the brush.
- Added: per-channel Sabattier — red crosses a little below the threshold and blue a little above, scaled by Effect Intensity, and the split is zero when intensity is; re-exposure along the Mackie line — a partial invert of last frame, weighted by source-luma proximity to the threshold.
- A packing: ACES display RGBA. Unchanged.

## spec-importance-sampled-bokeh

- Kept: Bokeh Radius, Highlight Shape, Brightness Boost, Chromatic Aberration, the 48-tap golden spiral, the luma power, the per-tap chroma split, the focus spring, depth defocus, click sharp rings, the center sharp blend.
- Added: cat's eye — the disk is squeezed along the field vector, more as Bokeh Radius grows, and the centre stays round; Airy disc (§12.2F) — bright taps take a diffraction profile of r/radius, dim taps keep the flat disk. Highlight Shape is still the luma power.
- A packing: linear bokeh RGB + importance alpha in A. C is unread. ACES on `writeTexture` only. That split was already how the file wrote.

## gravity-lens

- Kept: the four numeric slider roles as the shader already uses them (mass, ring width, chromatic split, dark-matter), the lens equation, the inner counter-image dim, blackbody redshift, the 3-lobe accretion arc, the photon ring, subhalo caustics, the shadow. Saved param names were not retitled.
- Added: point-mass magnification — the photo is scaled by a clamped 1/|1−(θE/b)⁴|, and inside θE the existing dim still wins; Doppler limb — the 3-lobe arc is multiplied by a slow one-sided brightening.
- A packing: raw lens fields `(b, potential, ringGlow, |deflection|)`. No C reader. Unchanged.
