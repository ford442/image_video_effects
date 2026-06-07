# polka-wave — Kimi Batch B Notes

## What I Changed
- Transformed monochrome halftone into true CMYK 4-color separation with canonical print angles (15°, 45°, 75°, 90°).
- Mouse ripple now inverts dot polarity (dots become holes, holes become dots) inside the ripple radius.
- Bass globally inflates all dot radii; treble adds per-cell micro-dot noise.
- Added `rot2D`, `aa_step`, and `bass_env` helper functions.

## What I'm Proud Of
The CMYK separation with proper angled dot grids genuinely looks like a Risograph print. The polarity inversion on mouse ripple feels like pressing a finger into wet ink.

## What Might Need a Human Eye
- The loop over 4 channels per pixel is the most expensive part — 4× texture samples inside the loop. On integrated graphics at 2048² this may drop below 60fps.
- The `paperWhite` background color (0.96, 0.96, 0.94) is subtle — verify it reads correctly against all input images.
