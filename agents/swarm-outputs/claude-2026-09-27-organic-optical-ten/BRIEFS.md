# BRIEFS — organic-optical-ten (2026-09-27)

Batch of 10 "organic / optical mid-high" generative shaders. Track A (1-6) is a first
upgrade pass. Track B (7-10) is a deliberate second pass on shaders that already carry
a genuine `Ideas:` line — user explicitly asked for these to be included rather than
skipped. See `docs/SHADER_UPGRADE_BATCH.md` for the live contract.

---

## Track A — first pass

```
SHADER: gen-abyssal-leviathan-scales
IDENTITY: hex-grid oily scale conveyor racing over a fissured plasma bed, thin-film spectral sheen, keel-ridged scales, click-triggered breach rings
KEEP VERBATIM: map() hex grid + sdScale, rowWave/conveyor timing, scalePalette() thin-film function, spring cursor in extraBuffer[133..138], click breach loop, camera fly-through, params x=Scale Density/y=Plasma Intensity/z=Conveyor Speed/w=Core Heat
ADD:
  1. Chromatic dispersion split on the thin-film sheen — offset R/G/B film phase by fresnel so it separates like real oil-slick at grazing angles.
  2. Scale "molt scar" from exact dataTextureC history — a scale recently crossed by a breach ring keeps a fading glowing crack for ~2s, via the existing per-cell hash.
  3. Held-flare micro-ridging — while mouse is held, boost keel/facet frequency in the already-computed repel region.
FORBID: a second spring/pointer system, a new palette family replacing scalePalette, a generic ripple import beyond the existing breach rings
A PACKING: display RGBA (already correct — no change)
```

```
SHADER: gen-bioluminescent-aether-pulsar
IDENTITY: raymarched twisted pulsar core smin-blended with a noisy accretion-disk torus, volumetric axial beam glow, orbiting camera, click shockwave shells
KEEP VERBATIM: map() core/disk SDF + smin blend, spin/audio-twisted core, disk noise via Accretion Density, beam glow accumulation, spring-damper camera orbit in extraBuffer[133..138], click shockwave loop, palette via Color Shift, exact C feedback, params mapping
ADD:
  1. Spin-locked twin jets — split the single symmetric beam term into two lobes above/below the disk plane with asymmetry scaled by Pulsar Spin Rate.
  2. Keplerian shear striping on the disk — warp the existing noise3(q_disk*4.0) sample with azimuthal shear proportional to radius x spin rate.
  3. Shockwave-triggered core flare — when the existing pulsarShock passes through the core radius, briefly spike the core's own noise/brightness term.
FORBID: a second spring/pointer mechanic, a new palette replacing the existing cosine palette
A PACKING: display RGBA (already correct — no change)
```

```
SHADER: gen-bioluminescent-aether-jellyfish-swarm
IDENTITY: domain-repeated swarm of bell+tentacle jellyfish creatures with aequorin subsurface glow, drifting through a volumetric aether void, hashed per-cell phase/audio pulse
KEEP VERBATIM: mapJellyfish() bell/hollow/core/tentacle smin chain, mapScene() domain repetition + drift/hash, raw (non-spring) mouse repulsion, volumetric empty-space noise pass, bioluminescentGlow() aequorin function, params x=Swarm Density/y=Propulsion Speed/z=Bioluminescence Intensity/w=Tentacle Length
ADD:
  1. Bell-contraction jet propulsion — pulse the bell radius per-cell using the hash/audio_propulsion already passed into mapJellyfish.
  2. Stinger-tip glow — brighten the tentacle capsule endpoints using the existing aequorin glow function.
  3. Startle flash on repulsion — when the existing repulse force exceeds a threshold, flash that jellyfish's bell with the aequorin palette.
FORBID: extraBuffer[133..138] spring (mouse is raw repulsion, not held/dragged), click/ripple shockwave system, IQ palette replacing aequorin glow
A PACKING: display RGBA (fix: switch C-read from filtering textureSampleLevel to exact textureLoad)
FLOOR FIX: writeDepthTexture is hardcoded vec4(0,0,0,0) — replace with real hit depth from raymarch distance.
```

```
SHADER: gen-bioreactor-bloom
IDENTITY: procedural fbm-warped cell-colony grid — pulsing nucleus/membrane cells, animated nutrient tendrils, layered pulsing bloom rings, toxicity poison-cloud at the cursor, spore sparkle
KEEP VERBATIM: fbm-warped grid/cell hashing, nucleus/membrane/pulse formulas, nutrientTendril()/pulseBloom() functions, poisonCloud mouse falloff, spore sparkle, params x=Cell Scale/y=Mitosis/z=Reactivity/w=Toxicity, bass_env in extraBuffer[0]
ADD:
  1. Mitosis split event — render a second nucleus blob when Mitosis+phase cross a threshold, offset along a hashed division axis.
  2. Toxicity necrosis creep — where poisonCloud overlaps a tendril, fade that tendril toward a necrotic tone.
  3. Reactivity-scaled bloom pulse — let bloomLayers ring speed/thickness respond to smoothBass x Reactivity.
FORBID: extraBuffer[133..138] spring, click/ripple shockwave system, raymarched SDF motif
A PACKING: display RGBA — FIX: HEAD reads C as color (prev.rgb) but writes A as raw fields (nucleus, membrane, tendrils, bloomLayers); switch A to display color to match the C-read.
FLOOR FIX: exact textureLoad instead of filtering sample; real semantic alpha instead of vec4(color,1.0); real relief depth instead of hardcoded zero; simplify the "regex auditor" indirection to a direct read (all 4 params are genuinely used, this is not a real bypass).
```

```
SHADER: gen-celestial-weave
IDENTITY: procedural interference-lattice weave of glowing fbm-warped fiber threads with knot highlights, overlaid with a hashed twinkling starfield and stochastic constellation lines
KEEP VERBATIM: fbm domain-warp + twisted weft/warp sine lattice, fiber/knot thresholds, star grid hash/twinkle/starGlow(), constellation neighbor-search + sdSegment lines, palette() cosine star hue, params x=Weave Scale/y=Twist/z=Shimmer/w=Void Depth, bass_env
ADD:
  1. Shimmer-driven traveling thread glint — a moving highlight along each thread using the already-computed weft/warpWave sine value as position-along-thread.
  2. Void Depth star parallax — per-star hashed depth makes closer stars bigger/brighter and drift slightly faster.
  3. Constellation pulse-travel — a light pulse travels along each drawn link segment, timed to smoothBass.
FORBID: extraBuffer[133..138] spring, click/ripple shockwave system, raymarched SDF geometry; do not tag "mouse-driven" in JSON.
A PACKING: display RGBA — FIX: A currently writes raw fields (fiber, knot, starGlowVal+constellation, 1.0), switch to display color to match the C-read.
FLOOR FIX: exact textureLoad instead of filtering sample; real semantic alpha instead of vec4(color,1.0); real relief depth instead of hardcoded zero.
```

```
SHADER: gen-chromatic-metamorphosis
IDENTITY: a single raymarched SDF primitive continuously cross-fading sphere->torus->box->capsule via a weighted smin chain, colored by an independent HSV field, under a GGX/Fresnel/AO/grain shading stack
KEEP VERBATIM: sceneSDF() 4-shape smin weight scheme (w0..w3/phase), independent HSV color field (normal+time+season), GGX/Fresnel/AO stack, mouse "catalyst" raw local-morph acceleration + rim/spec boost, params x=MorphSpeed/y=ColorSpeed/z=BlendRadius/w=LightIntensity
ADD:
  1. Catalyst "stutter" hold — when catalyst is high, bias the phase weights toward holding on the nearest integer phase before releasing.
  2. Temporal afterimage via dataTextureC (now wired) — blend a faint trailing echo of the previous frame's surface color behind the current hit.
  3. Per-phase seasonal color lean — bias the seasonal hue/season terms differently for box/capsule weights (w2/w3) than sphere/torus (w0/w1).
FORBID: extraBuffer[133..138] spring on the catalyst, click/ripple shockwave system, swapping the 4-primitive family for a different motif
A PACKING: display RGBA (new) — write vec4(col, semantic_alpha) into dataTextureA; read dataTextureC (declared but unused) as color history for idea #2.
FLOOR FIX (largest): dataTextureA is never written anywhere in the file — add the store. No ACES tonemap anywhere in the file — add acesToneMap() before final store. writeDepthTexture trailing component is 1.0, should be 0.0 to match convention. Header is non-canonical — rewrite to the canonical 7-line banner with Category/Upgraded/Ideas/A packing lines.
```

---

## Track B — second pass (existing Ideas kept verbatim, new ideas appended)

```
SHADER: gen-aetherial-plasma-loom
IDENTITY: a raymarched, twisting ribbon "loom" pinched into bright knots by a shuttle, twisted around the mouse point
KEEP VERBATIM: map() ring-ribbon SDF, 60-step density-integration raymarch, raw (non-sprung) mouse twist center, existing idea "alternating heddle lanes" (heddle sin lift), existing idea "plasma shuttle necking" (shuttle_phase/neck), params x=Density/y=Flow Speed/z=Twist/w=Core Brightness, palette()/weave_color, depth from first_depth
ADD (appended to existing Ideas):
  1. Warp thread-memory ghosting — add a genuine exact textureLoad of dataTextureC (currently declared but dead) and blend a small fraction into density/color for a faint persistent afterglow. This is a real bug fix (JSON falsely claims temporal-feedback today) framed as the shader's own idea.
  2. Weft-catch spark — a small local brightness spike where heddle lift and shuttle pinch phase coincide.
FORBID: spring-damper cursor (mouse is deliberately un-sprung here), click ripples, palette replacement
A PACKING: unchanged — ACES display RGBA in dataTextureA; dataTextureC now genuinely, exactly read.
JSON FIX: de-duplicate repeated top-level keys (updatedParams, supportsDepth, supportsDof, updated, features each appear twice) in shader_definitions/generative/gen-aetherial-plasma-loom.json.
HEADER: Upgraded: 2026-09-27. Ideas: alternating heddle lanes; plasma shuttle necking; warp thread-memory ghosting from exact C history; weft-catch spark where heddle lift meets shuttle pinch
```

```
SHADER: gen-bioluminescent-reaction-diffusion
IDENTITY: a true two-species Gray-Scott reaction-diffusion field rendered as cyan/violet bioluminescence, single-pass 9-tap Laplacian read of full previous state from dataTextureC
KEEP VERBATIM: 9-tap Moore-neighborhood Laplacian via loadStateClamped, single-pass (not ping-pong), Gray-Scott reaction a*b*b, feed/kill drift with luma+bass/mids, mouse directly seeds B species, existing idea "luciferin quench" (luciferinAge), existing idea "excitation flash on advancing B fronts", state packing (finalA, finalB, luciferinAge, 1) raw in A, spectral-bin shimmer, params unchanged
ADD (appended to existing Ideas):
  1. Pointer wake resets local luciferin-age near the mouse seed for an unquenched-bright glow trail that fades over several seconds.
  2. Quorum-sensing ignition flash — using the already-loaded 8-neighbor Laplacian samples, detect local B-concentration maxima and add a brief luciferinAge-gated supralinear flash.
FORBID: ping-pong buffers, a 5th state channel/repacking A, particle sparkle unrelated to the RD field, spring cursor, palette replacement
A PACKING: unchanged — raw (A, B, luciferinAge, 1) in dataTextureA, never tone-mapped.
HEADER: Upgraded: 2026-09-27. Ideas: luciferin quench from stored B-age; excitation flash on advancing B fronts; pointer wake resets local luciferin-age for an unquenched glow trail; quorum-sensing ignition flash at local B concentration maxima
```

```
SHADER: gen-celestial-quantum-glass-dragonfly
IDENTITY: a raymarched glass dragonfly (smin'd SDF body, IFS-folded fractal wing venation) hovering over volumetric plasma-storm fog, flown by a spring-tethered cursor
KEEP VERBATIM: mapBody/mapWings SDFs, spring-damper mouse in extraBuffer[133..138], existing idea "Cauchy thin-film wing iridescence", existing idea "quantum glass caustic core & photon emission", existing idea "acoustic wing-tip vortex trails", exact textureLoad(dataTextureC) 6% color trail, params unchanged, semantic alpha, depth from raymarch t
ADD (appended to existing Ideas):
  1. Velocity-banked flight roll — feed the spring's already-computed mouseVel into a small extra scene roll/tilt so the dragonfly banks into turns.
  2. Vortex-synced wingtip flutter — feed the fog loop's existing vortexWave phase into mapWings' trailing-edge z-offset, gated by Wing Frequency and treble.
FORBID: replacing the spring, unrelated creature parts, palette replacement, dropping the existing C-blend trail
A PACKING: unchanged — display RGBA.
HEADER FIX: header is missing Upgraded: entirely — add "Upgraded: 2026-09-27". JSON features missing "upgraded-rgba" despite ACES+ideas being real — add it.
HEADER: Ideas: Cauchy thin-film wing iridescence, quantum glass caustic core & photon emission, acoustic wing-tip vortex trails; velocity-banked flight roll from the spring's own momentum; vortex-synced wingtip flutter in the wing SDF
```

```
SHADER: gen-chromatic-oracle-jelly
IDENTITY: a 2D grid-cell swarm of drifting jellyfish with pulse-swim bells, pointer-tracking eyes, tentacle fringe, an oracle sigil glyph, and click ripples
KEEP VERBATIM: grid-cell tiling, existing idea "pulse-swim contraction with thrust/coast surge", existing idea "pupils track the pointer and blink on seeded schedules", tentacle fringe, oracle sigil glyph, deep bell glow ring, drag repulsion mouse mechanic, click ripple rings (u.ripples[]) currently decorative, exact-UV dataTextureC historyLoadUV blend, params unchanged
ADD (appended to existing Ideas):
  1. Tentacle-anchored luminous wake — a second, tentacle-phase-offset sample of the existing historyLoadUV mechanism, screened additively into the tentacle term.
  2. Click-triggered startle contraction — when a ripple is fresh and near a cell, briefly spike that cell's contraction value.
  3. (optional) Audio-linked pupil dilation from plasmaBuffer bass.
FORBID: new grid/creature type, spring-damper for the drag point, ripples becoming geometry-displacing shockwaves beyond the recoil beat
A PACKING: unchanged — ACES display RGBA.
HEADER: Ideas: pulse-swim contraction with thrust/coast surge; pupils track the pointer and blink on seeded schedules; tentacle-anchored luminous wake from a second history sample; click-triggered startle contraction spike
```
