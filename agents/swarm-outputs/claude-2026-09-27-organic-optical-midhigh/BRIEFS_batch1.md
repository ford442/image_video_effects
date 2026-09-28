# Idea Cards — batch 1 of 2 (organic/optical mid-high ten)

## gen-bioluminescent-neural-lattice
```
IDENTITY: raymarched voronoi-edge "neural" lattice the camera flies through, cosine-palette glow, mouse warps nearby space
KEEP VERBATIM: dual-voronoi SDF lattice (voronoi_edges + smin), camera flythrough, mouse spatial-attraction warp, 4 params (synapse_density, pulse_speed, glow_intensity, color_shift) and their roles
ADD:
  1. Bass-triggered synapse firing — each lattice cell gets a stable per-cell phase offset (new voronoi_edges_id helper); the phase sweeps with raymarch depth so a firing event reads as a narrow bright flash racing along the tunnel, not a uniform blink. Bass both speeds up firing and brightens it.
  2. Bioluminescent afterglow — dataTextureA/C were a dead binding (fake audio was read from C instead); now real temporal history lets recently-lit regions keep a decaying glow via a max(current, decayed-history) blend, tied to glow_intensity.
  3. Treble shimmer on the closest-approach ambient glow term — a cheap third audio band usage distinct from bass (firing) and mids (ambient hum).
FORBID: spring cursor, click ripples (this shader has no click/ripple mechanic), IQ palette swap, holographic overlay
A PACKING: display RGBA (afterglow-blended max), same value in writeTexture and dataTextureA
PLUMBING FIXED: real plasmaBuffer[0] audio (was self-sampling dataTextureC as fake audio); dataTextureA wired (was dead); writeDepthTexture now writes real raymarch depth (was never called)
```

## gen-biomechanical-hive
```
IDENTITY: infinite raymarched hex-prism hive lattice, fbm organic breathing walls, emissive per-cell core, bass/mid audio, mouse orbit camera
KEEP VERBATIM: hex-prism domain repetition (map()), core-vs-wall material split, breathing/pulse mechanic, 4 params (cell_density, pulse_speed, biomass, hue_shift) and roles, orbit camera (yaw/pitch from mouse)
ADD:
  1. Growth-memory afterglow — dataTextureA/C were declared but never written/read (dead feedback loop); now a strong bass pulse leaves a decaying afterglow trail (max blend against decayed raw-HDR history), native to the file's own "pulsing-growth" feature tag.
  2. Biomass-driven vein growth — a finer, higher-frequency fbm bump layer scaled by the `biomass` param, distinct from the existing macro `displacement` term, so raising Biomass visibly grows surface veins rather than only deepening big folds.
  3. Treble-triggered nerve flicker — sparse cell-locked flecks of light on the chitin walls keyed to treble (previously unused band), reading as a nervous system firing under the shell.
FORBID: spring/ripple overlay (file has no pointer-click mechanic to hang it on), IQ palette, replacing the hex-prism lattice with a different primitive
A PACKING: raw HDR display RGBA history (pre-ACES), ACES applied only on writeTexture — matches the "A/C = raw HDR" convention used elsewhere in the catalog
PLUMBING FIXED: dataTextureA/C wired for the first time (previously dead — no write, no read)
```

## gen-celestial-aether-seraphim-wings
```
IDENTITY: raymarched KIFS feather-tube fractal wings, damped-oscillator audio-driven flap, Wolfram lift/stall physics model keyed to mouse-Y angle of attack, thin-film iridescent palette
KEEP VERBATIM: KIFS fold loop (5 iterations), flap oscillator, lift/stall physics (C_L = 2πα, stall smoothstep), 4 params (fractal_spread, feather_thickness, iridescence_hue, ascent_speed) and roles
ADD:
  1. Stall-vortex shedding — reuses the exact same alphaAOA/stall threshold as the shading pass, but now perturbs the fold geometry itself (a per-iteration swirl phase) once past stall, so the wing visibly breaks up into turbulence instead of only tinting red/orange.
  2. Lift-direction hue shift — the iridescence hue now biases warm/cool by the sign of the angle of attack (climbing vs descending), scaled by the lift coefficient magnitude — ties the palette to the same Wolfram model that already drives brightness, deepening the existing physics idea rather than adding an unrelated one.
FORBID: unrelated overlay motifs (springs, ripples — this shader has no click mechanic); do not touch the KIFS fold count or feather SDF family
A PACKING: display RGBA (unchanged — same value in writeTexture and dataTextureA)
PLUMBING FIXED: dataTextureC read switched from filtering textureSampleLevel to exact textureLoad (binding-contract violation on rgba32float history); writeDepthTexture now writes real raymarch depth (was hardcoded to vec4(0) despite supportsDepth: true)
```

## gen-crystalline-mandala-bloom
```
IDENTITY: 2D kaleidoscope fold sampling the source image, procedural crystal petal SDF rings, bass-pulsing rings, click-ripple blooms — already fully plumbed (real audio, mouse recenter + ripples, correct A/C packing)
KEEP VERBATIM: kaleidoscope-on-image mechanic, petal/ring SDF layer, 4 params (symmetry_segments, facet_zoom, bloom_strength, hue_rotation) and roles, ripple bloom mechanic
ADD:
  1. Per-facet refraction offset — each of the `segments` kaleidoscope wedges now gets its own small, stable static offset (hash keyed on segment index), so every facet samples a very slightly different angle of the source image, like a real cut gem where each facet bends light differently. Previously every segment sampled the identical folded coordinate.
  2. Treble facet sparkle — a new prismatic glint locked to the petal SDF edge (where a real facet would catch the light) driven by treble, distinct from both the existing generic screen-space star field and the bass-driven concentric rings.
FORBID: replacing the kaleidoscope-on-image mechanic, spring cursor (mouse already just recenters — no drag physics needed), IQ palette swap
A PACKING: raw HDR display RGBA history (unchanged)
PLUMBING FIXED: none needed — this file was already fully plumbed (real audio, correct A/C, real depth, ripples)
```

## gen-cosmic-slime-mold
```
IDENTITY: procedural (non-agent) vein SDF network with growth-pulse timing, mouse-feeding tendrils, real audio, correct A/C packing
KEEP VERBATIM: 6-seed vein SDF structure (veinStructure), growth-pulse timing (growthPhase/growthPulse), mouse-feeding mechanic, 4 params (intensity, speed, scale, color_shift) and roles
ADD:
  1. Persistent growth memory — extraBuffer[133..138] was completely unused (greenfield); added a single-writer accumulator at (0,0) that rises while the pointer feeds the colony and decays slowly otherwise (0.997 decay/frame), so the colony's baseline size actually persists across a session instead of resetting the instant the pointer lifts.
  2. Mature-colony core glow — once growth memory crosses a threshold, thick vein trunks pick up a warm established-colony glow distinct from the cool neon vein palette, giving a visible payoff to sustained feeding.
FORBID: replacing the procedural vein SDF with a real agent simulation (out of scope — that's a rewrite, not an upgrade), spring cursor (mouse already has a native feeding mechanic)
A PACKING: exact HDR temporal history (unchanged)
PLUMBING FIXED: removed a duplicate/shadowed top-level "params" JSON key (hyphenated "color-shift", dead — the second "params" array with "color_shift" was the one actually in effect); no WGSL plumbing gaps found
```
