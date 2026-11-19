# Idea Cards — Grok (zoom / weave ten, 2026-11-19)

Written before the WGSL edits. Ten shaders the user listed by size. Each card adds **two** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or new IQ palette.

Every file already carries an earlier idea pass. This pass deepens that mechanism.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Chroma delay line (§12.2B) and dropout bursts (§12.2B) are `signal-noise` only.
- No other §12.2 row is newly applied.

`gen-percolation-threshold` and `sacred-geometry-torus` still paste the binding header. Migrating them to `#include "_prelude.wgsl"` is infrastructure. It is not an idea and does not by itself bump `Upgraded:`. The idea edits do.

`gen-celestial-weave` writes the bass envelope to `extraBuffer[0]` (engine-reserved). Moving that scalar to `extraBuffer[133]` is a remap, not an idea.

```
SHADER: liquid-zoom
IDENTITY: an endless zoom-through of the plate — four phase-offset parallax layers, faster near the camera, with fog, click travel-bursts, and a temporal streak.
KEEP VERBATIM: four-layer stack; ping-pong wrap; near / far speed, parallax strength, fog density; per-layer FFT pair; bounded click pulses; held pointer boost; in-place max streak; ACES display.
MECHANISM INTERROGATION:
  tactic 2: a zoom tunnel smears along the ray. The streak maxes the previous color in place, so it blooms instead of stretching toward the zoom center.
  tactic 3: chroma is one scalar. The split does not grow off the axis, which is where a zoom's dispersion actually shows.
  tactic 6: A is display RGBA. Exact C loads along the ray are the same packing.
ADD:
  1. Radial zoom smear — three exact C taps stepped toward the zoom center, maxed with the existing in-place streak. Length follows near speed and parallax.
  2. Off-axis chromatic growth — the existing radial RGB split strengthens with distance from the zoom center inside sampleLayer.
FORBID: a new spring, a new expanding ring, an IQ palette
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: liquid-jelly
IDENTITY: a wobbly gel — Kelvin-Voigt modes, a finite-speed shear wave, jiggle streaks, a soliton ridge, and a sprung pointer tether.
KEEP VERBATIM: viscoelasticModalFlow; shear / lobe / soliton / tether / arrival-gated click wave; jiggle smear; candy palette keyed to thickness; damping, elasticity, wobble, scatter tint; spring in extraBuffer[133..138]; display RGBA history.
MECHANISM INTERROGATION:
  tactic 2: a gel is nearly incompressible, so a press piles it up instead of only sliding the surface. A thin ridge pinches into beads.
  tactic 3: tetherForce is the press. Thickness today is only the length of the displacement, so inward and outward presses look the same.
  tactic 6: C stays display color plus the alpha thickness the slope already reads. No new field.
ADD:
  1. Poisson bulge — inward tether thickens the gel, outward tether thins it. Thickness still feeds the existing candy and absorption.
  2. Capillary pinch — the existing soliton ridge is beaded along its length, and the bead peaks catch a small highlight.
FORBID: a new solver, a second palette, Gray-Scott, a new spring
A PACKING: ACES display RGBA (unchanged). Alpha remains the thickness the slope reads.
```

```
SHADER: gen-celestial-weave
IDENTITY: a woven night-sky cloth — warp and weft, knots, stars, constellation links, a gravity lens at the pointer.
KEEP VERBATIM: fbm warp; weave scale / twist / shimmer / void depth; thread glint on the phase; star parallax; bass-timed constellation pulses; dust motes; gravity lens; ACES display.
MECHANISM INTERROGATION:
  tactic 2: a weave has an over and an under. Both threads are currently the same purple, so the cloth reads as a crosshatch.
  tactic 3: fiber and knot are coverage. Stars are added after the cloth and never go behind it.
  tactic 6: A stays display RGBA. The bass envelope moves off extraBuffer[0] onto [133]; that remap is not an idea.
ADD:
  1. Over-under shed — the brighter of |weft| and |warp| is the top thread (warm weft, cool warp) and the lower one stays the dimmer purple.
  2. Cloth occultation — fibers and knots dim the stars and the constellation links they cover.
FORBID: a new palette function, a spring, a second star field
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-cycloid-bloom
IDENTITY: a floral mandala of nested hypotrochoids, one counter-spinning epicycloid, cusp sparks, and a small rolling generator circle.
KEEP VERBATIM: hypotrochoid / epicycloid; coarse-plus-refine search; five layers; spin / petal multiplier / glow width / persistence; veins, stamen, crossings, cusp sparks, rolling circle; mouse pull; click waves; ACES display feedback.
MECHANISM INTERROGATION:
  tactic 2: a hypotrochoid is a point on a circle rolling inside a fixed circle. The fixed circle is not drawn, and the generator circle has no contact point.
  tactic 3: rollCenter and rollR are already the generator. The contact is the inner point of that circle and is thrown away.
  tactic 6: A stays ACES display. No new search loop.
ADD:
  1. Fixed circle — one faint ring at the outer hypotrochoid's fixed radius (R scaled by the outer layer).
  2. Contact bead — a bright knot on the existing rolling circle, on the side toward the origin.
FORBID: another petal search, a new palette, a spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-luminous-fluid-chladni-resonator
IDENTITY: a Chladni plate under a luminous fluid — nodal sand, Faraday ripples on the antinodes, sand streaming down |c|, a wet meniscus glint.
KEEP VERBATIM: chladni_multi modes N and M; curl fluidity; click flexural waves; sandGrains; Faraday lattice; gradient flow; meniscus spec; blackbody mix; glow slider.
MECHANISM INTERROGATION:
  tactic 2: sand piles at nodal crossings, where the plate is still and the slope is also flat. A free plate edge is an antinode, so sand clears there.
  tactic 3: c0 and gradLen are already computed for the flow and the glint. Their joint zero is the crossing and is unused.
  tactic 6: A stays ACES display. The gradient is not a new field.
ADD:
  1. Crossing piles — sand and a pale highlight thicken where |c| and |grad| are both small.
  2. Free-edge clearance — sand fades out in a margin at the frame, where a free plate cannot hold a node.
FORBID: a new mode family, thin-film, a spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: mouse-electromagnetic-aurora
IDENTITY: the pointer is a moving charge — electric field lines, magnetic hue, aurora curtains hung from |B|, click counter-charges anchored in place.
KEEP VERBATIM: Coulomb E; Biot-Savart-style B from pointer velocity; LIC filings; curtains coloured by the sign of B; counter-charges at the click; velocity state in A texels (0,0) and (1,0); charge / field vis / distortion / color rotation.
MECHANISM INTERROGATION:
  tactic 2: curtains in a real EM field drift with E×B, not only fall. A charge diagram also draws the equipotentials, which are rings, not lines.
  tactic 3: fieldDir and totalB are already computed. The curtain probe steps straight down and ignores them.
  tactic 6: pointer state packing unchanged. No new extraBuffer.
ADD:
  1. E×B shear — each curtain probe steps downward and sideways along B × direction-of-E, so the curtain leans with the drift.
  2. Coulomb equipotentials — faint log-spaced rings around the pointer charge, static in radius (a slow phase, not an expanding front).
FORBID: a new charge solver, an expanding click ring, a new palette
A PACKING: ACES display RGBA; texel (0,0) = (mouse.xy, time, 1), texel (1,0) = (velocity.xy, 0, 1). Unchanged.
```

```
SHADER: gen-luminescent-singularity-loom
IDENTITY: a raymarched thread lattice folded around a black-hole core, with gravitational light bending, shuttle beads, and a bass pluck.
KEEP VERBATIM: threadField fold; smooth-min with the core sphere; lensed march; shuttle beads; threadPluck; thread density / loom speed / glow / color shift; existing palette.
MECHANISM INTERROGATION:
  tactic 2: a loom opens a shed — alternate threads lift so the shuttle can pass. These cylinders stay coplanar.
  tactic 3: threadPluck already swells the radius. The fat antinode is not given its own glint.
  tactic 6: C is unread. A stays display RGBA.
ADD:
  1. Heddle shed — alternate threads offset in Y by a sine of loom speed, so a shed opens and closes through the same fold.
  2. Pluck antinode glint — where the existing pluck swells the thread, a cool highlight sits on that fat segment.
FORBID: a new primitive, step-count AO, a second palette, a spring
A PACKING: ACES+gamma display RGBA (unchanged). C unread.
```

```
SHADER: gen-percolation-threshold
IDENTITY: site percolation near p_c — occupied sites, union-find labels, a spanning cluster that conducts, finite clusters that fade.
KEEP VERBATIM: 80×60 lattice in A; epoch stamp; touch-left / touch-right; p from threshold shift and bass; lattice zoom, bloom, grain; conduction pulses; red bonds; mass fade; opalescence. Prelude migration is not an idea.
MECHANISM INTERROGATION:
  tactic 2: the lattice is sites and bonds. The picture fills the whole cell, so the bond you already test is invisible.
  tactic 3: the label is the root's flat index. The root site is never marked.
  tactic 6: sim packing unchanged. Display texels outside the lattice stay display RGBA.
ADD:
  1. Lattice bonds — a bar across the cell edge toward each occupied neighbor already tested.
  2. Cluster root — the site whose index equals the cluster label glows as the union-find seed.
FORBID: a new lattice, a spring, an IQ palette
A PACKING: lattice state in texels [0..79]×[0..59] = (label, epoch, touchL, touchR); ACES display RGBA elsewhere. Unchanged.
```

```
SHADER: sacred-geometry-torus
IDENTITY: a disc of torus-knot strands, phi-harmonic nodes, and a Fibonacci dot lattice, in gold, emerald, and sapphire.
KEEP VERBATIM: five knot taps; phi node loop; phyllotaxis; knots / spin / glow / phi layers; gold-emerald-sapphire mix; IQ strand hue at 0.35; crossing bloom; 3% trail; disc cutoff at r>0.95. Prelude migration is not an idea.
MECHANISM INTERROGATION:
  tactic 2: the emerald "sacred ring" uses smoothstep(0.55, 0.75, abs(r-0.5)), and abs(r-0.5) never reaches 0.55 inside the disc, so the ring is absent.
  tactic 3: the five taps are summed. The brightest tap and the runner-up — the over and the under — are thrown away.
  tactic 6: A stores (pattern, ring, lattice, alpha) while the trail reads C as color. That is a packing lie. Store the pre-ACES color the trail actually mixes, and read it with textureLoad.
ADD:
  1. Sacred ring restored — a thin emerald band on r≈0.5 (the mouse shift kept) with a round centerline highlight.
  2. Strand over-under — the winning tap stays bright and the runner-up recedes where the two taps separate.
FORBID: a new lattice, a spring, replacing the gold with a different palette
A PACKING: pre-ACES display RGB + alpha (the trail mixes before ACES). ACES on writeTexture only. Was (pattern, ring, lattice, alpha) while C was read as color.
```

```
SHADER: signal-noise
IDENTITY: the plate as a noisy composite signal — VHS head-switch, block artifacts, chroma smear, YUV noise, a sprung cursor.
KEEP VERBATIM: fbm noise; vhsHeadSwitch; dctBlockArtifact; luma-shouldered noise; quantisation staircase; dot crawl; smear; spring in extraBuffer[133..138]; VHS / artifact / smear / chroma sliders; exact C history.
MECHANISM INTERROGATION:
  tactic 2: composite chroma lags luma horizontally. The file splits RGB along a noise angle, which is not a delay line. Dropouts are line bursts with a tail; the head-switch is only the bottom band.
  tactic 5: a tape deck's two named artifacts not yet present are the chroma delay and the dropout.
  tactic 6: A stays display color. The delay is one extra sample of the picture, not a new history.
ADD:
  1. Chroma delay line — §12.2B: U and V from a sample a few pixels to the left, luma kept full-res. Amount is the existing chroma slider.
  2. Dropout burst — §12.2B: a rare line-wide streak with an exponential tail from the left, gated by VHS intensity. The head-switch band stays.
FORBID: a second spring, thin-film, a new tear system
A PACKING: ACES display RGBA (unchanged)
```
