# Generative Eight — Idea Cards (written before any WGSL edit)

**Agent:** claude · **Date:** 2026-09-21 · **Contract:** `docs/SHADER_UPGRADE_BATCH.md` §0/§2/§7

Selection rule: the smallest generative files (`shader_definitions/generative/`) with no `^//  Ideas:` line, no
`^//   [A-D]\. ` idea blocks and no `Batch 6x` stamp, read in full before claiming. `gen_capabilities` was skipped:
it is a capability probe, not an effect.

**Runtime caveat (re-checked today):** `src/renderer/webgpu/audioDepth.ts:5` still says binding 12 has "no per-frame
CPU writes", so `plasmaBuffer[0]` reads zeros in the app. Every idea below is visible with audio at zero. Audio
hooks are allowed to ride along, but none of them carries an idea.

**Family warning:** four files (velvet, serpent, oracle-jelly, calligraphic) come from one 2026-08 generator and
share an identical drag-mask / ripple-loop / history scaffold. That is exactly where one overlay could spread to
all four. The cards below give each one a mechanism that only makes sense for its own motif, and no idea is shared
with any other file.

---

```
SHADER: gen-cosmic-velvet-hypnosis
IDENTITY: soft log-spiral velvet well with counter-spiral moiré, runners and a violet core
KEEP VERBATIM: spiralPhase / velvet / rings / runner / counterSpiral / moire / velvetWeave; drag torque;
  click halos; inward radial history pull; 4 params
ADD:
  1. crushed-velvet pile — the fibres lie along the spiral arm tangent, and the pile direction flips in noise
     patches, so a slowly turning light makes some patches shine and others go dark. That light/dark patchwork
     is what crushed velvet looks like, and it only makes sense on a fabric.
  2. nested octave wells — plush seams at log-spaced radii (r = r0·k^n) that drift inward over time, so the well
     reads as endlessly sinking. The motif is already a log-spiral, and this repeats it by octave.
FORBID: new springs, new ripples, a second palette, a tunnel raymarch
A PACKING: ACES display RGBA (HEAD, read back as colour history)
```

```
SHADER: gen-prismatic-serpent-river
IDENTITY: lane-braided slithering serpents with scales, fins and eyes over a river current
KEEP VERBATIM: lane/slither kernel, scales, fins, wake, riverCurrent, drag, click shed skins, 4 params
ADD:
  1. finite serpents — each lane carries separate bodies with a head end and a tapering tail, with
     river-only gaps between them. Today every lane holds one sine body of infinite length. Eyes gather at the heads.
  2. prismatic dispersion — the body is solved separately for R, G and B, with the slither amplitude scaled
     per channel, so the edges split into rainbow fringes. Iridescence sets the spread. The file is called
     *prismatic* and never refracts.
FORBID: particle trails, generic IQ overlays beyond the file's own palette, springs
A PACKING: ACES display RGBA (HEAD)
```

```
SHADER: gen-cyber-terminal
IDENTITY: curved-CRT green digital rain over the source, with phosphor trails from C
KEEP VERBATIM: curvature, column speeds/drops, trail window, scanlines, input mix 0.8, HDR history in A,
  4 params (density / sharpness / brightness / scanline bloom)
ADD:
  1. segment glyph font — each cell draws a random subset of a 3×5 stroke skeleton (7-segment-style bars plus
     diagonals) instead of a single cross, so the rain reads as characters. Glyph Sharpness still sets the stroke width.
  2. white-hot leader — the cell at each falling drop's head burns near-white and flickers to a new glyph every
     frame. The green tail cools behind it. This is the thing that says "terminal rain".
FORBID: mouse lens, ripples, a new colour palette (phosphor green stays)
A PACKING: raw HDR display RGBA history (HEAD, documented in feedbackPacking)
```

```
SHADER: gen-chromatic-oracle-jelly
IDENTITY: grid swarm of drifting bell jellies, each with an oracle eye, sigil ring and curling tentacles
KEEP VERBATIM: cell grid + seeds, bell/rim/eye/pupil/tentacle/sigil/deepBell shapes, drag push, click
  prophecies, 4 params
ADD:
  1. pulse-swim — each jelly runs a contraction cycle: the bell narrows and stretches while the body surges
     up in a staircase (thrust, then coast). Tentacles stream out longer during the stroke. This is how jellyfish swim.
  2. watching eye — every pupil turns toward the pointer, clamped inside the iris. Each eye blinks on its own
     seeded schedule, with the lid squashing the eye vertically. "Oracle eyes" that never look at anything are a
     mechanism that was declared but never used.
FORBID: tentacle physics sim, springs, a new palette
A PACKING: ACES display RGBA (HEAD)
```

```
SHADER: gen-emergent-calligraphic-weave
IDENTITY: 3–10 flowing calligraphic filaments with pressure nibs and chromatic hairlines on dark paper
KEEP VERBATIM: curve/derivative/nib kernel, hairlines, hueMoment colouring, held-pointer warp, click ink
  fronts, HDR history, 4 params
ADD:
  1. over/under weave — each stroke carries a height that varies along x, and wherever strokes cross, the lower
     one is occluded by the upper one. Crossings alternate over and under like cloth. Today strokes are only summed,
     so the "weave" in the name is never drawn.
  2. dry-brush starvation — each stroke's ink load runs out along its path and is refilled periodically. A
     starved nib breaks into bristle streaks parallel to the stroke. It is native because the nib width already
     models pressure.
FORBID: fluid sim, paper-fibre bleed via C (keeps the history at its HEAD weight), springs
A PACKING: raw HDR display RGBA history (HEAD)
```

```
SHADER: gen-hyperbolic-tree
IDENTITY: branching tree fractal inside a Poincaré disk, sway, chromatic left/right leaves
KEEP VERBATIM: Möbius mapping, depth/angle param roles, sway terms, hue2rgb colouring, disk edge fade
FLOOR FIX (not an idea): the fork side was chosen by `hash12(mobius*100 + i)`, which is per-pixel white noise, so
  each pixel followed a random path and the tree rendered as speckle. It now descends into the child whose half-plane
  contains the pixel, which is the standard single-path tree trick. The C read was a filtering sampler on
  rgba32float and becomes an exact textureLoad.
ADD:
  1. terminal leaves — a leaf disc at each path's final tip, coloured by the existing left/right chromatic leaf
     hue. HEAD's "leafGlow" was only a halo around the branches.
  2. ideal-polygon geodesics — faint Poincaré-disk geodesic arcs (circles orthogonal to the rim) that form an
     ideal N-gon, slowly rotating behind the tree. This is the hyperbolic plane the tree lives in, drawn at last.
FORBID: raymarching, springs, ripples
A PACKING: ACES display RGBA (HEAD)
```

```
SHADER: gen-protocell-division
IDENTITY: iridescent smin-blob oil protocells that pinch into two daughters and merge back
KEEP VERBATIM: cellSDF motion + split + smin, film/fresnel iridescence, core pulse, mouse attraction, 4 params
FLOOR FIX (not an idea): C was sampled with a filtering sampler at *centred* coordinates (uv ∈ ±0.9), so it read the
  wrong pixels. It is now an exact textureLoad at coord.
ADD:
  1. cleavage furrow — a bright contractile ring pinching the neck between the daughters, peaking mid-division.
     Division is the whole mechanism of the file and it has no furrow.
  2. mitotic nuclei — two dark-cored nuclei inside each cell that separate *ahead* of the membrane
     (the nucleus divides first, then the cell). In the resting phase they are merged into one.
FORBID: a new sim, springs, generic chromatic aberration as the idea
A PACKING: ACES display RGBA (HEAD, straight colour in A; writeTexture premultiplied as HEAD)
```

```
SHADER: gen-ferrofluid-monolith
IDENTITY: raymarched twisted obelisk with ferrofluid radial spikes and an emissive core, pointer orbit
KEEP VERBATIM: mapScene twist/box/shell/core, orbit camera, chrome shading, glow march, click field, 4 params
ADD:
  1. Rosensweig cone lattice — a counter-helix multiplies the existing helical ridge field, so the ridges break
     into discrete peaks in a crossed lattice. That is the normal-field instability ferrofluid actually shows.
  2. core-light reflection — the chrome reflects the emissive core. A reflected ray's closest approach to the core
     axis becomes a blue streak on the facing spike flanks, which ties the two materials together.
FORBID: floor plane, particle sparks, springs
A PACKING: raw HDR display RGBA history (HEAD)
```
