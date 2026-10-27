# Image-reactive fireworks: Idea Cards

These four related image shaders are the batch. The neighboring generative
fireworks already have named, developed upgrades, so they are not included.
Cards were written before editing the WGSL.

## fireworks-depth-parade

**Identity:** Image-colored fireworks launch in three staggered depth layers.

**Keep verbatim:** Three depth bands, depth-matched probes, staggered shell and
click launches, slider roles, ballistic sparks, and display-color feedback.

**Add:**
1. Depth occlusion — let the image's foreground partially veil shells behind
   it, so the existing depth layers interact with the photo.
2. Atmospheric distance — soften and desaturate the background sparks, giving
   the existing far layer a distinct aerial perspective.

**Forbid:** Generic ripples, palette replacement, or a new scene.

**A packing:** ACES display RGBA; C reads display RGB. Existing B is a dimmed
display/previous-color auxiliary echo.

## fireworks-edge-ignite

**Identity:** Image contours ignite and launch colored fireworks.

**Keep verbatim:** Contour threshold, source-colored shells, ballistic paths,
click and held-pointer behavior, slider roles, and display-color feedback.

**Add:**
1. Contour-tangent shell spread — favor trajectories along the local image
   edge while retaining the radial shell.
2. Traveling ignition — a smooth moving light runs along detected contours,
   making the existing ignition lines feel like a burning fuse.

**Forbid:** Unrelated scene geometry, generic cursor overlays, or palette theft.

**A packing:** ACES display RGBA; C reads display RGB. Existing B is a dimmed
display/previous-color auxiliary echo.

## fireworks-patriotic-july4

**Identity:** Image-derived red, white, and blue fireworks over waving stripes.

**Keep verbatim:** Patriotic palette mix, radial ballistic shells, stripe wave,
star field, pointer effects, slider roles, and display-color feedback.

**Add:**
1. Tricolor shell breaks — arrange the existing shell stars into three slightly
   different radii and red/white/blue color groups.
2. Star diffraction — add small crossed rays to the existing sky pin-stars,
   controlled by the existing sparkle and twinkle.

**Forbid:** A replacement palette, generic shockwaves, or a different holiday.

**A packing:** ACES display RGBA; C reads display RGB. Existing B is a dimmed
display/previous-color auxiliary echo.

## fireworks-portrait-burst

**Identity:** Bright image regions detonate into source-colored portrait sparks.

**Keep verbatim:** Brightness threshold, source-derived launch colors, dissolve,
ballistic shells, mouse behavior, warmth role, and display-color feedback.

**Add:**
1. Highlight bloom — a brief broad halo from each qualified bright image core
   emphasizes the portrait highlight that launched the shell.
2. Cooling embers — each shell gradually shifts from source color toward its
   existing warm ember palette as it ages.

**Forbid:** Replacing the portrait with unrelated geometry or a generic palette.

**A packing:** ACES display RGBA; C reads display RGB. Existing B is a dimmed
display/previous-color auxiliary echo.
