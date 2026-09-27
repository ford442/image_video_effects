SHADER: gen-psychedelic-layered-time-stamps

IDENTITY (one sentence): the live video summed as up to 10 delayed, OkLab/blackbody-tinted copies (weight exp(-delay*scale*i)) with sinusoidal chromatic-split distortion, a Fresnel rim on the distortion edges and a light feedback mix.

KEEP VERBATIM:
- zoom_params roles: x = layer count (i32(x*10+3), loop hard-capped at 10), y = delay_scale, z = distortion_amp, w = chromatic_shift*0.01. Saved defaults 0.5/0.5/0.5/0.5 and the JSON updatedParams untouched.
- sin(uv.y*10+t) / cos(uv.x*10+t) distortion field with (1+2*bass) gain, R/B chroma split (+/- chromatic_shift*(1+bass|treble)).
- layer_weight = exp(-current_delay*delay_scale*i), final/layer_count, OkLab mix of layer tint with blackbody(layer_factor+bass*0.3), the Fresnel rim, held-mouse bass flash, alpha formula, depth passthrough.
- applyGenerativePrimaryControls display wrapper (intensity / speed pulse / contrast / mouse gain + ACES). It double-duties the four sliders but is HEAD's look; retained, noted.
- A delay clock advances 0.01/frame and wraps (same speed).

ADD (native ideas):
  1. Lagged echo taps — today every layer multiplies the SAME base sample, so the "time-stamps" are only tints. Each layer i now re-samples the video through the distortion field evaluated at (time - i*lag), lag scaled by delay_scale, with the same R/G/B chroma split. Layer 0 is bit-identical to HEAD's base sample; older layers trail as phase-lagged ghosts of the distortion. Layers become real dated stamps.
  2. Postmark rings — each layer stamps a dashed ring on its own age phase (the same color_shift phase already used for its tint): radius grows with age, fade envelope sin(pi*phase) so it is born/dies invisibly, inked in the layer's OkLab/blackbody tint, rings warped by the same distortion (z slider), centred on the pointer (default 0.5,0.5). A postmark per layer, on the layer's own clock.
  3. Delay wavefront — HEAD's delay clock is one global sawtooth (every texel identical, whole frame pops at wrap). Clock is now offset by radial distance from the stamp anchor, so the wrap edge (the stamp "edge" of the weights) sweeps outward from the anchor as a ring instead of a global pop.

FORBID on this file: spring/extraBuffer state, click shockwaves, ripple-w scaling, IQ cosine palette as the look, ferro/quantum motifs from sibling files, replacing the layer-sum with a different accumulator.

SILENT BUGS FIXED (read path):
  - plasma_color = plasmaBuffer[0..254].rgb: only [0] is ever uploaded (bass,mid,treble,0); the other 255 entries are zero, so the per-layer "plasma color offset" was black and every layer tinted only by blackbody. Replaced by a stateless OkLab hue-cycle ink (stamp_ink) on the same color_shift phase (restores the "different color offset per layer" the description promises). Consequence: layer tints are now hue-varied, not monochrome warm; documented, not hidden.
  - srgb_to_linear/linear_to_srgb: pow of negative (out-of-gamut OkLab) is NaN; bases clamped with max(...,0).
  - Feedback: HEAD read C.rgb via textureSampleLevel with a filtering sampler on rgba32float while A stored only (delay,0,0,1) — so "feedback" was a red sawtooth tint. Packing lie. Now exact textureLoad(C) and A stores raw pre-ACES accumulated colour in .rgb with the delay clock moved to .a (read back with the same packing).
  - Duplicate delay_track load removed.

A PACKING: raw pre-ACES accumulated feedback colour in A.rgb, wrapping delay clock in A.a; C read exactly the same way. ACES only on writeTexture. (HEAD packed the clock in A.x, read C.rgb as colour = packing lie, fixed and stated here.)

Notes: ripples unused by HEAD, none added. No extraBuffer use. Audio from plasmaBuffer[0].xyz only rides along (bass gain, treble chroma); all three ideas visible at audio = 0. Slider mapping: idea 1 lag scales with y (delay), idea 2 ring warp with z (distortion); no new sliders. Default look is NOT numerically identical to HEAD (tint hue, echo lag, feedback repaired); look unverified — no GPU here.
