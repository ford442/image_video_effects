# Retro-glitch eight — 2026-10-10

Idea cards written before WGSL edits. Each shader gains two native ideas. Saved params stay byte-exact. Existing springs, click fronts, and ACES stay where the file already has them. No new spring is added.

## data-moshing

IDENTITY: motion-compensated macroblock smear driven by an accumulated UV offset.
KEEP VERBATIM: flow-from-gradient offset, spring scrub, click-front corruption, block hash events, smear / block size / corruption / quantize, A = offset.xy + confidence + age.
ADD:
  1. Macroblock motion vector — snap the per-pixel offset onto one axis per block so the smear moves as an MPEG vector. Block size owns the cell.
  2. Residual spark — a red chroma fleck where this frame's offset disagrees with the stored vector. Corruption owns the fleck.
FORBID: a second spring, IQ palette, reading A as color.
A PACKING: raw sim (offset.xy, confidence, age). ACES only on writeTexture.
SYMBOLS: `macroblockMV`, `residualSpark`

## data-moshing-diffusion

IDENTITY: anisotropic diffusion of a datamosh UV offset, with stream packets and a held swirl.
KEEP VERBATIM: fp128 offset add, kappa diffusion loop, stream packets, smear / kappa / dt / quantize, click fronts, A = offset.xy + alpha.
ADD:
  1. Tangent diffusion — boost the diffusion coefficients along the image edge so smear runs with the contour. Kappa still sets the base coefficient.
  2. Packet wake — a short sample pulled upstream of the packet, mixed in by the packet brightness.
ALSO: stop mixing C.rgb into the picture. C is the offset field, not a color history.
FORBID: a new spring, IQ palette.
A PACKING: raw sim (offset.xy, unused, alpha). ACES only on writeTexture.
SYMBOLS: `tangentDiffusion`, `packetWake`

## digital-decay

IDENTITY: block corruption, bit-flips, and a ghost of the previous frame.
KEEP VERBATIM: block hash displacement, bitFlip, ghost mix, spring hotspot, corruption / block size / ghost decay / depth influence, A = display color.
ADD:
  1. Block tear — the lower half of a corrupting block slides in x. Block size owns the split.
  2. Stuck row — a sparse horizontal line latches the ghost and ignores the new sample. Ghost decay owns how hard it sticks.
FORBID: a new spring, IQ palette.
A PACKING: ACES display RGBA. C is the previous display frame.
SYMBOLS: `blockTear`, `stuckRow`

## digital-waves

IDENTITY: three-sine interference that displaces the photo, with scanlines and block glitches.
KEEP VERBATIM: three-sine field, glitch blocks, pixelation mix, spring focus, live slider roles (x displacement, y speed, z scale, w detail). Saved param names stay even though they differ from those roles.
ADD:
  1. Standing nodes — darken where the three sines cancel. Displacement scale still owns the travel.
  2. Crest scanlines — scanline pitch bunches where the wave is high, using the existing scanline function.
FORBID: a new spring, a second palette.
A PACKING: raw diagnostic (wave, depth, ripple, alpha). C is not read. ACES only on writeTexture.
SYMBOLS: `standingNodes`, `crestScan`

## pixel-rain

IDENTITY: columns of falling matrix rain over the photo, with a fading trail.
KEEP VERBATIM: three rain layers, column scroll, spring repulsion, speed / glitch / density / trail fade, A = display color.
ADD:
  1. Glyph tail — dimmer hashed cells behind each drop head, longer when density is high.
  2. Column blank — a rare full-column dropout back to the photo. Glitch owns how often it reads as a dropout.
FORBID: a new spring, chrysanthemum bursts.
A PACKING: ACES display RGBA. C is the previous display frame.
SYMBOLS: `glyphTail`, `columnBlank`

## rgb-glitch-trail

IDENTITY: a decaying intensity field that warps the photo into a chromatic trail under the pointer.
KEEP VERBATIM: C intensity decay, radius add, warped FBM offset, chaos streaks, decay / radius / shift / chaos. No spring in this file.
ADD:
  1. Channel lag — R and B sample further along the existing warp direction. Shift strength owns the lag.
  2. Persistence comet — a dim streak taken from the intensity stored a few pixels upstream. Decay owns how much of that comet remains.
FORBID: adding a spring, click-front rewrite.
A PACKING: raw sim (intensity, trailHue.rg, persistence). ACES only on writeTexture.
SYMBOLS: `channelLag`, `persistenceComet`

## spectral-glitch-sort

IDENTITY: brightness-gated samples pulled along a sort angle, with a chroma split and an exact-C trail.
KEEP VERBATIM: luma threshold gate, angle, spring epicenter, click tears, strength / threshold / angle / noise, A = display color.
ADD:
  1. Sort walk — four steps along the sort axis, keeping the brighter sample. Strength owns the step length.
  2. Chroma sort — R and B take opposite extra steps on that same axis. Noise owns the extra step.
FORBID: a full-frame sort rewrite, a new spring.
A PACKING: ACES display RGBA. C is the previous display frame.
SYMBOLS: `sortWalk`, `chromaSort`

## datamosh-brush

IDENTITY: a pointer brush that smears the photo in macroblocks and ghosts the previous frame.
KEEP VERBATIM: spring smear vector, macroblock edge, decay mix, brush / block / decay / threshold, A = display color.
ADD:
  1. DC hold — a corrupting block mixes toward one sample at the block center so the macroblock goes flat. Threshold still scales the ghost.
  2. Mosquito ring — a high-frequency flicker on the existing macroblock edge. Mids scale it; the edge function stays.
FORBID: a new spring, a second brush shape.
A PACKING: ACES display RGBA. C is the previous display frame.
SYMBOLS: `dcHold`, `mosquitoRing`
