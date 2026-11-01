# Grok 4.7 — mosaic / grid / voronoi twelve

Written before WGSL edits. Second pass where a file already named ideas: the new pair is additive and uses nouns already in that file. No shared spring, ripple stamp, or IQ palette. Cauchy on chroma-shift-grid only. Brown–Conrady on mouse-voronoi-mosaic only. Soft inverse-square on voronoi-light only.

```
SHADER: hex-mosaic
IDENTITY: a glass hex mosaic of the photo that reveals around the pointer, with grout, bevel, and a glint.
KEEP VERBATIM: density / reveal radius / edge hardness / sat boost; two-lattice nearest centre; press bulge; grout from hexEdgeDist; glint; click rings; vignette grain
MECHANISM INTERROGATION:
  tactic 2: a glass tile's highlight faces the light; the key here is fixed while the shader is pointer-led.
  tactic 3: the rejected lattice centre is already computed and discarded — it is the neighbouring pane.
  tactic 7: cellP is the bevel direction.
ADD:
  1. pointer-keyed bevel — the existing bevel faces the cursor instead of a fixed lightDir
  2. neighbour-pane leak — the rejected hex centre tints the grout, so mortar picks up the adjacent pane
FORBID: IQ palette, a new spring, shockwave rewrite
A PACKING: ACES display RGBA (C is not read)
```

```
SHADER: triangle-mosaic
IDENTITY: the photo sliced into rotating triangular facets with grout, tilt, and a seam runner.
KEEP VERBATIM: scale / rotation / twist / mix; skewed tri grid; chromatic seam; grout; centroid tilt; C blend by boundaryDist; params
MECHANISM INTERROGATION:
  tactic 2: leaded glass has metal beads at the vertices, and a tilted pane shows a second image through its thickness.
  tactic 3: tilt and the quad's other triangle are already implied by tri_offset.
  tactic 6: C stays the display-history blend already in the file.
ADD:
  1. vertex lead-came — beads at the three vertices of the current triangle
  2. tilt-axis thickness — a second sample along the existing facet tilt, mixed inside the pane only
FORBID: hex grout leak, IQ retint, spring
A PACKING: ACES display RGBA (unchanged; C is that history)
```

```
SHADER: mouse-voronoi-mosaic
IDENTITY: click sites are stained-glass panes that rotate, shift, and scale, with a leaded edge.
KEEP VERBATIM: shatter / edge thickness / color shift / glass opacity; ripple Voronoi; per-cell rotate-shift-scale; cosine tint from colorShift; mouse glow
MECHANISM INTERROGATION:
  tactic 2: crown glass bows the picture inside the pane; real leading is dark metal with a thin bright inner rim.
  tactic 5: old glass loses saturation as the pane ages (elapsed is already computed).
ADD:
  1. crown-glass bow — Brown–Conrady on the cell-local UV, k from shatter strength (§12.2B)
  2. dark lead plus inner rim — edge thickness still sets the band; glass opacity still scales it
  3. age patina — panes with a real click time drift toward a dull green-grey
FORBID: neural pulses, lantern spring, IQ as a new palette (existing colorShift tint stays)
A PACKING: ACES display RGBA (was not written; C is not read)
```

```
SHADER: focal-pixelate
IDENTITY: a pointer focus that stays sharp while the fringe quantizes into blocks with hex bokeh.
KEEP VERBATIM: pixel size / focus radius / softness / invert; block quantization; domain warp on the fringe only; hex kernel; LOD bias; A = (mix, 1/blocks, bass, alpha); B metadata
MECHANISM INTERROGATION:
  tactic 1: the hex kernel radius is locked to the block size; a lens circle of confusion grows with defocus on its own.
  tactic 3: fract(uv * blocks) is the pixel aperture and is thrown away once the centre is sampled.
ADD:
  1. pixel-aperture well — block corners darken, and only where the fringe is already pixelated
  2. defocus circle of confusion — hex radius widens with mix_factor, separate from the quantize grid
FORBID: Cauchy (that belongs on chroma-shift-grid), spring, click rings
A PACKING: unchanged raw metadata in A and B; ACES on writeTexture only
```

```
SHADER: pixelate-blast
IDENTITY: square pixel blocks blasted into Voronoi fragments around the pointer, with bevel and a finer core.
KEEP VERBATIM: density / blast radius / edge glow / chromatic; cascade lattice; bevel tilt; Cauchy-style R/G/B along blastDir; C feedback of linear HDR
MECHANISM INTERROGATION:
  tactic 2: fragments that leave the surface open a dark gap; they also smear along the blast.
  tactic 3: edgeDist and blastDir are already computed.
  tactic 6: C stays linear pre-ACES history.
ADD:
  1. separation gap — the existing Voronoi seam goes dark with blast energy, under the edge glow
  2. flight smear — one extra sample along blastDir, mixed by blast energy
FORBID: a new spring, internal hash fissure (that is voronoi-shatter), IQ retint
A PACKING: linear pre-ACES RGB + semantic alpha (unchanged)
```

```
SHADER: entropy-grid
IDENTITY: a grid of the photo scrambled inside a pointer radius by per-cell warp, a Voronoi ridge, and a Clifford kick.
KEEP VERBATIM: grid size / chaos / radius / invert; warped FBM from the cell id; clifford; influence gate; audio on chaos
MECHANISM INTERROGATION:
  tactic 4: chaos is one scalar; the grid it names should lock each cell to one sample as chaos rises.
  tactic 3: cellCenter is computed and then only used as an attractor origin.
ADD:
  1. cell-locked sample — mix the free UV toward the cell centre as chaos × influence rises; chaos 0 stays the continuous warp
  2. grid-boundary cracks — square-cell edges darken in the same influence region
FORBID: stained-glass leading, lantern, spring
A PACKING: ACES display RGBA (C is not read; display color was already stored)
```

```
SHADER: chroma-shift-grid
IDENTITY: a grid of lens-distorted cells whose chroma mode, speed, distortion, and chroma strength are the four sliders.
KEEP VERBATIM: three modes; animSpeed; distortStr lens; chromaStr; per-cell warp angle; Voronoi activity; spectral tint mix
MECHANISM INTERROGATION:
  tactic 1: the file is named chroma shift and then samples one UV. The shift is a per-channel offset of the offset it already builds.
  tactic 4: distortStr and chromaStr are global; the JSON already claims the pointer. A local gain on those two sliders is the same control, spatially.
ADD:
  1. Cauchy channel split — R/G/B offsets are the existing smoothOffset times n(λ) (§12.2F), chromaStr stays the amount
  2. pointer-local gain — lens k and chroma amount rise near the cursor; no new motif
FORBID: a second grid, neural web, audio (not claimed)
A PACKING: ACES display RGBA (C is not read; A was missing)
```

```
SHADER: hex-pulse
IDENTITY: a hex lattice whose cells pulse with a damped radial wave, edge glow, and chromatic fringe.
KEEP VERBATIM: base size / pulse strength / wave decay / speed; hex SDF; sin wave from the pointer; neighbour interference; bio glow; A = (excitation, edge, wave, alpha)
MECHANISM INTERROGATION:
  tactic 2: a pulse that only exists while the sin is high does not ring down; waveDecay already means how fast energy dies.
  tactic 6: A.r is the excitation this file stores. Reading it back from C is that same field.
  tactic 7: cos(phase) is the slope of the wave already evaluated.
ADD:
  1. ring-down memory — previous excitation persists, damped by the existing waveDecay
  2. wave-slope shade — the photo is lit by cos(phase), scaled by pulse strength
FORBID: full fluid solver, spring, IQ palette
A PACKING: raw (excitation, edge, wave, alpha) unchanged; ACES on writeTexture only
```

```
SHADER: ripple-blocks
IDENTITY: a grid of blocks that breathe with pointer and click interference, glow at the rim, and leave a trail.
KEEP VERBATIM: x grid scale, y domain-warp amount, z glow, w trail persistence (live shader roles, not a remap onto the JSON labels); cymatic interference; in-cell scale; audio bands
MECHANISM INTERROGATION:
  tactic 2: a shrunken block leaves a gutter; that gutter should carry the block's own light, not a hole.
  tactic 6: C is display color. The trail should be one held sample per cell, loaded exactly.
ADD:
  1. gutter bleed — out-of-cell pixels take a dim copy of that cell's color
  2. cell-held trail — exact load of C at the cell-centre pixel, max'd by trail persistence
FORBID: filtering sampler on C, Voronoi shatter, spring
A PACKING: ACES display RGBA (unchanged; C is that image)
```

```
SHADER: voronoi-shatter
IDENTITY: pointer-shattered Voronoi shards with gaps, rotation, click shock, and bass chatter.
KEEP VERBATIM: density / force / rotation / gaps; outward displace; shock from u.ripples; chatter; A = (m_dist, influence, rot/pi, alpha)
MECHANISM INTERROGATION:
  tactic 2: glass keeps spinning after the force drops; a shard also fissures across its face.
  tactic 6: C.b is the stored angle. One blend toward the new target is inertia, not a new solver.
ADD:
  1. angular inertia — coast the stored angle toward this frame's target
  2. internal fissure — a stable line across the shard along hash(m_id), width from the gap slider, strength from shatter force
FORBID: blast smear, neural pulses, a new spring
A PACKING: raw (m_dist, influence, coasted rot/pi, alpha) — same fields
```

```
SHADER: interactive-voronoi-web
IDENTITY: a Voronoi web over the photo, with pulses running along strands and nodes that fire.
KEEP VERBATIM: thickness / scale / glow / pulse speed; two-pass nearest sites; traveling pulse; synapse nodes; bass burst
MECHANISM INTERROGATION:
  tactic 2: an axon swells as the charge passes and goes dark in the refractory half-cycle.
  tactic 4: thickness is one scalar; the pulse already computed is its spatial version.
ADD:
  1. myelin swell — strand width tracks the existing pulse
  2. refractory dim — the negative half of pulseWave darkens the photo under the strand
FORBID: lantern, shatter cracks, a new palette
A PACKING: ACES display RGBA (unchanged; C is not read)
```

```
SHADER: voronoi-light
IDENTITY: a pointer lantern on Voronoi cells, tech lattice or glass refraction, with click photon rings.
KEEP VERBATIM: density / light radius / mode / pulse speed; both modes; spring already in extraBuffer[133..138]; ripple photons; border glow; C feedback of linear color
MECHANISM INTERROGATION:
  tactic 2: a real lantern is hotter in the core than a smoothstep; a facet facing the lamp is brighter.
  tactic 3: cellDelta is the in-cell direction and is only used as a refraction offset in glass mode.
ADD:
  1. inverse-square core — the existing radius gate stays; the core follows I/(d²+r0²) (§12.2F)
  2. facet facing — cellDelta dotted with the direction to the lantern shades both modes
FORBID: a second spring, neural web, shatter fissure
A PACKING: linear pre-ACES RGB + semantic alpha (C is that history; header previously claimed ACES in A)
```
