# Claude cyber-glitch-eight — Idea Cards

Written before WGSL edits. 2026-10-19.

Batch: neural-raymarcher-gabor, neural-raymarcher, ascii-flow-structure, cyber-trace-structure,
data-stream-structure, byte-mosh-explosion, rgb-glitch-displacement, cyber-scan. Six of the eight
pasted the 13 bindings; they were migrated to `#include "_prelude.wgsl"` first in a separate
header-only commit (not counted). cyber-trace-structure and cyber-scan already carry `Ideas:`; their
prior ideas stay and new ideas continue the numbering.

Where a JSON param name disagrees with what the WGSL does with that slot (neural-raymarcher,
data-stream-structure, rgb-glitch-displacement), the WGSL role is the one presets were saved
against, so the WGSL role is what is kept.

## neural-raymarcher

```
SHADER: neural-raymarcher
IDENTITY (one sentence): the source photo with a depth-scaled RGB split, a warm depth glow and
  dark-blue volumetric fog, whose depth comes from a 5-layer mirrored (ping-pong) zoom march toward
  the zoom centre, spun by an FFT-bin vortex.
KEEP VERBATIM: ping_pong mirror tiling; 5-layer loop with layerSpeed = mix(x, y, layerDepth),
  noise flow, vortex from extraBuffer[10], density/weight accumulation; chroma from extraBuffer[0]
  scaled by baseDepth; the edgeGlow formula and tint; fog = exp(-baseDepth·w·3) toward
  (0.02, 0.05, 0.1); calculateVolumetricAlpha; depth output = baseDepth.
MECHANISM INTERROGATION:
  t3 (promote an intermediate): `baseColor`, the colour the 5-layer march accumulates, is computed
    and then thrown away — only its depth is used.
  t2 (physics one step further): the fog only absorbs (Beer–Lambert toward a constant). A
    participating medium also in-scatters the light it was marched through.
  name: "neural" — the march produces nested depth shells; a neuron's signature is the action
    potential: a sharp front with a refractory tail travelling along the membrane.
ADD (2 native ideas):
  1. Marched in-scatter — the fog colour is lit by the discarded 5-layer march colour, weighted by
     the fog amount, so deep fog glows with the tunnel it was marched through instead of going flat
     navy. Amount = Glow Intensity (zoom_params.z, dead at HEAD).
  2. Action-potential wavefronts — spikes travel through the march's depth shells
     (phase = baseDepth·k − t·v), a sharp leading edge with an exponential refractory tail, strongest
     where depth steps (depthGrad); the FFT-bin vortex value speeds the firing. Same warm tint as the
     existing glow; scaled by Glow Intensity.
FLOOR: zoom_params.z wired (was dead); clamp → ACES on display RGB.
FORBID on this file: springs, click fronts, IQ palette, a new SDF network, replacing the layer march.
A PACKING: A unused (C never read) — unchanged.
```

## neural-raymarcher-gabor

```
SHADER: neural-raymarcher-gabor
IDENTITY (one sentence): the neural-raymarcher depth-split / glow / fog base over the photo,
  overlaid (by Activation Vis) with a 4-orientation Gabor filter bank coloured by one cosine palette
  per orientation; alpha = dominant orientation strength.
KEEP VERBATIM: 5-layer march, chroma, edge glow, fog (glow param), orientations 0/45/90/135 plus
  the pointer-angle + camera-rotation offset, the four palettes, gaborSigma/gaborScale from the
  pointer, mix by activationVis, alpha = dominant orientation / gaborScale, depth = baseDepth.
MECHANISM INTERROGATION:
  t1 (deepen the kernel): the bank uses only the even (cosine) Gabor kernel, so a single step edge
    rings into a double line and the response flips sign with phase. The next-better operator on the
    same taps is the quadrature pair (cos + sin) — the energy model of a V1 complex cell.
  t2 (physics/biology one step further): real orientation channels inhibit each other (divisive
    normalization); here all four palettes blend toward grey where several respond.
ADD (2 native ideas):
  1. Quadrature Gabor energy — the odd (sine) kernel is accumulated in the same 81-tap loop;
     response = sign(even)·sqrt(even² + odd²). Phase-invariant: an edge reads as one clean ridge.
  2. Cross-orientation divisive normalization — palette weights w_i = E_i² / (σ + mean E²) instead of
     |E_i|: the winning orientation owns its colour, and the overlay gain saturates with local
     contrast (strong in textured regions, quiet in flat ones).
FLOOR: gaborFreq read zoom_config.x, which is time, so the frequency grew without bound and the bank
  aliased into noise within seconds — fixed to the legacy default (0.3 → 0.125 cycles/px). Clamp →
  ACES on display; alpha clamped to [0, 1].
FORBID on this file: springs, click fronts, new palettes, changing the orientation set.
A PACKING: A unused — unchanged.
```

## ascii-flow-structure

```
SHADER: ascii-flow-structure
IDENTITY (one sentence): an ASCII grid of 8 SDF glyphs picked by cell brightness, whose
  directional glyphs rotate along a structure-tensor flow field, tinted by LIC and phosphor green,
  bent by a spring-cursor vortex and locked by clicks / hold.
KEEP VERBATIM: 4 params and roles (grid density, coherence boost, LIC blend, mouse influence);
  smoothTensor + eigen decomposition, coherency pow; vortex + click shock + held lock; glyph set and
  index rules; flowColor/phosphor mix; spring [133..138]; ACES; A = (eigenvec.xy, coherency, lic).
MECHANISM INTERROGATION:
  t1/t5 (deepen the kernel / artifact of the real thing): ASCII art matches a glyph's ink coverage
    to tone; here every glyph has fixed stroke widths, so tone only lives in the index.
  t6 (use the history): A already stores the cell's eigenvector and coherency; on video the
    eigenvector's ±sign and small angle noise make directional glyphs flicker between / | \ .
ADD (2 native ideas):
  1. Ink-weight tone matching — stroke half-width (and dot radius, box wall) scales with the cell's
     brightness, thin for dark cells and bold for bright, so the grid carries tone continuously.
  2. Orientation hysteresis — the cell's flow vector is blended with last frame's (exact C.xy at
     the cell centre, sign-aligned) weighted by last frame's coherency; the pointer vortex stays
     immediate.
PACKING FIX: HEAD read C.a (which holds licValue) as the previous coherency; it now reads C.z,
  which is where A stores coherency.
FORBID on this file: new glyph sets, IQ palette swaps, extra springs or click fronts.
A PACKING: raw fields (eigenvec.x, eigenvec.y, coherencyBlend, licValue) — unchanged.
```

## cyber-trace-structure

```
SHADER: cyber-trace-structure (second pass; first pass 2026-09-11)
IDENTITY (one sentence): a structure-tensor LIC neon trace painted by a spring-cursor brush over
  the photo, coloured by flow angle, with eigenvector neon streaks and saddle bifurcation forks.
KEEP VERBATIM: 4 params (decay, glow, hue shift, brush size); spring [133..138]; tensor, eigen,
  coherency, Hessian saddle mask; brush; vortex; ripple turbulence; LIC + fork LIC; Ideas 1–2;
  colour chain; ACES; A = trace history RGBA.
MECHANISM INTERROGATION:
  t6 (use the history): the trace history in C only fades where it was drawn; nothing moves it,
    although every pixel knows the flow direction.
  t5 (artifact of the real device): a circuit trace is routed in 0°/45°/90° segments.
ADD (2 native ideas):
  3. Trace current — history is read from exact C upstream along the eigenflow (manual bilinear of
     4 exact loads, ~1.6 px), weighted by coherency, so painted traces run along image edges like
     current down a trace; isotropic areas just fade.
  4. Octilinear routing — the advection direction snaps toward the nearest 45° route in proportion
     to coherency, so traces run in straight PCB segments that bend at the saddle forks.
FORBID on this file: a second spring, new click fronts, IQ palette, replacing the LIC.
A PACKING: trace history RGBA — unchanged.
```

## data-stream-structure

```
SHADER: data-stream-structure
IDENTITY (one sentence): the photo cut into strips aligned with the structure-tensor eigenvector,
  each strip scrolling at its own speed, tinted green/cyber with a hex packet lattice, flicker
  blocks, pointer vortex and a C trail.
KEEP VERBATIM: 4 WGSL roles (x speed, y strip density, z turbulence, w glow); strips, per-strip
  speed, perp wobble, rand>0.75 jitter; hexGrid; bright blocks; palettes; spring [133..138];
  ripple boost; C.r trail; ACES; A = (trail, lum, flowAngle, alpha).
MECHANISM INTERROGATION:
  t5 (artifact of the real thing): a data stream is framed — packets with headers and gaps; here
    strips are a continuous smear.
  t3 (promote an intermediate): the tensor eigenvalues are computed, but only lambda1 is used;
    coherency (lambda1 vs lambda2) says where a lane has a direction at all.
ADD (2 native ideas):
  1. Packet framing — each strip is cut along its length into packets that travel with that strip's
     speed: a dark inter-packet gap and a lit 4-bit header at the leading edge, in the strip's
     palette colour. Scales with Glow.
  2. Lane collisions — where the tensor is isotropic but textured (corners, clutter: low coherency,
     non-zero trace), lanes have no direction, so packets collide: per-cell bytes re-hash in short
     time slots and jump. Scales with strip density (the JSON's "Corruption Rate" slot).
FORBID on this file: springs beyond the existing one, click fronts, IQ palette as the look.
A PACKING: (trail, lum, flowAngle, alpha) — unchanged.
```

## byte-mosh-explosion

```
SHADER: byte-mosh-explosion
IDENTITY (one sentence): the photo through a pointer-centred chromatic prism, packed into 8-bit
  RGBA words and corrupted per block by bitwise ops (XOR / AND / OR / shift / rotate / swizzle) at
  an audio-driven error rate, with ripple chroma waves and bit rotations.
KEEP VERBATIM: 4 params (operation mix, bit shift, error rate, prism strength); spring [133..138];
  prismDisplace shape; ripple chroma waves; block op selector and thresholds; pixel flips; pointer
  glitch zone; ripple rotations; flicker × scanline; spectral glow; ACES; semantic alpha.
MECHANISM INTERROGATION:
  t2 (physics one step further): a corrupted word desynchronises a decoder until the next resync
    marker, so real bitstream errors smear forward in scan order and misalign bytes.
  t5 (artifact of the real device): decoders conceal unrecoverable blocks by repeating the previous
    frame's block — frozen stale tiles.
  F (optical): the prism splits R/G/B by a fixed linear ±1; real glass follows Cauchy n(λ).
ADD (3 native ideas):
  1. Resync propagation — a block inherits a byte slip (RGBA word rotated by 8 bits: R←G←B←A) from a
     corrupted block up to 3 blocks to its left, decaying with distance, cut at resync markers every
     4 blocks.
  2. Error concealment — a share of corrupted blocks show the previous frame's decoded block from
     exact C instead of new data, holding stale tiles for a 0.5 s slot.
  3. Cauchy prism — channel deflections follow n(λ) = A + B/λ² at 650/550/450 nm (blue bends ~1.7×
     more than red) instead of −1/0/+1.
FLOOR: `finalColor.rgb = …` is invalid WGSL (swizzle assignment) — HEAD failed Naga and never
  compiled; rewritten as whole-vector assignment.
FORBID on this file: new springs, IQ palette, thin-film, a second tear system.
A PACKING: HEAD wrote (blue byte, error, glow, alpha) that nothing read; A is now ACES display RGBA
  (C read as colour for Idea 2).
```

## rgb-glitch-displacement

```
SHADER: rgb-glitch-displacement
IDENTITY (one sentence): a stack of digital glitch displacements (temporal block jumps, pointer
  wave, block / scanline offsets, column sort, datamosh near the pointer) with chroma-subsampling
  modes, DCT block edges, RGB shift, posterize bands, a rolling bar and per-wavelength absorption,
  carrying its offset forward through C.
KEEP VERBATIM: 4 WGSL roles (x chroma mode, y glitch intensity, z block size, w temporal); spring
  [133..136]; every displacement function and its order; colour chain; ACES; semantic alpha;
  A.xy = offset, A.z = glitch energy.
MECHANISM INTERROGATION:
  t6 (use the history): A.w is written as 0 and C.w is never read — a free latch bit.
  B (glitch family): scanline glitches re-roll every 1/15 s, so they flicker instead of locking the
    way a real tracking error does.
  B (datamosh): the offset carry is per pixel and decays; a P-frame carries whole macroblocks by the
    previous frame's motion vector until the next I-frame.
ADD (2 native ideas):
  1. Schmitt tracking latch (§12.2B) — per scanline band, a smooth drive with hysteresis
     (hi/lo from Glitch Intensity) latches a horizontal tear with a skew across the band; the latch
     lives in A.w and is read back from exact C.w.
  2. Macroblock motion carry (§12.2B) — inside the pointer's datamosh zone the offset carry reads
     the previous frame's 16 px macroblock vector (exact C at the block centre) with almost no
     decay, so blocks drift as units, and an I-frame every 2 s resets it.
FORBID on this file: springs beyond the existing one, thin-film, particle sparkles.
A PACKING: offset.xy, glitch energy, tracking latch in .w (was 0).
```

## cyber-scan

```
SHADER: cyber-scan (second pass; first pass ideas: LIDAR iso-depth contours, range readout)
IDENTITY (one sentence): triple sweeping scan beams over the photo, warm/cool by depth, with hex
  grid data, binary rain, interference, chromatic scan, LIDAR contours, a range readout and an
  afterimage trail from C.
KEEP VERBATIM: 4 params (scan speed, trail length, scan width, colour shift); beams and trails;
  holographic lines; hex; rain; interference; noise; chroma; sparkle; click bursts; Ideas 1–2;
  ACES; A = ACES display RGBA.
MECHANISM INTERROGATION:
  t2 (physics one step further): a LIDAR return is brighter from surfaces facing the scanner and
    darker at grazing incidence; the beam here lights everything equally.
  t5 (artifact of the real device): a radar / scanner scope uses a two-component P7 phosphor —
    blue-white flash that dies fast, yellow-green afterglow that persists.
ADD (2 native ideas):
  3. LIDAR return intensity — the main beam's emission is scaled by albedo (luma) × cos(incidence),
     with the normal from depth central differences; grazing silhouettes give dark no-return gaps.
  4. P7 phosphor trail — the C smear decays per channel (blue fastest, green slowest) so the
     afterimage turns yellow-green as it fades.
FORBID on this file: springs, more ripple systems, IQ palette.
A PACKING: ACES display RGBA — unchanged.
```
