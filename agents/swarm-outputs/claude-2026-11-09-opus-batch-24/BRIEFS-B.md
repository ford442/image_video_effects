# Fork B Idea Cards (written before WGSL)

SHADER: recursion-mirror-vortex
IDENTITY: nested Möbius/abs-fract mirror folds around a mouse singularity, blended over the image.
KEEP VERBATIM: vortexTwist, mobiusFold loop, box/sphere fold, seam glow, 4 param roles.
ADD: 1. per-reflection mirror absorbance — each fold bounce loses ~10% with a silvered-glass green cast (infinite-hallway realism).
     2. C-fed Droste regress — previous frame pulled toward the singularity shows through folded regions, so the hallway keeps receding.
FORBID: new palette, springs, extra ripple system.
A PACKING: ACES display RGBA (was foldedUV, unread).

SHADER: holographic-entropy-vortex (2nd pass)
IDENTITY: fbm entropy field swirled by a radial-shear vortex with iridescent holographic sheen + atmosphere.
KEEP VERBATIM: vortex shear, fbm entropy, OkLab palettes, Rayleigh/Mie, caustics, params.
ADD: 3. logarithmic spiral arms ordering the entropy field (ordered in-arm, noisy between) — differentiates from the mirror vortex (field structure, not image folding).
     4. thin-film thickness = local entropy, so iridescent fringes follow the swirl.
FORBID: image folding/mirror (other vortex), springs.
A PACKING: ACES display RGBA.

SHADER: matrix_digital_rain
IDENTITY (HEAD body): 5 ping-pong zoom layers with depth edge glow + fog; name/description promise digital rain.
KEEP VERBATIM: 5-layer zoom stack, layer speed lo/hi, edge glow, fog, volumetric alpha.
ADD: 1. per-layer glyph rain columns gating each zoom layer (head decodes true image, trail = green phosphor code).
     2. depth-parallax column speed (near layers rain faster, bass speeds rain).
FORBID: replacing the zoom stack, CRT scanlines.
A PACKING: ACES display RGBA (A was unwritten).
