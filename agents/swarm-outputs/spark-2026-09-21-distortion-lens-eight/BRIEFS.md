# Distortion lens eight — Idea Cards (written before any WGSL edit)

Batch: 2026-09-21, fourth batch of the day. Family: `distortion`, 43/63 files had no named ideas.
Theme: optical lenses and gravitational/thermal refraction — every file here bends the source image
through a lens-like mapping, so every idea is an optical or physical consequence of *that* mapping.

**Selection.** Read 10 candidates in full. Claimed 8. Excluded after reading:
- `spiral-lens` — already over-stuffed (Möbius + kaleido + domain warp + log/arch spirals + 5 overlays),
  and most layers are gated on `plasmaBuffer` audio, which the renderer never writes
  (`audioDepth.ts:5`), so they are invisible at runtime. It needs a subtractive pass, not more ideas.
- `cyber-lens` — not read in depth; kept out to hold the batch at 8.

**Runtime facts that shape the cards (checked today, not assumed):**
- `plasmaBuffer` is still never written → no idea may depend on audio to be visible.
- `writeExtraBuffer` re-uploads all 256 floats every frame → the `extraBuffer[133..138]` springs in
  zoom-burst / interactive-zoom-blur / infinite-zoom-lens / bubble-lens / refraction-tunnel always
  resolve to the raw mouse. Harmless; left in place (no churn), and no idea is built on them.

Forbidden across the whole batch: new springs, new ripple loops, IQ/cosine palettes, oil-slick overlays.

---

```
SHADER: gravity-well
IDENTITY: Schwarzschild lens under the cursor — shadow, photon/Einstein rings, tilted Doppler-bright
          blackbody accretion disk.
KEEP VERBATIM: deflection formula, redshift tint, ring radii, blackbody(), disk tilt 0.55, Doppler
               beaming, 4 params and their mix() ranges, A field packing.
ADD:
  1. Lensed far side of the disk — the disk's back half is bent up and over the shadow as a thin
     arc (the "Interstellar halo"). Belongs: it is what lensing does to a disk behind a hole; the file
     already has the disk and the deflection, just never lenses the disk itself.
  2. Keplerian shear streaks — disk emission gets azimuthal density streaks that orbit at
     Ω ∝ r^-1.5, so the inner disk laps the outer and streaks shear into spirals. Belongs: it gives
     the Doppler side a visible flow direction; currently the disk is a static smooth gradient.
FORBID: click rings, springs, colour palettes other than blackbody.
A PACKING: HEAD's lensing fields (deflection/3, ring, diskMask, shadow). C is never read. Unchanged.
```

```
SHADER: black-hole
IDENTITY: stylized radial pinch lens with a black horizon, chromatic lensing, orange accretion glow,
          orbit runners and infall packets.
KEEP VERBATIM: pinch falloff 1/(d*5+0.1), RGB offset split, disk colour/turb/runners/packets,
               click fronts, param roles (gravity/radius/glow/lensing width), alpha formula.
ADD:
  1. Frame dragging — the lensing offset gains a tangential component that grows toward the
     horizon, so the image swirls into the hole instead of only pinching (a spinning hole drags
     space around with it). Held pointer reverses nothing; it deepens the drag.
  2. Photon-ring secondary image — a thin band just outside the horizon shows the whole scene
     point-reflected through the hole (the flipped secondary image of a lens), chromatic like the
     primary. Distinct from gravity-well, which renders its rings as blackbody light, not image.
FORBID: blackbody disk (that is gravity-well's), springs, new palettes.
A PACKING: HEAD's fields (dist, radius, horizonMask, alpha). C never read. Unchanged.
```

```
SHADER: heat-haze-gpt52
IDENTITY: rising fbm heat shimmer with chromatic split, held thermal source under the cursor,
          filaments/packets overlay.
KEEP VERBATIM: fbm warp stack, curl term, dispersion, thermal source, filaments/packets/click, C blend.
ADD:
  1. Inferior mirage — below a hot ground line the image is reflected (vertically flipped about the
     line) and shimmer-broken, like a road mirage. The header has claimed "mirage-refraction" since
     August but no reflection exists in the code.
  2. Boundary-layer strength — haze displacement is boosted near the hot ground and decays with height
     above it (hot air is thickest at the surface). Additive boost; the top of the frame stays at HEAD.
  3. Held pointer lays a hot patch — while held, a local mirage pool appears just below the cursor,
     using the same reflection as idea 1. Belongs: the thermal source is already held-pointer driven.
FORBID: removing the existing overlays (preset identity), springs.
A PACKING: display RGBA (HEAD). Unchanged.
```

```
SHADER: zoom-burst
IDENTITY: photographic zoom-burst — radial streak accumulation from the pointer with spin shear,
          chromatic split, speed lines.
KEEP VERBATIM: tap loop, pow(t,1.7) spacing, spin shear, chroma split, speed lines, ACES, alpha.
ADD:
  1. Highlight comets — taps are weighted by their luminance so bright points drag long bright tails
     while midtones blur normally (a real zoom exposure integrates light, highlights dominate).
  2. Zoom-ring dwell ghost — a real hand zoom lingers at the end of its travel, so the far end of the
     streak carries a faint, sharper second image of the scene. One extra tap at the streak end.
FORBID: depth-occlusion or radial trail advection (those are interactive-zoom-blur's cards).
A PACKING: ACES display RGBA (HEAD). Unchanged.
```

```
SHADER: interactive-zoom-blur
IDENTITY: radial zoom blur from the cursor, true zoom mapping (centre sharp), per-channel chroma,
          depth attenuation, temporal trail.
KEEP VERBATIM: center + dir*(1 + t*strength) mapping, Bayer dither, channel spreads, depth
               attenuation, effectBlend, param roles.
ADD:
  1. Depth-occluded streaks — a tap whose surface is nearer than the pixel it lands on is rejected,
     so foreground edges don't smear over background (real zoom smear respects occlusion). Uses the
     depth texture the file already reads.
  2. Radial trail advection — the temporal trail is read from C one step *inward* along the zoom
     ray, so history streams outward from the epicentre instead of sitting as a static ghost.
FORBID: highlight weighting / dwell ghost (zoom-burst's cards).
A PACKING: display RGBA (HEAD). Floor: C read switches from filtered sample to exact textureLoad.
```

```
SHADER: infinite-zoom-lens
IDENTITY: circular lens under the pointer with a Droste-style spiral recursion, chromatic arms,
          C feedback.
KEEP VERBATIM: drosteUV(), recursion loop and weights, chroma arms, overlays, lens mask, ACES.
ADD:
  1. Log-periodic nesting — inside the lens, radius is wrapped with fract(log r / log S), so the
     picture actually repeats inward forever (a real Droste). HEAD only rotates; it never nests.
  2. Endless fall — the log phase scrolls with time × Zoom Strength, so nested copies stream toward
     the centre. Zoom Strength currently only spins the spiral.
  3. Picture-frame seams — each nesting boundary gets a thin shadowed frame edge, the tell of Droste
     packaging art. Fades with the recursion weight.
FORBID: new palettes; replacing the recursion loop.
A PACKING: ACES display RGBA (HEAD). Unchanged.
```

```
SHADER: bubble-lens
IDENTITY: magnifying soap bubble under the pointer with thin-film interference, drainage, black spot,
          satellite bubbles on click.
KEEP VERBATIM: evalBubble lens, drainage, black spot, Fresnel, satellites, membrane loop, ACES, C max.
ADD:
  1. Convex-mirror reflection — the bubble's front surface reflects the scene inverted and compressed
     toward the rim, weighted by the Fresnel term the file already computes but only uses for tint.
  2. Marangoni vortices — two slow counter-rotating swirls advect the thickness noise, so interference
     colours curl like a real bubble film. HEAD's "Marangoni" is one dot product.
FORBID: springs (already present, dead), new palettes beyond the interference phase.
A PACKING: ACES display RGBA (HEAD). Unchanged.
```

```
SHADER: refraction-tunnel
IDENTITY: glass tunnel centred on screen, chromatic refraction at the walls, hoop/rib/helix rails,
          fog toward the wall.
KEEP VERBATIM: IOR split, dispersion offsets, rails, fog, click ring, ACES, alpha.
ADD:
  1. Glass-pipe wall reflection — near the tunnel radius the image is mirrored across the wall
     (total internal reflection in a glass tube), Fresnel-weighted toward grazing.
  2. Perspective rails — hoops and ribs are spaced in 1/r, so they bunch toward the vanishing point
     and read as a receding tunnel; HEAD spaces them uniformly in r.
FLOOR (not counted): `newAngle` (the Twist Amount slider) never touched the sampled image, only
  dispersion direction and overlays. The base sample is now rotated by the twist delta.
FORBID: springs, new palettes.
A PACKING: ACES display RGBA (HEAD). Unchanged.
```

---

## Card corrections made during implementation (visible, per the 2026-09-21 process lesson)

- **refraction-tunnel, idea 2:** the card said "hoops **and ribs** spaced in 1/r". Ribs are radial
  lines, so they are already perspective-correct; respacing them is meaningless. Implemented as: hoops
  **and the helix** in 1/r, all three rails fading into the vanishing point.
- **refraction-tunnel, floor:** the twist fix rotates by the slider's twist and held drag only, **not**
  HEAD's `time * rotSpeed` term. Including time would spin the whole picture at the default setting,
  and that would be a different effect.
- **refraction-tunnel, idea 1:** the first draft scaled the reflection by the Chromatic Dispersion
  slider. That gives a saved param a second meaning (param theft, §4.4), so it was reverted to a
  constant 0.55 before gating.
- **bubble-lens, idea 1:** the card said "weighted by the Fresnel term the file already computes".
  That term is directional (`dot(-direction, up)`), not incidence-based. The reflection uses Schlick at
  the true sphere incidence cosθ = sqrt(1 − r²) with the file's own `fresnelBase` (IOR slider).
  HEAD's term still drives the interference tint unchanged.
