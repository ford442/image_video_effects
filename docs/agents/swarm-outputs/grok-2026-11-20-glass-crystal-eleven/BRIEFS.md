# Idea Cards — Grok (glass / crystal eleven, 2026-11-20)

Written before the WGSL edits. Eleven shaders the user listed by size. Each card adds two or three ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, shockwave, or palette is added. Springs, click paths, and earlier ideas that are already in a file stay as they are.

Eight files still paste the binding header (`mouse-time-crystal`, `refractive-bubbles`, `alpha-paint-thickness`, `gen-protocell-division`, `kaleido-portal-interactive`, `reactive-glass-grid`, `fractal-noise-dissolve-nlm`, `quantum-wormhole`). Migrating them to `#include "_prelude.wgsl"` is infrastructure and is not an idea.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Deep-water dispersion (§12.2D) is `luma-refraction` only.
- Cauchy scales (§12.2F) is `luma-refraction` only.
- Snell (§12.2F) and Airy disc (§12.2F) are `refractive-bubbles` only.
- Wet-edge (§12.2C) is `alpha-paint-thickness` only.
- Beer–Lambert (§12.2F) is `hybrid-reaction-diffusion-glass` only.
- No other §12.2 row is newly applied.

```
SHADER: luma-refraction
IDENTITY (one sentence): a height-field pond whose speed follows image brightness, seen only as chromatic refraction of the photo.
KEEP VERBATIM: Wave Speed / Mouse Force / Damping / Refraction; h and v in C.rg; 5-point wave step; luma-scaled speed; mouse stir; click raindrops; audio rain; drizzle; R/G/B offsets; dispersion glint. State never enters the display path.
MECHANISM INTERROGATION:
  tactic 1: the wave step is non-dispersive. Real ripples sort by wavelength.
  tactic 2: the three channel offsets are a fixed scale of one normal. Glass dispersion is Cauchy, not a bass/treble fudge on the same delta.
  tactic 6: C.rg is the height and velocity. Do not write display color into A.
ADD:
  1. Deep-water dispersion (§12.2D) — divide the existing localSpeed by (1 + |laplacian|), so short crests lag. Wave Speed still sets the scale.
  2. Cauchy scales (§12.2F) — n(λ)=1+B/λ² relative to green multiplies the existing normal offset. Refraction still scales the whole bend.
FORBID: a spring, a new palette, storing the photo in A, replacing the wave step
A PACKING: raw wave state (h, v, 0, 1). ACES on the refracted display only.
```

```
SHADER: mouse-time-crystal
IDENTITY (one sentence): clicks seed crystals that grow by diffusion-limited aggregation along the photo's gradients, then age and cool.
KEEP VERBATIM: Growth Rate / Crystal Density / Age Color Speed / Glow Intensity; state (age, branchID, density, temperature); ripple seeds; neighbor stick test; cosine age palette; mouse heat. The stick rule is not rewritten.
MECHANISM INTERROGATION:
  tactic 2: a mineral face catches a specular, and the interior cools faster than the growth front.
  tactic 3: density is stored and never shown. The luma gradient is computed and thrown away after the stick test.
  tactic 6: C is the crystal tuple. Do not ACES it.
ADD:
  1. Growth-face glint — the luma gradient already used for sticking becomes a face normal and a tight specular. Glow Intensity still scales the glow.
  2. Cooling rim — temperature decays faster where that gradient is flat, and stays hot on the front.
  3. Density veins — the stored density darkens the crystal so older branches read as mineral.
FORBID: changing the stick probability, a new spring, replacing the age palette, tip-screening from dla-crystals
A PACKING: raw (age, branchID, density, temperature). ACES on display only.
```

```
SHADER: refractive-bubbles
IDENTITY (one sentence): glass bubbles orbiting the pointer, each a ball lens with a thin-film wall and a bright contact wall where two overlap.
KEEP VERBATIM: Bubble Size / Refraction Index / Bubble Count / Wobble Speed; orbit; sphere normal; ball-lens core mix; thin-film from wall thickness; Plateau contact wall; Fresnel; Beer–Lambert absorption; point specular.
MECHANISM INTERROGATION:
  tactic 2: the rim bend is `nXY * strength`, not a refracted ray. The point specular has no diffraction ring.
  tactic 3: bubbleNormal and the specular cosine are already computed.
ADD:
  1. Snell rim (§12.2F) — refract() of the view ray through the existing normal, with a reflect fallback on total internal reflection. The ball-lens mix still owns the core. Refraction Index still scales the bend.
  2. Airy disc (§12.2F) — diffraction rings on the existing specular cosine, not a new light.
FORBID: a spring, a second bubble shape, replacing the contact wall or the film
A PACKING: ACES display RGBA (C is unread; A stays the display color)
```

```
SHADER: alpha-paint-thickness
IDENTITY (one sentence): impasto. Alpha is wet thickness — thin wash, medium color, thick specular — painted by the pointer and by click splatters.
KEEP VERBATIM: Brush Size / Paint Saturation / Specular Power / Drying Rate; pigment.rgb + thickness.a; hue brush; ripple splatters; thickness-gradient specular; palette-knife ridge; canvas tooth; drying multiply.
MECHANISM INTERROGATION:
  tactic 2: watercolour pigment parks at the wet boundary. Thick paint also throws a shadow down-light, not a uniform darkening.
  tactic 3: the four neighbor thicknesses are already loaded for the gradient.
  tactic 6: A stays pigment + thickness. Do not ACES the stored fields.
ADD:
  1. Wet edge (§12.2C) — max(−∇² thickness, 0) from those four taps darkens the stroke boundary.
  2. Directional impasto shadow — the existing lightDir occludes where the thickness gradient faces it. The uniform thick-shadow stays.
FORBID: a new spring, a new pigment solver, replacing the knife ridge or the tooth
A PACKING: raw pigment.rgb + thickness.a. ACES on display only.
```

```
SHADER: gen-protocell-division
IDENTITY (one sentence): oil-iridescent protocells that split under a cleavage furrow, nuclei leading the membrane.
KEEP VERBATIM: Cell Count / Surface Tension / Iridescence / Division Rate; smin of two lobes; furrow envelope; mitotic nuclei; film hue; mouse attract; 5% C color trail; premultiplied write.
MECHANISM INTERROGATION:
  tactic 2: after the ring contracts, daughter cells keep a seam. A nucleus has a denser core.
  tactic 3: the furrow's spatial ring is multiplied by div*(1−div) and then discarded. The nucleus distance is already in the SDF return.
ADD:
  1. Division scar — the same neck ring, without the mid-split envelope, faded in after the split.
  2. Nucleolus — a darker core where the nucleus distance is most negative.
FORBID: a new cell shape, a Gray-Scott solver, replacing the iridescence
A PACKING: ACES display RGBA, straight color in A (writeTexture stays premultiplied)
```

```
SHADER: kaleido-portal-interactive
IDENTITY (one sentence): a circular portal of a kaleidoscope fold around a sprung center, with click spins and a soft border.
KEEP VERBATIM: Radius / Segments / Rotation / Hardness; triangle fold; spring in extraBuffer[133..138]; click spin phase in [139]; soft-knee border glow. Do not add the mirror-dimension bevel.
MECHANISM INTERROGATION:
  tactic 2: the portal is a glass disc. Its circular lip bends the photo. The fold already spins; a spinning tube smears along the tangent.
  tactic 4: Hardness is the lip width. Rotation and the click burst are the angular velocity.
  tactic 5: mirror-dimension already owns crease bevel, fold fringe, and tube caustic. This file's unused device is the circular lip and the spin.
ADD:
  1. Portal lip — a radial UV bend across the existing hardness band at the circular edge.
  2. Spin smear — one extra sample along the tangent, weighted by Rotation plus the click burst velocity.
FORBID: copying the mirror bevel / fold fringe / tube caustic, a new fold, a new spring
A PACKING: raw portal tuple (mask, border, segments/16, alpha). ACES on writeTexture only. C is unread.
```

```
SHADER: bismuth-crystallizer
IDENTITY (one sentence): a hopper-stair bismuth crystal, oxide iridescence and metal Fresnel over the photo, with a bright terrace lip and a tarnished well.
KEEP VERBATIM: Crystal Depth / Hopper Offset / Iridescence Freq / Metallic Mix; the hopper loop; oxide interference; metal Fresnel; terrace rim; tarnish well.
MECHANISM INTERROGATION:
  tactic 2: each stair has a vertical riser in shadow, and the oxide thickness runs from the lip to the well, not only with the integer step.
  tactic 3: terraceEdge is the fractional position inside the current stair and is only used as a rim/well mask.
ADD:
  1. Stair riser — a dark band just inward of the existing bright lip.
  2. Oxide across the stair — terraceEdge added into the existing interference phase, so color grades across one step.
FORBID: a new crystal primitive, a second palette, a spring
A PACKING: ACES display RGBA (C unread)
```

```
SHADER: hybrid-reaction-diffusion-glass
IDENTITY (one sentence): a Turing field used as the thickness of a glass pane that refracts the photo, with caustics where the gradient focuses.
KEEP VERBATIM: Feed / Kill / Glass Refraction / Depth Effect; 9-point Laplacian; cubic reaction; mouse deposit; click fronts; gradient refraction; palette mix; Fresnel; thickness IOR; divergence caustic. A stays (chem, |grad|, caustic, coverage).
MECHANISM INTERROGATION:
  tactic 2: thicker chemistry should absorb the photo, not only lerp toward the palette.
  tactic 3: the Laplacian is computed for the PDE and then discarded. Its magnitude is the reaction front.
  tactic 6: C.r is chemistry. Do not write display color into A.
ADD:
  1. Beer–Lambert (§12.2F) — exp(−palette · chem) multiplies the photo before the existing mix. Glass Refraction still scales the bend and the absorption.
  2. Reaction-front meniscus — |laplacian| draws a thin bright line on the chemical boundary.
FORBID: a new solver, replacing the caustic, ACES on the stored fields
A PACKING: raw (chem, |grad|, caustic, coverage). ACES on display only.
```

```
SHADER: reactive-glass-grid
IDENTITY (one sentence): a grid of glass tiles that bulge toward a sprung pointer, refract the photo, and sparkle on click rings.
KEEP VERBATIM: Tile Density / Refraction / Glow / Edge Smoothness; spring in extraBuffer[133..137]; click shockwaves; per-tile FFT voice; chromatic R/G/B taps; Fresnel rim; caustic hash.
MECHANISM INTERROGATION:
  tactic 2: a glass tile is a shallow lens even when the pointer is far, and the seams are grout, not only a glow.
  tactic 3: localUV is the tile coordinate and is only multiplied by influence.
ADD:
  1. Resting pillow — a small lens from localUV that remains when influence is zero. The pointer bulge still dominates up close. Refraction still scales it.
  2. Grout — darken where localUV reaches the tile edge, under the existing glow.
FORBID: a new spring, a new shockwave, an IQ palette, Cauchy (that scale belongs to luma-refraction)
A PACKING: ACES display RGBA (C unread; A matches the display)
```

```
SHADER: fractal-noise-dissolve-nlm
IDENTITY (one sentence): fractal-noise erosion around the pointer, slower on unique patches and faster on repetitive ones, with non-local-means smoothing on what remains.
KEEP VERBATIM: Noise Scale / Radius / Edge Width / NLM Mix; the noise sum; patch SSD; search loop; similarity bias; burn rim. Do not copy char-cracks or ember-lift from fractal-noise-dissolve.
MECHANISM INTERROGATION:
  tactic 3: center − nlmResult is the detail the filter removed. avgSimilarity is only a scalar bias.
  tactic 4: Edge Width is uniform. Repetitive patches should burn on a tighter front.
  tactic 5: a burn leaves ash, not a hard cut to black.
ADD:
  1. Similarity-scaled edge — Edge Width times a factor from the existing dissolve bias.
  2. NLM residual — a fraction of (center − smoothed) put back on the surviving side. NLM Mix still owns how smooth the survivor is.
  3. Ash — the dissolved side keeps a dark remainder of the smoothed color under the burn.
FORBID: a new noise, a spring, replacing the patch search
A PACKING: ACES display RGBA (C unread). This file did not write A; the display color is what gets stored.
```

```
SHADER: quantum-wormhole
IDENTITY (one sentence): a throat at the pointer that twists hue by a 4D phase, advects a trail with image curl, bursts highlights, and inverts the darks.
KEEP VERBATIM: Intensity / Speed / Scale / Detail as twist / flow / trail / persistence; to4D; curlField; HSV twist; oil slick; highlight burst; void invert; helix; click rings; C trail. Do not copy the additive photon ring from cyber-physical-portal.
MECHANISM INTERROGATION:
  tactic 2: a spinning throat drags nearby light azimuthally, and light climbing out of the well loses color. The photo should also appear as a lensed ring, not only a hue twist.
  tactic 3: the curl velocity and the HSV are already computed. The radial vector is computed and discarded inside depthInf.
ADD:
  1. Frame drag — a tangential add on the existing curl, stronger at the throat. Intensity (twistScale) scales it.
  2. Gravitational redshift — the existing HSV loses saturation and value in the throat.
  3. Einstein ring — a thin annulus mixes in a photo sample from the far side of the throat. Not an additive warm line.
FORBID: a spring, a new palette, replacing the void invert or the trail
A PACKING: ACES display RGBA (C is the color trail)
```
