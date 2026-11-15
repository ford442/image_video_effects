# Idea Cards — grok/small-ten (2026-11-15)

Written before the WGSL edits. Ten smallest remaining shaders (136–144 lines), mixed families. Each card adds 2–3 ideas inside the existing main path. Saved params stay byte-exact. No new spring. No shared ripple stamp. No shared palette.

Formula rule: wet-edge (§12.2C) is only on `liquid-smear-structure`. No other §12.2 row is used. No row is shared.

Six files still paste the binding header (`chroma-kinetic-blackbody`, `liquid-smear-structure`, `predator-camouflage`, `spectral-bleed-confinement`, `pp-ssao`, `radiating-displacement`). Those get `migrate_to_prelude.py` first. That swap is not an idea and is not why `Upgraded:` moves.

## adaptive-mosaic

```
SHADER: adaptive-mosaic
IDENTITY: depth-scaled photo tesserae with grout bevels, finer cells where the photo is busy, mortar mixed from the neighbours, and a Voronoi crackle.
KEEP VERBATIM: Tile Size, Depth Blend, Bevel Width, Audio Sensitivity; depth-scaled tile; held focus shrink; click pulse shrink; local-variance subdivision; 4-neighbour mortar; grout runners; Voronoi crackle; C color mix (decay).
MECHANISM INTERROGATION:
  tactic 2: a real tessera has a fired glaze and a grout joint that is bright on the lit face and dark on the other. The bevel is currently a uniform lip.
  tactic 3: inCell already says which face of the joint this pixel sits on. That direction is thrown away after the SDF.
  tactic 7: the joint has an orientation. Light from the upper left should catch one face.
ADD:
  1. Directional grout lip — the existing bevel SDF lights the face toward the upper left and recesses the opposite face.
  2. Per-tessera glaze — hash(tileId) tints and scales that tile's sample so neighbours are different firings, not one flat readout.
FORBID: a spring, a new palette, another Voronoi, reading C as anything but color.
A PACKING: ACES display RGBA (unchanged). C is color history.
```

## chroma-kinetic-blackbody

```
SHADER: chroma-kinetic-blackbody
IDENTITY: a mouse-centered kinetic RGB split whose size follows luma, mixed with a blackbody colour taken from that same luma, hotter under a held pointer.
KEEP VERBATIM: Effect Strength, Effect Radius, Luma Influence, Rotation; rotDir split axis; offsets 1.00 / 0.18 / 0.68 as the baseline; C luma-delta kinetic boost; blackbodyColor(); mouse heat on hold; 0.6 thermal mix.
MECHANISM INTERROGATION:
  tactic 2: Wien's law — a hotter body peaks at a shorter wavelength, so the blue fringe should outrun the red fringe as temperature rises. The split scales are fixed.
  tactic 8: blackbodyColor already multiplies by T^4 and then the core is tone-mapped before the mix, so the white-hot core never bleaches. The light should desaturate the core and leave the warmth in the fringe.
  tactic 3: temperature is computed and only used as a colour lookup.
ADD:
  1. Wien split — the existing R and B offsets scale with the temperature this pixel already has. Hot stretches blue; cool stretches red. Green offset stays 0.18.
  2. White-hot core — above the mid temperatures the core chroma collapses toward its own luma; a warm shoulder sits outside that core, inside the same falloff.
FORBID: a spring, an IQ palette, a second heat source, Cauchy as a separate lens.
A PACKING: ACES display RGBA (unchanged). C is that display, read for luma delta.
```

## hybrid-magnetic-field

```
SHADER: hybrid-magnetic-field
IDENTITY: two opposite-circulation poles (pointer and a drifting counter-pole) drawing field lines, with FBM distortion, LIC trails in C, and a vortex at the pointer pole.
KEEP VERBATIM: Field Intensity, Line Density, Trail Persistence, Field Distortion; magneticField(); source2 at −0.5 strength; 3-tap exact-C LIC; existing palette; vortex; pole glow. A stays pre-ACES so trails can accumulate; ACES only on writeTexture.
MECHANISM INTERROGATION:
  tactic 5: iron filings are dashes along the line, not a continuous sine. linePattern is a solid sin of angle.
  tactic 2: two opposite poles have a null between them. |B| is already computed and the null is invisible because fieldDir spins there.
  tactic 3: fieldMag near zero away from both poles is the null, and it is only used as line brightness.
ADD:
  1. Iron filings — hash along the streamline breaks the existing sine into bright segments and dim gaps. The sine, density, and palette stay.
  2. Null marker — the stagnation point of the 1/r² pair (closer to the weaker pole) draws a stable cross. It shows up only where |B| is actually small.
FORBID: a third pole, a new palette, a spring, replacing LIC with particles.
A PACKING: pre-ACES display RGB in A (unchanged). ACES on writeTexture only.
```

## liquid-smear-structure

```
SHADER: liquid-smear-structure
IDENTITY: structure-tensor streamlines advect a paint layer through C, with edge-aware LIC, a held-pointer stir, and click fronts. Angle tints the fresh paint.
KEEP VERBATIM: Smear Decay, LIC Steps, Coherence Boost, Mouse Influence; gradient → tangent → coherence; ±3 LIC taps; advect uv−flow from exact C; brush swirl; click fronts; palette on tangent angle. A stays linear; ACES on writeTexture.
MECHANISM INTERROGATION:
  tactic 1: the tangent is noise where coherence is low, but the LIC loop still steps the full streamline length.
  tactic 2: pigment in a wet smear darkens where the edge piles up. coherence is that edge and is only a flow gain today.
  tactic 6: C is the paint. Darkening the fresh sample at high coherence does not change the packing.
ADD:
  1. Coherence-gated LIC length — the same ±3 loop, step length mixed down where the tensor is uncommitted.
  2. Wet-edge darkening (§12.2C) — high coherence pulls the fresh paint toward a darker, browner edge. The slider still sets tensor gain, which already feeds coherence.
FORBID: a new solver, vorticity (no stored velocity), a spring (the brush is already the pointer), Gray-Scott.
A PACKING: linear display RGBA in A (unchanged). ACES on writeTexture only.
```

## predator-camouflage

```
SHADER: predator-camouflage
IDENTITY: a pointer-sized cloak refracts the photo, with chromatophore noise, thermal false colour, a chromatic rim, and pigment-sac runners.
KEEP VERBATIM: Cloak Radius, Refraction Strength, Chromatophore Speed, Noise Scale; thermalMap; rim chromatic split; cloakMask / rim / sacScale / sac runners / hunt sweep; click fronts. A stays the cloak fields (mask, rim, pigment, alpha), not display.
MECHANISM INTERROGATION:
  tactic 6: A.z is pigment and C is never read. Chromatophores hold their last expansion; the speed slider is the chase rate.
  tactic 2: active camo matches background luminance and fails at the silhouette. The thermal mix currently tints the whole disc the same way.
  tactic 5: the cloak's failure is a bright rim, which this file already has as `rim`.
ADD:
  1. Pigment memory — pigment chases the previous C.z. Chromatophore Speed still sets how fast. A.z stores the chased value.
  2. Luma-matched interior — after the thermal mix, interior luma is pulled back to the unrefracted photo. The rim additions stay unmatched, so the silhouette is where the cloak fails.
FORBID: a spring, storing display in A (that would wipe the pigment), a new creature, IQ palette.
A PACKING: raw cloak fields (mask, rim, pigment, alpha). C.z is previous pigment. ACES on writeTexture only.
```

## ring-slicer

```
SHADER: ring-slicer
IDENTITY: concentric rings of the photo spin in alternating directions around a mouse-follow centre, with FBM wobble on the radius and a palette seam.
KEEP VERBATIM: Ring Count, Rotation Speed, Chaos, Mouse Follow; alternating direction by ring index; FBM radius wobble; grab-twist on mouse-down; fract wrap; cosine seam palette. No spring.
MECHANISM INTERROGATION:
  tactic 4: Chaos is one wobble amplitude. A sliced ring also shears: the inner lip of a ring leads the outer lip.
  tactic 5: a saw cut has a kerf. The seam is only a glowing band; the cut itself should go dark.
  tactic 3: ringPos (fract of the sliced radius) is computed for the seam and not used on the angle.
ADD:
  1. Intra-ring shear — (ringPos − 0.5) × chaos added to the existing angle, so each ring twists across its own width.
  2. Kerf — the same seam distance darkens a thin cut; the palette glow still sits on that cut.
FORBID: a new palette, click ripples, a spring, changing alternating-direction parity.
A PACKING: ACES display RGBA. C is unread. This file did not write A; the write is the floor, same colour as writeTexture.
```

## spectral-bleed-confinement

```
SHADER: spectral-bleed-confinement
IDENTITY: edge-gated RGB bleed along a curl field, each channel confined by the product of the other two, with a sprung focus, click fronts, and C afterglow.
KEEP VERBATIM: Bleed Radius, Confinement, Curl Speed, Edge Threshold; 6-tap channelTap; 120° channel fan; confine = exp(−cross · confinement); existing spring in extraBuffer[133..138]; afterglow mix from exact C. Do not add a second spring.
MECHANISM INTERROGATION:
  tactic 7: edgeMagnitude returns a length and drops the gradient. Real chromatic fringe leaves along the edge normal; the curl should be biased, not replaced.
  tactic 8: confined bleed is deleted. The light that cannot cross should remain as a neutral rim on the edge.
  tactic 3: the cross-channel product is only a suppressor.
ADD:
  1. Normal-biased fan — the 120° split stays. Its axis mixes from the curl toward the edge normal as the edge gets confident.
  2. Confinement residual — bleed × (1 − confine) returns as luma on the source, so confinement moves energy instead of erasing it.
FORBID: a new spring, a thin-film look, replacing the curl, Cauchy radius scaling (the fan is the spectral part).
A PACKING: ACES display RGBA (unchanged). C is that display, read as afterglow.
```

## pp-ssao

```
SHADER: pp-ssao
IDENTITY: screen-space depth occlusion on the photo, sample count from Quality, cosine-weighted, with occluder colour bleed and a bent-normal tap.
KEEP VERBATIM: Radius, Intensity, Quality (4/8/16), Color Bleed; cosine weight; bent-normal bleed; held pointer field; click fronts; scan packet. No new spring.
MECHANISM INTERROGATION:
  tactic 1: the occlusion test is a count of closer samples. The same taps also have an elevation angle; the horizon is the next approximation of the same operator.
  tactic 2: a depth test with no bias acne-darkens flat walls. The radius is the scale of that bias.
  tactic 3: depthDiff is a signed distance and is only used as a boolean.
ADD:
  1. Depth bias — a sample counts only if it is closer by bias ≈ 0.0015 + 0.06 × radius. Same radius slider.
  2. Horizon mix — atan2 of the biased rise over sample distance, taken as a max over the same loop, mixed with the count. Intensity still scales the result.
FORBID: a spring, a new colour grade, GTAO sample directions that throw away the existing kernel, reading C.
A PACKING: ACES display RGBA (unchanged). C is unread.
```

## alpha-spectral-decompose

```
SHADER: alpha-spectral-decompose
IDENTITY: four frequency bands of the photo, stored in A as low / mid-low / mid-high / high, recomposed with four gain sliders and a fixed tint per band. The pointer boosts the high band; ripples flash it.
KEEP VERBATIM: Low / Mid-Low / Mid-High / High Freq Gain; 8×3 neighbourhood; DoG residuals; tint vectors; 0.2 original mix; mouse high-band boost; ripple pulse. A stays raw band luma, never ACES.
MECHANISM INTERROGATION:
  tactic 1: gaborFilter is in the file and never called. The high band is an isotropic Gaussian. The function is the oriented kernel the header already promises.
  tactic 6: A is the bands and C is never read. Lows in a real decomposer lag; highs do not.
  tactic 4: each gain is one band. Bass belongs on the low gain, treble on the high gain, mids on the two middle gains. The slider stays the gain.
ADD:
  1. Oriented Gabor on the high residual — inside the existing loop, a signed Gabor steers bandA. The DoG is still computed; the high band mixes toward the Gabor.
  2. Low-band inertia — bandR chases C.r. The other three bands stay instant.
  3. Band-matched audio — bass scales low gain, mids the two middle gains, treble the high gain. Each multiply is (1 + band × k) on the existing slider.
FORBID: ACES inside A, a spring, replacing the four tints, a display-history packing.
A PACKING: raw band luma (R low, G mid-low, B mid-high, A high). C is the previous bands. ACES on writeTexture only.
```

## radiating-displacement

```
SHADER: radiating-displacement
IDENTITY: waves radiate from the cursor and from clicks, and only saturated pixels move. Neutrals stay sharp. RGB is a phase split of the same wave.
KEEP VERBATIM: Wave Speed, Displace Strength, Saturation Threshold, Wave Radius; isNeutral gate; waveDisplacement; click ripples with depth-scaled amplitude; far-depth ambient; phase-split RGB. No spring.
MECHANISM INTERROGATION:
  tactic 2: a wave that radiates on a surface falls off as 1/sqrt(r). The mask is a flat smoothstep disk.
  tactic 4: Saturation Threshold is a hard gate. Just-above-threshold colour should barely move; a pure colour should take the full strength.
  tactic 3: hsv.y is only compared to the threshold.
ADD:
  1. Cylindrical spread — inside waveDisplacement, amplitude × 1/sqrt(dist / radius-scale + 1). The radius cutoff stays.
  2. Saturation-proportional amplitude — smoothstep from the threshold up over 0.4 in saturation multiplies the cursor wave and the phase split. Clicks keep their own depth falloff.
FORBID: a spring, another chroma model, moving neutral pixels, reading C (this file does not own a trail).
A PACKING: ACES display RGBA (unchanged). C is unread.
```
