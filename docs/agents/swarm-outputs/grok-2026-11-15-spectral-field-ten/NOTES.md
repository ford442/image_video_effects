# Notes — spectral-field ten (2026-11-15)

Cards in `BRIEFS.md` were written before the WGSL. Saved `params` are unchanged. Real-GPU visual QA was not run (no GPU on this VM).

## photon-bins

Kept: graded-index bend, wall reflect, sim packing, 2×2 hash gather, persistence in A, spectrum ribbons, count fringe, ridge glint, night-dimmed plate. Present does not write A.

In the diff:
- March: Beer absorption on dark ground (§12.2F); Schlick keep on the existing reflect (§12.2F). Dispersion now follows mids, which the definition already declared (`audio: mid`). That wiring is floor, not an idea.
- Splat: elliptical kernel along `q.z`, the heading the gather already loaded.
- Present: caustic multiplied by source albedo. Alpha is coverage. Depth is scene depth plus coverage. ACES on the display only.

A packing: A/C stays spectral energy + count.

## conv-guided-filter-depth

Kept: linear model, luma range weight, photo-edge hold, mouse aperture, ripple dents, four slider roles.

In the diff: Gaussian spatial weight on the existing window; epsilon scaled by `varGuide`; guided colour clamped to the window min/max (§12.2A). The luma weight used `pow` of a signed difference; it is now a square. That is a fix, not an idea.

A packing: ACES display RGBA.

## datamosh

Kept: A = motion, age, strength; I-frame reset; chroma ghost from per-pixel C; phase-edge snap; the spring and click fronts already in the file.

In the diff: P-frame motion mixes from C at the block centre (§12.2B); predicted colour is quantized by Motion Strength on P-frames (§12.2B).

A packing: motion state in A. Display is ACES on writeTexture only.

## spectral-mesh

Kept: gradient density, wobble, mouse pull, spectralWavelength, diagonals, triangle wires, junction beads, grating fringe, A = (line, triLine, pull, alpha).

In the diff: lineWidth grows with `gradMag`; cell interior darkens, wires do not.

A packing: unchanged. C is not read.

## gen-fractal-lightning-canvas

Kept: branchBolt, seed loop, pointer bolt, strike, afterglow from C.r, cool/hot/core colours, four slider roles.

In the diff: tighter dendrite band (return stroke); sheath taper with radius; four exact-C neighbours as a scorch, scaled by the same Afterglow mix. C is `textureLoad` now. The filtering sample of C was invalid for the history format. That is floor.

A packing: A.r raw energy. Display is ACES.

## gen-bioluminescent-mycelial-nexus

Kept: three tubes, smin, fbm warp, held mouse pull, bass thickness, treble emit, SSS slider, 80-step march.

In the diff: noise3D uses the hermite weights it already computed; a sphere at the cell centre; the emit runs along the tube axis implied by the normal; three-tap AO on the lit body (§12.2E), emit left bright. Floor added with the ideas: ACES, semantic alpha, dataA, depth. C is not read.

A packing: ACES display RGBA.

## rainbow-vector-field

Kept: polar hue, Frequency on distance, saturation via `length`, brightness, ring phase, depth as displacement strength.

Floor, not ideas: pasted header replaced by `#include "_prelude.wgsl"`. Mouse uv is `zoom_config.yz` (it was divided by resolution). Mouse-down is `zoom_config.w` (the old code read `zoom_config.x`, which is time). ACES on display. Bounds guard.

In the diff: cos crest on the same ring phase; spokes at `freq` count; held swirl of the angle. Depth is still a scalar strength, plus the crest.

A packing: ACES display RGBA. C is not read.

## alpha-depth-fog-volumetric

Kept: seven layers, height, turbulence, temperature ramp, pointer clear, click shells, the small C smear, A = ACES rgb + transmittance. Beer was already the composite. This pass does not re-apply it.

In the diff: fog colour pulled toward bright source pixels; silver lining weighted by `4T(1-T)` with a 0.45 floor; far depth shifts toward the cool stop, weaker when Color Temperature is warm.

A packing: unchanged.

## cross-spec-alpha-spectral-bloom

Kept: radius loop, Cauchy split of the sharp plate, exposure, chromatic shift, mouse lamp, bass halo.

In the diff: the loop accumulates `max(sample - knee, 0)` and the knee drops as Exposure rises; red/blue Gaussian widths follow `(n - nG)` from the file's Cauchy (§12.2F), gained because n0 = 1.5 otherwise hides the difference; the plate is multiplied by `(1 - give)` before the bloom is added (§12.2F). Reinhard replaced by ACES. The old header said A stored four bloom bands. It stored display colour. The header now says so.

A packing: ACES display RGBA. C is not read.

## hyb-spectral-fbm-displace

Kept: domainWarp, Spectral Spread magnitude, conveyors, oil-slick, wavelength tint, held pull, click rings, Effect Mix, the 0.08 history weight.

In the diff: ±spread multiplied by a Cauchy ratio (§12.2F); the history sample is upstream of `dispVec`; a band across the warp, gated by how far the pixel moved. ACES on display. Alpha tracks warp length when the effect is mixed in.

A packing: ACES display RGBA. C is read as colour.
