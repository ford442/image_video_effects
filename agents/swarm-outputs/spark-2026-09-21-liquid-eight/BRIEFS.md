# Liquid Eight — Idea Cards (written before any WGSL edit)

**Agent:** spark · **Date:** 2026-09-21 · **Contract:** `docs/SHADER_UPGRADE_BATCH.md` §0/§2/§7

## Selection

`liquid-effects` is the most-neglected family by ratio: **30 of 31 files carry no `Ideas:` line.**
But that proxy is leaky, so every candidate was read in full before being claimed. Excluded after reading:

| ID | Why excluded |
|---|---|
| `glass-wipes` | No `Ideas:` header, but body already carries Batch 67's named "A. elastic wiper / B. bead conveyor" ideas. Already upgraded. |
| `liquid-metal` | Rosensweig hex mode, Ward anisotropic lobe, depth-basin gravity, magnetic-pole moat. Idea-dense; more would be piling on. |
| `rain-ripples` | "RETRY expanded upgrade": voronoi drops, fbm micro-ripples, caustics, thin film. Already stuffed. |
| `liquid-v1` | Its own description calls it the *clean baseline*. Upgrading it erases its purpose. |
| `liquid-pass1/2`, `liquid-optimized-pass1/2` | Multipass: A packing is a contract *between* passes. Different job. |
| upgraded Batch 51/59 files | Already have `Upgraded:` + named work. |

**Claimed (8):** liquid-rainbow-prismatic, luma-velocity-melt, liquid, kimi_liquid_glass, liquid-oil,
liquid-mirror, ink-marbling, liquid-displacement.

**Cloning risk, named up front:** `liquid`, `kimi_liquid_glass`, `liquid-oil` and `liquid-mirror` share one
solver template — the same 5-tap Laplacian wave equation on C, the same ripple ring, the same Schlick.
The template is the *same*; the physics each file claims is not (capillary water / refractive glass /
viscous oil / reflective mirror). Every idea below is keyed to that claim. None of the four gets an idea
that would make sense on another.

All eight already have the floor. **No springs, ripple loops, palettes or conveyors added.**

---

## 1. `liquid-rainbow-prismatic`

```
SHADER: liquid-rainbow-prismatic
IDENTITY: the photo seen through a rippling liquid lens with Cauchy dispersion splitting R/G/B, a
          thin-film rainbow sheen on top, and a caustic glow.
KEEP VERBATIM: the four slot roles as HEAD uses them (curvature / dispersion / filmScale / saturation —
          the JSON ids read viscosity / turbulence / ripple_strength / spectral_sat; mismatch is HEAD's,
          not rewired); surface(); Cauchy nR/nG/nB; per-channel refracted samples; the film phase
          formula; history mix; Fresnel alpha.
ADD (2 native ideas):
  1. Gravity drainage + Newton's black film — a real film thins from the top down under gravity, so its
     interference bands stack horizontally and the thinnest region goes BLACK (destructive for every
     wavelength) just before it would pop. Mix a vertical drainage profile into thickness and kill the
     sheen where thickness → 0. The thin-film half of this effect is currently a swirl with no gravity.
  2. Dispersed caustics — the caustic is a grey 6-tap blur around the green sample. In a dispersive lens,
     each wavelength focuses somewhere else, so gather each channel's caustic around ITS OWN refracted uv.
     Caustics fringe into rainbows, which is the name of the effect.
FORBID: extra palettes, springs, anything that is not optics.
A PACKING: ACES display RGBA in A; C read as colour via historyAt(). Unchanged.
```

## 2. `luma-velocity-melt`

```
SHADER: luma-velocity-melt
IDENTITY: bright parts of the photo melt downward like wax, advected through an HDR display history,
          with a held-pointer swirl and click push.
KEEP VERBATIM: all four params with their non-normalised ranges used directly (melt-speed 0..0.02,
          heat 0..5, persistence 0.5..0.999, threshold); hot mask; noise flow; tangent swirl; click
          rings; chroma split along flow; history weight; HDR clamp at 8.0.
ADD (2 native ideas):
  1. Drip pinch-off — melting material does not smear as a sheet, it necks into columns and beads into
     drops. Per-column bead phase modulates the downward flow (content piles where flow slows), and a
     lateral pull toward each column's centre necks the stream. Gated by the hot mask.
  2. Depth-ledge pooling — the file already reads depth to scale the melt. Where the scene steps in depth
     directly below a pixel, the drip stops and pools: vertical flow is cut, and a little lateral
     spread spills along the ledge. Wax running down a real 3-D scene.
FORBID: palettes, a spring (this file has none and needs none), replacing the advection.
A PACKING: untonemapped HDR RGB + semantic alpha in A (as HEAD documents); B unwritten. Unchanged.
```

## 3. `liquid`

```
SHADER: liquid
IDENTITY: a capillary water surface over the photo — persistent height/velocity waves pushed by the
          held pointer and by clicks, refracting the image, with caustics and foam.
KEEP VERBATIM: viscosity / turbulence / ripple_strength / color_shift; the wave equation and its
          tension/damping mixes; capillary noise; spring; ring impulse; refraction, Fresnel, caustic,
          tint; A raw packing.
ADD (2 native ideas):
  1. Capillary precursor ring — capillary waves have ANOMALOUS dispersion: the short ones travel faster
     than the long ones. That is why a drop on water throws a fringe of tiny ripples out AHEAD of the
     main ring. Add a faster, narrower, higher-frequency precursor to each click, damped harder by
     viscosity (viscous damping scales with k²).
  2. Foam drains into troughs — foam lives in B but only decays where it was born. Real foam slides off
     crests under gravity. Semi-Lagrangian transport of B from the uphill neighbour moves foam
     downslope, so it collects in the troughs and lines them.
FORBID: TIR, bubbles, displacement troughs, glitter — those belong to this template's siblings.
A PACKING: raw — R height, G velocity, B foam, A coverage. Unchanged.
```

## 4. `kimi_liquid_glass`

```
SHADER: kimi_liquid_glass
IDENTITY: a slab of liquid glass over the photo — a thickness field refracts through refract() with a
          physical IOR, absorbs by thickness, throws caustics and interference.
KEEP VERBATIM: the four slot roles as HEAD uses them (intensity / speed / scale / detail); modal drive;
          lens push; ring impulse; ior mix 1.31..1.58; refract() offset; dispersion; Schlick f0 from IOR;
          absorption; interference; A raw packing.
ADD (2 native ideas):
  1. Total internal reflection on steep flanks — light leaving glass for air cannot escape past the
     critical angle asin(1/ior). Where the surface is steep enough, the photo is NOT transmitted and you
     see a silvery internal reflection instead. That is why glass and water edges flash bright. Computed
     from the same ior the file already uses, as a soft mask on the Snell discriminant.
  2. Seed bubbles — glassmakers call trapped bubbles "seeds". They rise slowly and only exist where the
     glass is thick. Each is a small diverging lens: a dark rim (itself TIR at the bubble wall) and a
     bright specular dot. Lives in the thickness field the file already stores.
FORBID: glitter, foam, dispersion changes — keep this glass, not water or a prism.
A PACKING: raw — R height, G velocity, B thickness, A coverage. Unchanged.
```

## 5. `liquid-oil`

```
SHADER: liquid-oil
IDENTITY: a thick oil film over the photo — slow high-viscosity waves, a shear field, a heavy
          specular, and thin-film interference keyed to film height and shear.
KEEP VERBATIM: viscosity / turbulence / ripple_strength / color_shift; capillary/damping mixes; curl
          drive; shear update; ring impulse; Schlick; specular exponent; film phase formula's terms;
          absorption; A raw packing.
ADD (2 native ideas):
  1. Displacement wake — dragging something through thick oil does not lift it, it PARTS it: a trough
     at the core, a raised rim, and a channel that closes slowly behind you because viscosity resists
     refill. HEAD's stir only added upward acceleration. Replace the lift with a core-down / rim-up
     displacement; the existing high-viscosity solver then holds the wake open on its own.
  2. Shear-aligned film streaks — oil drags into long streaks along its flow. Average film height along
     the contour direction (perpendicular to the height gradient) before it drives the interference
     phase, weighted by the shear the file already tracks, so the colour bands stretch into strands.
FORBID: precursor rings, foam, glitter, bubbles.
A PACKING: raw — R film height, G vertical response, B shear, A coverage. Unchanged.
```

## 6. `liquid-mirror`

```
SHADER: liquid-mirror
IDENTITY: a reflective liquid sheet — the photo is mirrored across the surface and broken up by a
          persistent height field that the pointer pushes, with Fresnel and a steel-tinted reflection.
KEEP VERBATIM: distort / smooth / reflect / push; spring; ring impulse; ambient drive; wave equation;
          mirrorUV flip; direct sample; Schlick f0 mix; specular; steel tint; A raw packing.
ADD (2 native ideas):
  1. Glitter path — a light over rippled water shatters into thousands of tiny glints, concentrated
     in a band under the light and spreading wider as the water roughens. Jittered micro-facet normals
     around the solved normal, a very high specular exponent, and a per-cell flicker. The glints'
     spread is keyed to the stored surface energy.
  2. Energy-roughened reflection — calm water reflects sharp, disturbed water reflects soft. Blur the
     mirrored sample by a radius taken from B (surface energy) and from (1 − smooth). This gives B its
     first visible optical job: HEAD only fed it through `treble * 0.12`, which is zero without audio.
FORBID: TIR, bubbles, foam drainage, displacement wakes.
A PACKING: raw — R height, G velocity, B surface energy, A coverage. Unchanged.
```

## 7. `ink-marbling`

```
SHADER: ink-marbling
IDENTITY: marbled ink on a bath — pigment and thickness advected through wave flow, swirled by the
          stirrer, diffused into veins, with ink drops on click.
KEEP VERBATIM: the four slot roles (warp intensity / flow speed / flow scale / detail); spring stirrer;
          waveA/waveB flow; swirl; drop injection (core + ring) and dropColor; neighbour diffusion;
          thickness retention; the palette() calls already present; A raw packing.
ADD (2 native ideas):
  1. Area-preserving drop spread — in real marbling a new drop PUSHES every existing ring outward, which
     is how the concentric "stone" pattern forms. Jaffer's marbling map does this exactly:
     p ← c + (p − c)·√(1 − R²/|p − c|²). Applied per frame as the inverse lookup for the growing radius.
     This REPLACES HEAD's ring-front push (`flow += dir·ring·warp·1.5`), which was an approximation of
     the same thing and would double-count; stated here, not done silently.
  2. Comb rake — the tool that defines marbling. A comb of tines is drawn through the bath on a slow
     cycle, alternating direction each pass (that back-and-forth is the classic nonpareil). Jaffer's
     tine-line displacement α·λ/(d + λ), d = distance to the nearest tine. Tine spacing rides the
     existing scale slot, rake rate the speed slot, strength the intensity slot.
FORBID: new palettes, a second stirrer, anything not done with ink and a bath.
A PACKING: raw — pigment.rgb + thickness. Unchanged.
```

## 8. `liquid-displacement`

```
SHADER: liquid-displacement
IDENTITY: the photo displaced by a persistent incompressible flow — velocity with viscous diffusion and
          a pressure-like height coupling, pushed by the pointer and clicks, rendered as refraction.
KEEP VERBATIM: viscosity / pressure_iterations / flow_speed / turbulence; divergence; lapV; heightGrad
          pressure term; curl drive; spring; click push; damping; A raw packing.
ADD (2 native ideas):
  1. Vorticity confinement — the standard fix for exactly this solver's failure mode. Numerical damping
     smears small swirls out; confinement measures the curl, finds the gradient of |curl|, and pushes
     back along N × ω to re-sharpen the vortices. Strength rides turbulence. Needs the curl at the four
     neighbours, so it adds eight exact C loads (the four diagonals and the four 2-away texels).
  2. Flow-line streaks — a displacement shader only ever shows the flow as a warp. Integrate the source
     along the local velocity (a 4-tap line integral) and mix it in by speed, so fast flow drags the
     photo into visible streamlines.
FORBID: foam, TIR, glitter, drop displacement.
A PACKING: raw — RG velocity, B height, A activity. Unchanged.
```

---

## Shared discipline

- 16 ideas, 8 files, none reused. The four template siblings get physics that only fits their own claim.
- Saved `params` byte-exact. HEAD's id/role mismatches (prismatic, kimi) documented, not rewired.
- All five raw-state files stay raw. No field is promoted to display RGBA; nothing new is ACES'd in A.
- `upgraded-rgba` tag added only to the five files missing it (kimi_liquid_glass, liquid-oil,
  liquid-mirror, ink-marbling, liquid-displacement), and only after their cards land. ACES is already
  present in all eight.
