# Distortion lens eight — NOTES

Per shader: what was kept verbatim, A packing, and where each idea sits in the diff.
No JSON changes: every saved `params` / `updatedParams` block is byte-identical to HEAD.

## gravity-well
- Kept: deflection, redshift tint, ring radii, blackbody(), 0.55 disk tilt, Doppler beaming, 4 param ranges.
- A: lensing fields (deflection/3, rings, diskMask, shadow). C unread. Unchanged.
- Idea 1 (lensed far side): `haloBand * haloArc` block. Arc hugs bCrit, strongest perpendicular to the
  disk plane, has its own Doppler around the circle, sits behind the near disk (`1 - diskMask`) and
  outside the shadow. Width follows Disk Extent (the disk's size, same role).
- Idea 2 (Keplerian shear): `keplerStreaks()`. Ω = 2.2·(1.6 rs / r)^1.5; two phases cross-faded over
  a 6 s cycle so winding stays bounded. Modulates disk emission 50% and the halo 40%.
- Structural: the `shadow` line moved above the disk block (the halo needs it). Same value.
- No ACES (HEAD had none; the JSON has no upgraded-rgba tag, and none was added).

## black-hole
- Kept: pinch falloff, RGB split, disk colour/turbulence/runners/packets, click fronts, alpha formula.
- A: fields (dist, radius, horizonMask, alpha). Unchanged.
- Idea 1 (frame dragging): `drag_dir * drag` added to all three channel offsets; 0.55·exp(-4·d)
  × (1 + 0.6·held).
- Idea 2 (photon-ring secondary image): `ring_mask` block. Band [1.04R, 1.04R + 0.22R + 0.006];
  samples the scene point-reflected through the hole, with reach going from 0.9 at the inner edge to
  1.1R at the outer edge. Chromatic, warm-tinted, mixed in at 80%.
- **Flagged, not changed:** the output is `final_color * a` with a ≈ 0.2–0.5 away from the horizon,
  which premultiplies and visibly darkens the frame. It may be intentional (Grok flourish pass).
  Check on a GPU. JSON also claims upgraded-rgba with no ACES (pre-existing).

## heat-haze-gpt52
- Kept: fbm warp stack, curl, dispersion, thermal source, filaments/packets/click/slick overlays, C blend.
- A: display RGBA (HEAD). Unchanged.
- Idea 1 (inferior mirage): `mirageSample()` plus the `mirage` term. Ground line at y = 0.78; the
  reflection is flipped and squashed 1.6× below it, fades over 0.13, is broken into pools by n1/n2,
  and is scaled by Haze Intensity.
- Idea 2 (boundary layer): `boundary = 1 + 1.1·exp(-|y − ground| / 0.15)` multiplies the warp. At the
  top of the frame it is 1.005, i.e. HEAD's value.
- Idea 3 (held hot patch): `hotPatch` is a local mirage 0.035 below the cursor, only while held.
- Flagged: upgraded-rgba without ACES (pre-existing).

## zoom-burst
- Kept: tap loop, pow(t, 1.7) spacing, spin shear, chroma split, speed lines, ACES, alpha, dead spring.
- A: ACES display RGBA. Unchanged.
- Idea 1 (highlight comets): `comet = 1 + max(lum − 0.55, 0)·4·t` in the tap weight.
- Idea 2 (dwell ghost): one extra tap at the streak end (`ghost`), mixed at 16% into `burst`.

## interactive-zoom-blur
- Kept: `center + dir·(1 + t·strength)` mapping, Bayer dither, channel spreads, depth attenuation,
  effectBlend, click pulses, dead spring.
- A: display RGBA. **Floor fix:** C was read with `textureSampleLevel(dataTextureC, u_sampler, …)`,
  a filtering sample on rgba32float. It is now an exact `textureLoad`.
- Idea 1 (depth occlusion): `occl` per tap from the depth at the green tap (near = 1). Normalised by
  `occlSum`, which equals `samples` when nothing is occluded, so that case is identical to HEAD.
- Idea 2 (radial trail advection): C is read at `center + dir·advect`, i.e. 1.5–7.5% inward along the ray.

## infinite-zoom-lens
- Kept: drosteUV(), the recursion loop and its weights, chroma arms, overlays, lens mask, ACES.
- A: ACES display RGBA. Unchanged.
- Idea 1 (log-periodic nesting): `nestU/nestF/nestR` wrap log-radius with S = 2.2 inside the lens.
  `lensUV` feeds drosteUV in place of `uv`.
- Idea 2 (endless fall): `fallPhase = time·zoomSpeed·0.12`, so Zoom Strength now also sets the fall
  rate (it is the zoom slider, so this is the same role).
- Idea 3 (frame seams): `frameShadow` / `frameLip` at each nesting boundary, lens-masked.
- **Largest look change in the batch:** the lens interior now nests. Eyeball it first on a GPU.

## bubble-lens
- Kept: evalBubble lens, drainage, black spot, HEAD Fresnel tint, satellites, membrane loop, ACES, C max.
- A: ACES display RGBA. Unchanged.
- Idea 1 (rear-wall reflection): `sphereFresnel` / `reflCol` block. The scene is inverted through the
  centre with reach 0.35R → 2.75R toward the rim, weighted by Schlick at the true incidence (IOR
  slider), and suppressed in the black spot.
- Idea 2 (Marangoni vortices): two counter-rotating swirls rotate the thickness-noise lookup (`filmUV`).
  The lens sample itself is untouched.

## refraction-tunnel
- Kept: IOR split, dispersion offsets, click ring, fog, streak, ACES, alpha, dead spring.
- A: ACES display RGBA. Unchanged.
- Floor (not counted): `twistDelta` now rotates the base sample about the tunnel axis. Twist Amount
  was otherwise invisible in the image. At default twist 0.5 → delta 0, so sampling equals HEAD.
- Idea 1 (glass-pipe reflection): `wallRefl` block. The outer 20% of the tunnel radius shows a radial
  mirror of the adjacent band, with weight pow(s, 2.5)·0.55.
- Idea 2 (perspective rails): `tunnelZ = 0.35 / r`; hoops and helix are spaced in z and all rails
  fade out by r ≈ 0.03–0.16.

## Batch-wide
- Zero springs, ripple loops or palettes added. The five pre-existing extraBuffer springs are dead at
  runtime (the whole buffer is re-uploaded each frame) and resolve to the raw mouse. They are left as-is.
- No idea depends on audio: plasmaBuffer is still unwritten by the renderer (`audioDepth.ts:5`).
