# Split-Gen Eight — Idea Cards (written before any WGSL edit, 2026-09-28)

Line numbers are HEAD line numbers.

---

```
SHADER: morphogenic-resonance   (generative, 234 lines)
IDENTITY: a grid of rotating polygons that morph sinusoidally into noisy veined blobs; edge glow, treble
          discharge, pointer warp, advected trails.
KEEP VERBATIM: sdPolygon / sdOrganic / morphField structure; grid scale from geoBias; slider roles
          (x morph speed, y geometric bias, z ripple intensity, w colour shift); ring front; trails from C.
ADD:
  1. Travelling morph front (morphogen wave) — each cell's morph phase lags by the distance of its
     centre from the pointer, so geo→bio change sweeps outward as a wave. HEAD: every cell morphs in
     lockstep off one global sin(t) (L90, L200). formColor must use the per-cell phase, so morphField
     returns interp as well as distance.
  2. Crystalline facet spokes — centre-to-vertex bevel lines inside each polygon (the polygon sector
     angle already exists in sdPolygon), bright in the geometric state and fading as the cell turns organic.
  3. (optional) Veins conduct the discharge — treble discharge follows the vein fbm band inside organic
     cells instead of uniform edge noise.
FORBID: springs, click ripples, IQ palette, mitosis (saturated), neighbour fusion bridges (taken).
A PACKING: ACES display RGBA (HEAD; C read as colour) — keep.
```

---

```
SHADER: aurora-borealis-loom   (generative, 243 lines)
IDENTITY: five hued aurora curtains woven as fabric: weft/warp thread overlay, ion beads, ion streaks, stars.
KEEP VERBATIM: auroraCurtain, weftPattern / warpPattern, ionizationNodes, slider roles (x weave density,
          y hue speed, z ionization, w curtain flow), mouse pull, trails.
ADD:
  1. Fell line + reed beat-up — the woven cloth ends at a fell line that advances down the frame with
     curtainFlow (wrapping). Past the fell line only bare warp threads glow (no weft yet). At the line
     the reed "beats up" the newest pick: a bright horizontal compaction band, stronger on bass.
  2. Slub yarn — thread thickness varies along each thread (1-D noise per row/column), and aurora light
     pools in the thick slubs, so the weave reads as hand-spun yarn instead of a perfect grid.
  3. Pulsating aurora patches — soft cellular patches of the curtain blink on quasi-periodic 3–12 s
     periods (each patch its own phase), the real "pulsating aurora" behaviour.
FORBID: over-under interlacing, shuttle (both saturated in loom files); curtain folds, altitude
        emission layers, ray striations, lower-border fringe (saturated in aurora files); springs.
A PACKING: ACES display RGBA (HEAD) — keep.
```

---

```
SHADER: volumetric-cloud-nebula   (generative, 251 lines)
IDENTITY: an fbm nebula raymarched from an orbiting camera; cosine emission palette; Beer-Lambert alpha;
          twinkling stars behind.
KEEP VERBATIM: raymarchVolumetric integration, cloudDensity, nebulaColor, orbit camera, slider roles
          (x density, y colour shift, z camera distance, w extinction — which also drives flowSpeed at HEAD;
          keep that coupling and note it).
ADD:
  1. Light-echo shell — a periodic stateless central flash (every ~8 s, bass-brightened) whose light
     expands outward as a spherical shell of radius c·age. Gas the shell passes through lights up with
     a white-blue rim, the V838 Mon light echo.
  2. Absorbing dense cores — the declared-but-unused SIGMA_A_NEBULA finally acts: per-step emission is
     scaled by single-scatter albedo σs/(σs+σa·density-weight), so the thickest knots sink dark inside
     bright envelopes.
  3. (optional) Warp-flight star streaks — background stars elongate along the camera's orbital velocity
     direction (the "warp-flight" camera already moves them).
FLOOR BUG (fix; document the default-look change): `temporal = finalCol + prev*(0.82+0.05*flow)` has
  a steady state of about 6.7× finalCol, clamped to 5.5 and written to writeTexture without a tone map,
  so HEAD is blown out. Use bounded mix trails and put ACES on display.
FORBID: dust lanes, reddening, ionizing star, globules, ionization fronts (all in gen_kimi_nebula);
        HG forward scatter (taken).
A PACKING: display RGBA (ACES) — C read as colour history.
```

---

```
SHADER: gen-image-pyro   (generative, 245 lines)
IDENTITY: fireworks launched from bright parts of the loaded photo; sparks and embers coloured by the
          photo; gravity; trails; pointer barrage when held.
KEEP VERBATIM: mortar loop (7 launches), image-sampled spark colours, embers, hue-twist behaviour,
          updatedParams roles (Burst Power, Ignition, Trail Length, Hue Twist −1..1), starfield, vignette.
ADD:
  1. Drag-damped spark flight — closed-form linear-drag ballistics
     p = o + v·(1−e^{−kt})/k − g·(t/k − (1−e^{−kt})/k²): sparks decelerate, then droop into the
     chrysanthemum shape instead of a pure parabola.
  2. Shell types per mortar — a per-cycle hash picks peony (the current look, the majority), willow (gold,
     long-lived, high drag, drooping) or ring (sparks on a tilted planar ellipse).
  3. (optional) Crossette split — some peony sparks split into four at mid-life, each child flying off at
     ±90°.
FLOOR BUGS (fix, document; not ideas):
  - Upside down: pixel y-down is used as y-up, so shells "ascend" downward and gravity pulls up. Flip uv.y.
  - Pointer treated as pixels (`mouse - res*0.5`); zoom_config.yz is 0..1 UV. Map it into the same uv space.
  - The image is sampled 2× zoomed (`uv*0.5+0.5` with uv∈[−0.5,0.5] on the short axis). Map to the full frame.
  - The core flash (`col += probeCol*core`) lights the whole screen uniformly. Give it distance falloff from
    the burst centre.
  - Trail Length is inverted (`mix(0.94,0.88,trail)`). Flip it; the default 0.5 keeps decay 0.91.
  - An undocumented, never-read dataTextureB write: drop it.
  - Depth is written as 0. Write a truthful depth (sparks/glow forward).
FORBID: burst-lit smoke / buoyancy (gen-fireworks-smoke-bloom), springs, ripples.
A PACKING: ACES display RGBA; alpha semantic (not 1.0).
```

---

```
SHADER: film-gate-weave   (retro-glitch, 152 lines; Composer overlay stamp)
IDENTITY: a 35 mm projection with frame-quantized vertical gate weave, dust, persistent vertical scratches,
          hair, splice tape, flicker, lens-breathe chroma.
KEEP VERBATIM: 24 fps frameId quantization, weave/regJitter/intermittent formula, slider roles
          (x weave, y dust, z scratches, w flicker), dust/hair/splice/click flash, A packing.
ADD:
  1. Frame-line reveal — when weave pushes sampleUV.y outside [0,1], show the black frame bar (with a
     thin soft edge) and then the neighbouring frame (wrap), instead of the clamp smear at HEAD.
  2. Wandering scratches — the persistent scratch in C.g is loaded from a coord drifted ±1 px in x
     per frame (hashed per frameId), so scratches meander across frames the way a real base scratch
     does, instead of standing on a fixed column.
  3. Reel-change cue dots — a cigarette-burn circle (dark ring with a bright pitted centre) in the top
     right for ~4 frames (24 fps), on a long period (~11 s); visibility scales with the dust slider.
FORBID: new springs, per-channel grain / continuous hairline (analog-film-degrade), ripple rings.
A PACKING: (rgb.r, scratch, 0, alpha) — C.g is the scratch field. Keep.
```

---

```
SHADER: scanline-drift   (retro-glitch, 160 lines; Composer stamp)
IDENTITY: horizontal strips each drifting sideways with RGB split; a pointer band adds jitter;
          click tears.
KEEP VERBATIM: stripId from lineHeight, sin drift + hash jitter, mouse band + mouse.x edge proximity,
          click tear loop, colour split, strip boundary darkening, slider roles.
ADD:
  1. Tape-stretch shear — over the lower ~30% of each strip the offset blends smoothly into the next
     strip's offset, so strips shear into one another like stretched tape instead of hard-stepping.
  2. H-sync porch at the wrap seam — where `fract(uv.x+offset)` wraps, show a dark horizontal-blanking
     porch a few px wide with a faint bright sync-tip sliver, which is what a displaced line really reveals.
  3. Drift-velocity smear — each strip smears horizontally along its own drift velocity (the analytic
     derivative of its sin offset): 3–4 taps, so fast strips blur and slow ones stay crisp.
FLOOR: remove the dead `plasmaBuffer[stripBin]` term (bins 1..8 read 0) and the "regional FFT flicker"
       header claim. Keep the treble flicker from plasmaBuffer[0].z.
FORBID: head-switch skew / dropout (vhs-tracking), vertical-hold blanking bar (static-reveal), new springs.
A PACKING: ACES display RGBA (HEAD) — keep.
```

---

```
SHADER: glass-brick-distortion   (distortion, 178 lines)
IDENTITY: a grid of glass bricks, each a plano-convex lens magnifying its brick centre; grout lines,
          Fresnel, Beer-Lambert tint, pointer clear zone, click ripple shocks.
KEEP VERBATIM: brick grid + drift, bCenter lens sampling, prismatic dispersion R/G/B offsets, grout,
          clear zone, slider roles (x brick size, y IOR, z chroma, w depth influence).
ADD:
  1. Flutes — the header promises "Architectural Fluted Lens Refraction" but the code has no flutes.
     Add vertical ribs (a sin profile across brickUV.x, ~5–7 per brick) to the lens offset, with a faint
     rib highlight, so each brick reads as ribbed architectural glass.
  2. Grout-edge mirror bevel — within a thin band inside the grout the surface normal tilts steeply:
     sample the image mirrored across the brick edge, darken it, and add a thin specular line (the rounded
     edge of a moulded glass block).
  3. (optional) Per-brick batch tint — each brick gets a slightly different green/blue glass tint and
     thickness (hash of brickId), as in real mixed-batch glass-block walls.
FORBID: new springs, iridescence, IQ palette.
A PACKING: ACES display RGBA (HEAD) — keep.
```

---

```
SHADER: paper-cutout   (interactive-mouse, 159 lines)
IDENTITY: the photo posterized by luma into stacked paper sheets; the pointer is a light casting shadows
          away from it; clicks emboss rings.
KEEP VERBATIM: luma quantization, 4-tap shadow march toward the light, colour normalization,
          click emboss, slider roles (x layers, y shadow dist, z softness, w separation), relief depth.
ADD:
  1. Height-weighted shadows — shadow strength scales with how many layers higher the occluder is
     (sample_quant − quantized_luma), so tall stacks throw darker shadows. HEAD uses a binary
     "higher than separation" test.
  2. Lit cut edge — at layer boundaries (quantized luma differs from a 1-px neighbour) the edge facing
     the light shows the paper's bright white cut core; the far side gets a thin dark rim.
  3. Hand-cut layer jitter — each paper layer is offset by a tiny per-layer hashed amount (≈1–2 px), so
     the stack reads as hand-cut and hand-placed rather than perfectly registered.
FLOOR: remove the dead `plasmaBuffer[layerBin]` voice (reads 0).
FORBID: paper fibre (saturated), springs, new ripples.
A PACKING: display RGBA (HEAD) — keep; add ACES only if HEAD's peak-limit is replaced.
```
