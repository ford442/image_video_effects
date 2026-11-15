# Notes — grok/small-ten (2026-11-15)

Idea cards were written first in `BRIEFS.md`. Saved `params` are byte-exact. Six pasted headers were migrated with `migrate_to_prelude.py` before the idea edits (`chroma-kinetic-blackbody`, `liquid-smear-structure`, `predator-camouflage`, `spectral-bleed-confinement`, `pp-ssao`, `radiating-displacement`). That migration is not an upgrade.

No new spring. `spectral-bleed-confinement` keeps the spring it already had in `extraBuffer[133..138]`.

Formula used: wet-edge (§12.2C) on `liquid-smear-structure` only. No other §12.2 row. No row is shared.

## adaptive-mosaic

Kept: tile size, depth blend, bevel, audio sensitivity, variance subdivision, neighbour mortar, grout runners, Voronoi crackle, C color mix.
In the diff: directional grout lip (`// ── Idea 1`) uses the bevel face; per-tessera glaze (`// ── Idea 2`) tints the centre sample.
A packing: ACES display RGBA. C is color history.

## chroma-kinetic-blackbody

Kept: strength, radius, luma influence, rotation, split axis, baseline offsets 1.00 / 0.18 / 0.68, C luma-delta boost, `blackbodyColor`, mouse heat, 0.6 mix.
In the diff: Wien split scales the red and blue offsets from the temperature this pixel already has. White-hot core desaturates toward luma inside the same falloff and leaves a warm shoulder. ACES runs once on the final blend so the blackbody radiance is not crushed before the mix. `log` in the cool branch is guarded.
A packing: ACES display RGBA. C is that display, read for the luma delta.

## hybrid-magnetic-field

Kept: field intensity, line density, trail persistence, distortion, both poles, 3-tap exact-C LIC, palette, vortex, pole glow.
In the diff: iron filings break the existing sine along the streamline. The null marker sits on the stagnation of the 1/r² pair, closer to the weaker pole, and only where `|B|` is small.
A packing: pre-ACES RGB in A so trails can accumulate. ACES on `writeTexture` only.

## liquid-smear-structure

Kept: smear decay, LIC steps, coherence boost, mouse influence, gradient → tangent → coherence, ±3 taps, advected C, brush, click fronts, angle palette.
In the diff: LIC step length is `streamline * mix(0.18, 1.0, coherence)`. Wet-edge (§12.2C) darkens fresh paint where coherence is high.
A packing: linear display RGBA in A. ACES on `writeTexture` only.

## predator-camouflage

Kept: cloak radius, refraction, chromatophore speed, noise scale, thermal map, rim split, sac runners, hunt sweep, click fronts.
In the diff: pigment chases `C.z`; chromatophore speed is the chase rate; `A.z` stores the chased pigment. After the thermal mix, interior luma is scaled back to the unrefracted photo. Rim additions stay after that, so the silhouette is unmatched.
A packing: raw cloak fields `(mask, rim, pigment, alpha)`. ACES on `writeTexture` only. The old custom filmic curve was replaced with catalog ACES on that display store (floor, not an idea).

## ring-slicer

Kept: ring count, rotation speed, chaos, mouse follow, alternating direction, FBM radius wobble, grab-twist, fract wrap, seam palette.
In the diff: `(ringPos - 0.5) * chaos` shears the angle inside each ring. The same seam distance darkens a kerf; the palette glow still sits on it.
A packing: ACES display RGBA. C is unread. This file did not write A; it now writes the same display colour. The old soft-knee (ACES only above luma 1) became a full ACES on the display store.

## spectral-bleed-confinement

Kept: bleed radius, confinement, curl speed, edge threshold, 6-tap `channelTap`, 120° fan, `exp(-cross * confinement)`, the existing spring, C afterglow.
In the diff: `edgeGradient` keeps the direction `edgeMagnitude` used to drop. The fan axis mixes from the curl toward that normal. Rejected bleed (`bleed * (1 - confine)`) is added back as luma. The click `pow` of a signed distance was rewritten as a square so the base cannot be negative.
A packing: ACES display RGBA. C is that display.

## pp-ssao

Kept: radius, intensity, quality sample counts 4/8/16, color bleed, cosine weight, bent-normal bleed, pointer field, click fronts, scan packet.
In the diff: a sample occludes only past `0.0015 + 0.06 * radius`. The same loop tracks the max horizon angle and mixes it with the count. Intensity still scales the result.
A packing: ACES display RGBA. C is unread.

## alpha-spectral-decompose

Kept: four gain sliders and their tints, 8×3 neighbourhood, DoG residuals, 0.2 original mix, mouse high-band boost, ripple pulse.
In the diff: the unused `gaborFilter` now steers `bandA` from inside the existing loop. `bandR` chases `C.r` (other bands stay instant). Bass / mids / treble scale the matching gain as `(1 + band * k)`.
A packing: raw band luma. ACES on `writeTexture` only. Empty history does not lag (the mix turns on once C has energy).

## radiating-displacement

Kept: wave speed, displace strength, saturation threshold, wave radius, neutral gate, click ripples with depth-scaled amplitude, far-depth ambient, phase-split RGB.
In the diff: `waveDisplacement` multiplies by `1/sqrt(dist * (7/radius) + 1)`. A smoothstep from the threshold over 0.4 in saturation scales the cursor wave and the phase split. Clicks are not rescaled.
A packing: ACES display RGBA. C is unread.
