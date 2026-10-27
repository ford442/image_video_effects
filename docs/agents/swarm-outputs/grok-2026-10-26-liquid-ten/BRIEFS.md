# Idea Cards — Grok (`grok/liquid-ten`, 2026-10-26)

Written before WGSL edits. Ten liquid / vortex / field shaders. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula rule: a §12.2 row is used on at most one file here.

Seven pasted headers are migrated to `#include "_prelude.wgsl"` as infrastructure (`quantum-foam`, `ink-bleed`, `ambient-liquid`, `magnetic-interference`, `lava-lamp-blobs`, `tornado-vortex`, `gen_reaction_diffusion.wgsl`). `ink-bleed` declares binding 11 as `comparisonSampler`; that identifier is renamed to `comparison_sampler` so the codemod can see a canonical header. That swap is not the upgrade.

---

## quantum-foam

IDENTITY: the photo sheared into multi-scale curl foam — Voronoi cells, interference, quaternion hue rotation, spectral remix, click bursts.
KEEP VERBATIM: Intensity→foam scale, Speed→flow, Scale→history diffusion, Detail→octave count; 3-layer curl parallax; Voronoi F1/F2; interference product; quaternion rotate; spectralPower; anisotropic C blend; click bursts. No new spring.
MECHANISM:
- tactic 2: a foam wall thins before it pops. The Voronoi gap F2−F1 is that thickness.
- tactic 3: `cell.y - cell.x` is smoothed into a mask and the gap itself is discarded.
- tactic 6: C is display color. A bright cell last frame is a bubble that should not reset every frame.
ADD:
  1. Necked walls — emission follows `exp(-gap)`, so the thinnest Voronoi walls flare and the depth creases there.
  2. Bubble memory — where last frame's luma was high and this pixel is still a cell center, the existing diffusion blend holds the plasma color instead of washing it out.
FORBID: a Gray-Scott solver, a new palette, a pointer spring.
A PACKING: linear display RGBA in A (C is the color history the blend reads). ACES on `writeTexture` only, so the history mix stays in linear light.
FORMULA: no §12.2 row.

## vortex

IDENTITY: four Lamb-Oseen vortices stirring the photo, with LIC streaks and a bathtub dimple.
KEEP VERBATIM: Vortex Strength / Core Size / Rotation Speed / Turbulence; four-vortex layout and signs; Lamb-Oseen speed and core vorticity; confinement; inflow; local swirl; LIC; Lorentzian dimple, throat darkening, depth recess.
MECHANISM:
- tactic 2: the shear is greatest on the ring where Lamb-Oseen speed peaks, and that ring rolls up. The funnel slope focuses a bright shoulder.
- tactic 3: `x = r/rc` and `dimple.yz` are computed and then only used for speed and refraction.
- tactic 6: C is not read. Neither idea repacks A.
ADD:
  1. Shear-layer billows — an azimuthal ripple on the shell `x ≈ 1.12`, tangent to the vortex, so the core boundary rolls instead of staying a smooth circle.
  2. Funnel caustic — a cool ring where the existing dimple slope is steep, kept off the dark throat.
FORBID: a new vortex count, Gray-Scott, an IQ palette, a spring.
A PACKING: ACES display RGBA (unchanged).
FORMULA: no §12.2 row.

## liquid-optimized

IDENTITY: one analytic capillary height field — click packets, eight FFT capillary trains, bass swell, held dimple — refracting the photo with Fresnel and Beer-Lambert absorption.
KEEP VERBATIM: Surface Tension / Gravity / Damping / Turbidity roles; closed-form height and gradient; guarded ripple loop; per-band `omega ~ sqrt(k^3)` trains; Fresnel-Schlick; slant-path absorption; temporal sheen from exact C.
MECHANISM:
- tactic 2: a capillary surface beads along the node where the slope is steep and the height crosses zero. A turbid film crawls toward the thicker region (Marangoni).
- tactic 3: `hCenter` and `hg.yz` are the whole surface and are only used for the normal and the path length.
- tactic 6: C is the sheen color. The bead is in the color the sheen already trails.
ADD:
  1. Meniscus bead — a cool highlight where height is near zero and the analytic slope is in the capillary band, scaled by Surface Tension.
  2. Marangoni crawl — an extra UV shift along the height gradient, toward thicker film, scaled by Surface Tension and Turbidity. Refraction and absorption stay.
FORBID: a particle solver, a second spring, an IQ palette.
A PACKING: ACES display RGBA (unchanged; sheen reads C as color).
FORMULA: no §12.2 row (Fresnel and Beer-Lambert are already the 2026-08-23 pass).

## hybrid-particle-fluid

IDENTITY: curl-advected particles with glowing trails over a decaying dye ribbon.
KEEP VERBATIM: Particle Density / Flow Speed / Trail Decay / Glow Radius; curl velocity; exact-C advection and the two-tap LIC; cosine palette; bass velocity tint; vorticity color. A stores pre-ACES dye.
MECHANISM:
- tactic 2: a particle's wake follows its own last step. A crowd of them turns the dye milky.
- tactic 3: the advect loop already computes a per-particle `vel` and throws it away; the trail then uses the *pixel* velocity, so every wake is parallel.
- tactic 6: C is the dye. The wake still reads those same texels.
ADD:
  1. Particle-owned wake — the trail offset uses the particle's last curl step, not the pixel velocity.
  2. Suspension milk — where `particleIntensity` is high relative to the particle count, the dye mixes toward a pale tint of the particle color and alpha rises.
FORBID: replacing curl noise with a grid solver, a new palette family, a spring.
A PACKING: display RGB in A; ACES on `writeTexture` (unchanged).
FORMULA: no §12.2 row.

## ink-bleed

IDENTITY: ink laid by a spring nib, wicking along paper fibres faster than across them, fading, and soaking into the photo.
KEEP VERBATIM: Ink Hue / Spread Speed / Fade Speed / Ink Density; fibre-frame 4-neighbor weights; spring nib in `extraBuffer[133..136]`; speed-thinned deposit; click splats; exact C loads. A stores `(ink, 0, 0, ink)`.
MECHANISM:
- tactic 2: watercolour pigment concentrates on the wet edge and granulates in the thin wash.
- tactic 3: `e,w,n,s` are fetched for the fibre weights. Their difference is the edge. `paperTexture` is fetched for absorption and then only scales alpha.
- tactic 6: the wet edge is written into the ink field so the next frame's diffusion carries it. Granulation is a render of that field.
ADD:
  1. Wet-edge bead — `length(e−w, n−s)` times ink×(1−ink) is added back into the ink, scaled by Spread Speed, and the stroke is darkened there.
  2. Paper granulation — a thin, low-density wash is multiplied by the existing paper hash so pigment stays in the pits. Thick ink is left smooth. State is the ungranulated field.
FORBID: a Gray-Scott replacement, a second nib, an IQ palette.
A PACKING: raw ink in A.r and A.a (unchanged). ACES on display only.
FORMULA: wet-edge accumulation (§12.2C); paper granulation (§12.2C). This is the only file in the batch using those rows.

## ambient-liquid

IDENTITY: curl-advected photo with a real Gray-Scott U/V field, metaball ink, and anisotropic sheen.
KEEP VERBATIM: Viscosity / Turbulence / Ripple Strength / Color Shift roles; curl displacement; click V seeding; feed/kill from the FFT band; metaball `smin`; HSV shift; anisotropic spec; vignette and grain. A stays `(U, V, inkMask, luma)`.
MECHANISM:
- tactic 1: the Laplacian is a 5-point cross, so spots prefer the axes.
- tactic 2: where the reaction has eaten the substrate, the liquid under the ink is a darker pool.
- tactic 3: `chem.x` (U) is stepped and then only V is shown.
- tactic 6: both ideas keep the same A packing. The stain is display-only.
ADD:
  1. Isotropic 9-point Laplacian — edge weight 0.20, corner weight 0.05, rescaled by 4 so the Gray-Scott rate matches the old cross.
  2. Depletion stain — darken the photo where U is spent and V is present, scaled by Ripple Strength (the slider that already mixes the ink).
FORBID: swapping in FitzHugh-Nagumo, a new palette, a spring.
A PACKING: raw `(U, V, inkMask, luma)`. ACES on display only. B still receives the display diagnostic.
FORMULA: isotropic 9-point Laplacian (§12.2D). This is the only file in the batch using that row. `gen-reaction-diffusion` already has a 9-point stencil and does not get a second one.

## magnetic-interference

IDENTITY: a pointer magnet with domain walls, hysteresis, scanlines, and a velocity trail, displacing the photo.
KEEP VERBATIM: Strength / Radius / Aberration / Scanlines; pull, swirl, gravity well, velocity trail; eight wall families; coercivity gate and remanence; scanlines; treble sparkle; chromatic shift. `extraBuffer[133..135]` stays the pointer and the bass envelope. A stays display RGBA.
MECHANISM:
- tactic 2: a real magnet flips in Barkhausen jumps while it is crossing coercivity, and iron filings line up with the field.
- tactic 3: `switching` is a smooth mask. `totalDisp` has a direction that is never walked.
- tactic 6: C is the previous display color (the hysteresis mix). Filings sample the photo, not a new field.
ADD:
  1. Barkhausen crackle — a per-cell pulse only while `switching` is mid-flip, flashing the remanent color.
  2. Iron-filing streaks — three short taps along `totalDisp`, mixed in only inside the magnet's influence.
FORBID: a vortex-style full-frame LIC, a new palette, a second spring.
A PACKING: ACES display RGBA (unchanged).
FORMULA: no §12.2 row.

## lava-lamp-blobs

IDENTITY: rising metaball wax with blackbody cores, melt windows, click heat, and a spring-followed pointer.
KEEP VERBATIM: Blob Count / Rise Speed / Melt / Heat; per-blob FFT voice; click blobs; spring in `extraBuffer[133..136]`; saddle meniscus; cooler skin; OkLab mix; A packing `(blobShape, blobHalo, heat, alpha)`.
MECHANISM:
- tactic 2: wax inside a blob rolls upward, and the top of a rising blob cools.
- tactic 3: `fy`, the vertical field difference, is computed for the meniscus gradient and then reduced to a length.
- tactic 6: C is the raw field. Bands and the cap are display tints of `blobShape`.
ADD:
  1. Convection rolls — a slow band inside `blobShape`, scrolling with Rise Speed, nudging the core blackbody.
  2. Cooled cap — where the field falls as y increases (the top of the blob) and the pixel is not the hot center, mix toward the existing skin temperature.
FORBID: a new blob primitive, a fluid solver, thin-film oil.
A PACKING: raw `(blobShape, blobHalo, heat, alpha)`. ACES on `writeTexture` only.
FORMULA: no §12.2 row.

## tornado-vortex

IDENTITY: a Rankine funnel with inflow, updraft, debris, click satellites, and treble lightning.
KEEP VERBATIM: Intensity / Spin Speed / Debris Amount / Lightning; Rankine `vTheta`; radial inflow; updraft; satellite vortices; condensation wall; OkLab funnel; blackbody bolts; ground dust.
MECHANISM:
- tactic 2: the eye is clear, and a strong funnel develops a breakdown bulb where the updraft stalls.
- tactic 3: `coreRadius` is a constant width. Fog is densest on axis, which fills the eye the real vortex leaves empty.
- tactic 6: C is not read. A stays the display color.
ADD:
  1. Clear eye — Beer-Lambert fog is suppressed inside the Rankine core so the eyewall reads as a wall.
  2. Breakdown bulb — `coreRadius` swells at mid-height with Intensity, and the updraft is stalled inside that bulb.
FORBID: replacing Rankine with Lamb-Oseen (that is `vortex`), a debris galaxy, a spring.
A PACKING: ACES display RGBA (unchanged).
FORMULA: no §12.2 row.

## gen-reaction-diffusion

IDENTITY: Gray-Scott or FitzHugh-Nagumo on one field, mouse and click spirals, bass pulses, treble speckle. File is `gen_reaction_diffusion.wgsl`.
KEEP VERBATIM: Excitability / Recovery / Stimulus / Model Blend roles; 9-point Laplacian; gradient-stretched GS feed; FHN cubic; refractory trough on the FHN color; spiral seeds; raw A `(state, waveFront, fitzMode)` with no tone map. B stays the diagnostic color.
MECHANISM:
- tactic 2: an FHN cell in its refractory trough cannot fire again. A tight bend propagates slower.
- tactic 3: the trough is a display multiply. The stimuli still add into `du` on that trough. `lap.x` and the GS gradient magnitude are both already computed.
- tactic 6: the gate changes the FHN step only. Gray-Scott stimuli stay open. A packing does not change.
ADD:
  1. Refractory stimulus gate — mouse, audio, treble, and spiral stimuli on the FHN branch are multiplied by `(1 − preRefractory)`, using the same trough thresholds as the display. The Gray-Scott branch is not gated.
  2. Curvature slowing — the FHN timestep shrinks where `|lap| / (|grad|+ε)` is large, and that bend picks up a faint tip highlight.
FORBID: a third model, an IQ palette, a spring, clamping the stored FHN state.
A PACKING: raw sim fields in A (negatives allowed). ACES on `writeTexture` only.
FORMULA: no §12.2 row. The existing 9-point stencil stays; the isotropic-Laplacian row is spent on `ambient-liquid`.
