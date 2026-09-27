# Densest Multi-System Seven — Idea Cards (2026-09-27)

Each card was written by its agent before the WGSL edit; concatenated here by the coordinator.

---

# Idea Card — gen-resonant-quantum-obsidian-scarab-engine

```
SHADER: gen-resonant-quantum-obsidian-scarab-engine
IDENTITY (one sentence): a breathing cyan plasma torus core wrapped in a
  mirror-folded (KIFS) exoskeleton of black obsidian beads with hard white
  specular, violet quantum dust, and a faint feedback trail.
KEEP VERBATIM: map() (mouse-shifted sdTorus core, 4-fold KIFS with its
  in-place x/y "rotation" shear, smin 0.5, material ids 1/2); 100-step primary
  march; Lambert core + pow32 obsidian spec; held-mouse dust; 5% C feedback;
  fake-CA channel offset; ACES*1.2; lum alpha; depth = t/20; slider roles
  x=exoskeleton complexity (fold offset), y=plasma intensity,
  z=obsidian reflectivity, w=core pulse rate.
ADD (3 native ideas — each couples two subsystems already in the file):
  1. Elytra plate seams with a core-breath pulse — the KIFS shell is split into
     interlocking octant plates (great-circle seams in the final folded frame,
     per-plate obsidian tint); the seams are the "quantum circuitry" from the
     JSON description and light up with a wave that leaves the core at the same
     sin(time*rate) that breathes the torus, travelling outward through the
     plates. Fuses KIFS geometry + core pulse. (Plasma Intensity = brightness,
     Core Pulse Rate = wave speed.)
  2. Plasma mirror in the obsidian — reflect(rd,n) on exoskeleton hits is
     marched a short way against the core torus only; the cyan core appears as
     a Fresnel-weighted reflection in the black glass. Fuses core + obsidian;
     scaled by Obsidian Reflectivity x Plasma Intensity.
  3. Core corona leaking between plates — primary march integrates
     exp(-coreDist) * stepLength, so plasma light bleeds through the gaps of the
     exoskeleton and rims the torus silhouette on misses. Fuses the march +
     core field.
FORBID: spring cursor, click ripples (HEAD never used ripples), IQ palette,
  conchoidal fracture shells (gen-obsidian-echo-chamber), trailing membrane /
  buckle fractures (gen-resonant-quantum-obsidian-astro-manta), dragon iris or
  bismuth hopper ideas (batch siblings), a new creature or new fractal.
A PACKING: ACES display RGBA (HEAD, unchanged). C is read as colour history.
```

Audio: rides along only (bass already in pulse rate; mids in plasma).
All three ideas are visible with audio = 0.

Notes on HEAD bugs:
- KIFS "rotation" writes p.x then reads the new p.x for p.y (a shear, not a
  rotation). Kept verbatim: it IS the exoskeleton shape; fixing it would
  change the identity. The seam trap replicates it exactly so seams sit on
  the real surface.
- C feedback mixes ACES display back into HDR before ACES (5% weight). Stable
  (contracts), kept as HEAD's look; noted, not changed.
- No pow-negative-base, ripple.w, zero-C, or dead-mask issues found. New pow
  calls clamp bases with max(.,0).
- Dust is zero unless the mouse is held (zoom_config.w * 0.1) — HEAD behaviour,
  preserved.

---

# Idea Card — gen-resonant-quantum-plasma-dragon-eye

```
SHADER: gen-resonant-quantum-plasma-dragon-eye
IDENTITY (one sentence): a raymarched dragon eyeball inside a bioluminescent scale socket, vertical slit pupil
  holding a gold supernova, green/gold/abyss fibre iris ring, orbiting camera, mouse-look + gravitational lens,
  bass-dilated pupil, volumetric quantum-plasma haze.
KEEP VERBATIM: map() SDF family (eyeball sphere r=2, fibre ring at r=0.8 with Iris-Complexity polar fbm, slit
  ellipse 0.15+dil*0.4 / 0.6+dil*0.3, scale shell r=2.3 with fbm), mouse look-at rotation + lens (Aberration),
  camera orbit, pupil nova / iris ring / sclera veins / scale SSS shading, background plasma, 16-step volumetric
  plasma loop, CA tint, 4% C persistence, ACES*1.15. updatedParams byte-exact (Plasma Density, Iris Complexity,
  Pupil Sharpness, Aberration).
ADD (native ideas):
  1. Dilator-fibre stroma — the bare sclera cap between the slit and the fibre ring (HEAD painted it white with
     veins) becomes iris tissue: radial dilator fibres (count from Iris Complexity), gold pupillary zone -> green
     ciliary zone -> abyss root, and guanine iridophore flecks (reptile iris) that twinkle with view angle.
     Why: HEAD's iris is only a thin ring; this is the dragon eye's own iris deepened.
  2. Hippus coupling — the pupil breathes autonomously (slow irregular hippus, visible with audio=0), and the
     stroma is anchored margin-to-root, so fibres compress and crimp as the slit widens (bass adds on top).
     Why: fuses the pupil-dilation system and the iris system, which HEAD kept independent.
  3. Corneal dome — Fresnel sheen reflecting the plasma, a Purkinje catchlight from the key light, and refraction
     parallax that makes the stroma sit behind the cornea as the camera orbits. Why: an eye has a cornea; HEAD
     had none.
  4. Tapetum eyeshine — the pupil nova flares retroreflectively when the camera crosses the gaze axis, and the
     eye's light illuminates the EXISTING volumetric plasma density as a gaze shaft along the mouse-look axis
     (occluded behind the eyeball). Why: couples the volumetric plasma subsystem to the eye/mouse-look subsystem.
FORBID on this file: spring cursor, click ripples, IQ palette, bismuth hopper/oxide/crystal ideas (sibling
  dragon-core owns those), a breath plasma jet cone (shipped gen-ethereal-cyber-plasma-void-dragon owns that),
  collarette zigzag / Fuchs crypts (shipped gen-iris-bloom-fractal owns those).
A PACKING: ACES display RGBA (as HEAD); C persistence now mixed in display space so C decodes consistently.
```

## Slider wiring
- Pupil Sharpness was DEAD (HEAD computed `sharpPupil` and never used it). Now it is the slit's superellipse
  exponent n = clamp(2 * psDefault / pupilSharpness, 1, 4): at the saved default n = 2 exactly = HEAD ellipse
  (checked numerically, max |diff| ~1e-7); higher = sharper cat-slit tips, lower = rounded-rectangle slit.
- Plasma Density: background plasma, volumetric haze, gaze shaft. Iris Complexity: ring fbm + stroma fibre count.
  Aberration: lens, CA ripple, CA tint (unchanged).

## Silent bugs fixed
- Unbounded iris/pupil primitives: fibre ring (`abs(r-0.8)`) and slit ellipse were infinite cylinders along z, so
  from side views of the orbit a glowing slab/tube ran across the whole screen through the scale shell. Both are
  now bounded to the front cap of the eyeball (z<0, |p| < R + small). This changes side views (intended fix).
- `extraBuffer[0]` write: HEAD stored its bass envelope in extraBuffer[0], which the engine overwrites with raw
  bass every frame (and pixel 0's write raced other workgroups). Now stateless: smoothBass = plasmaBuffer[0].x.
- `textureSampleLevel(dataTextureC, …)` -> exact `textureLoad(dataTextureC, coord, 0)`; C (ACES display) was
  mixed into HDR pre-ACES; now mixed after ACES.
- `pow(1.0 - cosi, k)` bases clamped with max(…, 0) (cosi can exceed 1 by an ulp -> NaN).
- Hardcoded alpha 1.0 -> the `presence` HEAD already computed (hit alpha + plasma glow).
- Iris ring shading used world-space p while its geometry lives in mouse-rotated eye space; now eye space.

---

```
SHADER: gen-sentient-ferro-silicate-swarm
IDENTITY (one sentence): a grid-repeated swarm of liquid-chrome ferro beads (one particle per 0.15-uv cell) pushed by
  curl flow, pulled by a brutalist KIFS SDF, shattered by bass, with fresnel oil-spill iridescence, velocity heat tint
  and a short temporal smear.
KEEP VERBATIM: hash2/hash3/noise3/fbm/curlNoise/kIFS/smin/brutalistSDF; gridScale 0.15 domain repetition and per-cell
  rnd/rnd3 particle offsets; curl push * (1 - rigidity); per-cell SDF attraction * rigidity * 0.02; bass * shatter * 2
  curl shatter; chrome spec pow 128 + fresnel^2; oil-spill cosine hue * iridescence; cyan->orange heat on vel * bass;
  density brightening; CA on vel; 0.25 temporal blend. Param roles: x Swarm Cohesion, y Fractal Rigidity,
  z Shatter Force, w Oil-Spill Iridescence (updatedParams unchanged).
ADD (2–4 native ideas):
  1. World-scale silicate assembly — the brutalist SDF is only ever evaluated in cell-local space, so the promised
     "self-assembles into brutalist architecture" never appears. Sample the same brutalistSDF at each cell's WORLD
     centre (slowly rotating slice) with an assemble/dissolve breath; cells inside the building lock their particle
     onto the lattice site (rigidity = snap strength, curl suppressed). Shatter Force sets how deep the dissolve
     phase eats the building; bass still blows locked cells loose. Visible at audio 0 (time-driven breath).
  2. Quartz facet crystallization — locked beads stop being round chrome: their normal is quantized to a hexagonal
     (6-sector x 3-tier) quartz facet set with bright facet-edge glints. Free beads stay liquid chrome. The swarm's
     phase change ferro -> silicate is the picture's new beat.
  3. Si–O bond struts — between a locked cell and each locked 4-neighbour, draw a glassy strut from particle centre to
     particle centre (thickness from Swarm Cohesion), so the assembled building reads as a bonded silicate network
     rather than 84 isolated beads.
  4. Curl-advected wake — the temporal feedback samples dataTextureC upstream along this cell's own curl vector
     (fuses the curl field with the temporal smear), so free fluid streams in comet-like wakes while locked crystal
     stays crisp (wake offset scales by 1 - lock).
FORBID on this file: Rosensweig spike lattice / |psi|^2 filaments or contours (entangled-ferrofluid owns them);
  field lines, dipoles, magnetic surface spikes (spectral-ferrofluid owns them); spring cursor, click-ripple
  shockwaves, IQ palette stamp; replacing the cell-grid swarm with a raymarched scene.
A PACKING: ACES display RGBA (alpha = swarm occupancy: bead/strut/lock coverage). C is read back as display RGB, so
  the blend happens in display space (consistent encode/decode).
SILENT BUGS FIXED:
  - dataTextureA was never written, so C was always zero and `mix(prevCol, col, 0.25)` rendered the whole effect at
    ~25% brightness. A now stores the blended display colour.
  - extraBuffer[0] (engine-reserved, CPU-overwritten) was read + written as a bass envelope from thread (0,0) — a race
    and an illegal write. Replaced with stateless plasmaBuffer[0].x.
  - Mouse "magnetic anomaly" was computed in cell-local coordinates against a screen-space cursor, so it was a
    uniform bias on every cell (and mouseY skipped the aspect mapping). Now the cursor is mapped into each cell's local
    frame, so beads near the pointer lean toward it and far cells are untouched (Cohesion still scales it).
  - Depth wrote constant 0; now writes a truthful relief (lock/occupancy).
```

---

```
SHADER: gen-sonoluminescent-chrono-geode-matrix
IDENTITY (one sentence): a spinning KIFS-folded crystal geode shell (clipped to a sphere) around a
  sonoluminescent bubble core that collapses every cycle, flashes blue-white and fires a ballistic
  shockwave shell, all swirl-smeared by C motion-blur trails.
KEEP VERBATIM: sdGeodeShell fold (4 iters, axis (1,1,1) rot 0.5, clip length(sp)-1); bubble core
  (exp-collapse coreR, noise churn); closed-form flash cycle (flashPhase/collapse/regrow); ballistic
  shell ringR; eased warpTime + orbital camera; fresnel iridescence; volumetric plasma_acc; swirl-
  advected C trails (raw HDR, decay 0.86-0.05*w, clamp 5.0); all 4 slider roles and mappings
  (Intensity / Speed / Scale / Mouse Influence) and the updatedParams block byte-exact; press-to-repel
  mouse; alpha/depth semantics.
ADD (3 native ideas — each couples two subsystems this file already has):
  1. Shock-front crystal ignition — the ballistic shell currently only glows in the void; where the
     front crosses the geode surface radius it now ignites a hot incandescent band on the crystal and
     jolts the shards outward as it passes (shell x geode, shading + SDF displacement).
  2. Collapse-deposited agate strata — real geodes are banded chalcedony laid down over time ("chrono");
     concentric radial strata on the geode material advance one band spacing per collapse cycle,
     eased by `regrow`, and the freshest band catches the flash colour (flash cycle x geode shading).
  3. Flash translucency through thin shard walls — thickness probe along -n (5 SDF samples) lets the
     core's collapse flash bleed through thin fractured walls (core x geode; the description promises
     the fracture "reveals" the core, HEAD only had a reflection dot product).
FORBID on this file: springs, click-ripple shockwaves (it has its own ballistic shell), IQ palette stamp,
  a new particle system, bismuth/hopper/oxide motifs (owned by siblings), changing the fold or camera.
A PACKING: raw HDR history RGB (pre-ACES, clamped <= 5.0) + semantic alpha — unchanged; C is read raw,
  writeTexture gets ACES. Consistent, so HEAD packing wins.

SILENT BUG FIXED: "bass-transient kick" in extraBuffer[133..135] never persisted (the engine re-uploads
  the whole 256-float scratch each frame, zeroing [133..255]) AND the single-thread write raced every
  other workgroup's read of [135] in the same dispatch -> per-16x16-tile kick flicker under audio.
  What it actually computed on the writer thread was prevBass=0, prevT=0, dt=0.1, kickE=min(2.5*bass,2).
  Replaced with that same value computed stateless per thread (no buffer writes, no race). Audio=0 look
  unchanged (kick was 0). Header no longer claims transient detection / dt-integration.
```

Notes: Idea 3 threshold chosen from a numpy port of the geode SDF (96x96 rays, 1666 hits): thickness-probe
sum percentiles p5 0.87 / p50 1.3 / p95 6.0 at h=0.035k -> smoothstep(1.2, 5.0) keeps bulk crystal dark and
lights only thin shards (an unthresholded clamp saturated ~30% of the surface). JSON: features +mouse-driven
(press repels shards), +upgraded-rgba; "bass-transient-kick" renamed "bass-kick" (the transient never existed);
updatedParams untouched. Look not GPU-verified (no adapter in this VM).

---

```
SHADER: gen-spectral-ferrofluid
IDENTITY (one sentence): a spectral-palette magnetic fluid whose iso-|B| contour bands and field-aligned FBM spikes
  wrap around a mouse pole plus three orbiting satellite dipoles, with viscous temporal memory.
KEEP VERBATIM: magneticField() radial+angular dipole kernel; mouse primary pole + 3 orbiting satellites
  (weights 1/0.4/0.3/0.2, radii 0.3/0.25/0.35); held-mouse polarity inversion; field-aligned fbm2/fbm3oct spikes;
  sin(fMag*12 - spikes*8) contour bands; ferroPalette/spikePalette; click-ripple disturbances; vignette, field-edge CA,
  gamma then ACES; the four slider roles and mappings (FieldStrength*3+0.5, Viscosity*0.3 memory, SpikeHeight*2+0.2,
  Turbulence); field-strength alpha; A/C raw-field packing.
ADD (native ideas):
  1. Archimedean flux spirals — the dipole kernel's radial(1/r^2):angular(0.5/r) ratio gives exact per-pole
     streamlines theta - 0.5 r = const. Superpose the four poles' stream functions (weights x10 = 10/4/3/2 integer
     windings, so atan2 seams vanish) and ink them as grooves crossing the existing iso-|B| contours: the orbit
     system and the line renderer finally couple into a woven field-line/iso-line net. Density-faded near poles;
     Turbulence slider wobbles the tubes.
  2. Cotton-Mouton birefringence (Michel-Levy tint) — "Spectral" made physical: field-induced delta-n ~ B^2
     (Langevin-saturated) gives optical path difference; per-RGB sin^2(pi*OPD/lambda) interference colours, times
     sin^2(2*alpha) between fieldDir and a slowly turning polarizer, so dark Maltese-cross isogyres sit on every pole.
     Uses the stored fieldDir that previously only drove a 3% chromatic nudge.
  3. Pole meniscus mounds — ferrofluid heaps over each pole (|B|^2 pull, so both polarities heap: held-mouse
     inversion keeps the mound). Analytic Lorentzian height -> analytic normal -> glossy black body + specular ring
     glint and Fresnel rim on the shoulder. Makes the header's "smooth specular normals" claim true (HEAD had none).
FORBID on this file: Rosensweig spike lattice, |psi|^2 filaments/contours (entangled-ferrofluid); labyrinth fingering,
  Taylor cones, dipole chain bridges, LIC iron filings, X-point null flash, Earnshaw wobble (shipped ferro/magnetic
  siblings); swarm/particle/silicate ideas (ferro-silicate-swarm); springs, extraBuffer state, IQ palette stamps.
A PACKING: raw field state, unchanged from HEAD — A = (fMag*0.25, fieldDir.x, fieldDir.y, alpha); C read exactly
  with textureLoad(dataTextureC, coord, 0) as fields. No ACES on A.

SILENT BUGS FIXED:
  - rms read plasmaBuffer[0].w, which the engine always uploads as 0 (audioDepth.ts writes [3]=0): orbit speed and
    turbulence rms terms were dead. Now rms = mean(plasmaBuffer[0].xyz) — identical at audio=0.
  - ripple loop bound u32(config.y) was the lifetime click count (unbounded) indexing ripples[50]: out-of-range reads
    after 50 clicks. Clamped to 50.
NOT CHANGED (noted): bass_env() is called with constant prev, so it is a fixed lerp, not an envelope — kept to preserve
  the look at the saved defaults.
```

---

SHADER: gen-superfluid-quantum-foam
IDENTITY (one sentence): a raymarched lattice of boiling iridescent foam bubbles, warped by a flow field and a
  cursor vortex, with magenta near-miss radiation glow, cyan click-cavitation shells and a faint temporal smear.
KEEP VERBATIM: domain-repeated sphere lattice (sp = 3/env, radius (0.6+h*0.6)*env + boil, boil = hash*sin(t*3+bass*10)*P1);
  vortex pull + xz twist inside Vortex Radius (P2); glow accumulator `(0.5-d)*0.08*P3` (P3); Current Speed time scale
  (P4); per-channel ndotv chromatic iridescence; fog; click-cavitation shell loop (age = time - ripple.z, no .w);
  magenta flash; temporal mix of C; ACES; depth write; A packing. All four saved params byte-exact.
  HEAD spring in extraBuffer[133..138] is left as-is (it never persists — buffer is re-zeroed each frame — so the
  cursor is effectively the raw mouse; noted, not "fixed" into new state).
ADD (3 native ideas, each fusing subsystems already in the file):
  1. Coalescing bubble necks — each sample now evaluates the 8 nearest lattice bubbles and smooth-mins them, so when
     the existing boil (P1) / warp / bass swell pushes neighbours together they fuse through a Plateau-style neck
     instead of interpenetrating. The description promises bubbles that "merge"; HEAD only ever saw one cell.
     (lattice x boil)
  2. Film-drainage black-film pop — every bubble gets a stateless life phase (speed tied to Current Speed). Its film
     drains as it ages: the iridescence gets a thickness-driven interference-order shift (thicker at the bottom by
     gravity drainage), goes to the dark "black film" just before rupture, then the bubble pops (radius collapses)
     and throws a short warm expanding burst shell into the glow accumulator — the description's "burst ... releasing
     flashes". (boil lifecycle x iridescence x radiation glow)
  3. Kelvin-wave vortex filament — the cursor vortex becomes a superfluid quantized vortex line: a vertical hollow
     core thread through the vortex centre carrying a travelling helical Kelvin wave, rendered analytically
     (ray-line closest approach, occluded by foam hits) as a dark core with a cyan sheath, plus an irrotational 1/r
     swirl of the bubbles around that moving core. Strength/extent from Vortex Radius (P2 = 0 turns it off, like HEAD).
     (vortex x superfluid flow)
FORBID on this file: virtual pair flashes, Born-rule detection hits, Worley F2-F1 membranes (gen-quantum-foam-alpha);
  Rosensweig spikes / |psi|^2 filaments (entangled-ferrofluid); geode collapse flash / sonoluminescence strata
  (sibling in this batch); new spring cursor, new ripple overlay, IQ palette stamp, extra particle system.
A PACKING: ACES display RGBA, premultiplied (col*alpha, alpha) — unchanged from HEAD; C read back as colour history.

SILENT BUGS FIXED (read path):
  a. `curlNoise` took finite differences of a white hash (hash33), so the "current" was a discontinuous random warp of
     up to ~6 world units (numpy port: jumps of 3-6 units every ~0.5 units of space) that shattered the spheres into
     shards; its z component was also not a curl (dPsi_y/dy - dPsi_y/dx). Now: correct central-difference curl of a
     smooth two-octave trig vector potential, same call site and 0.3*env scale, displacement ~0.3-0.9 units.
  b. Cell ID used floor(pos/sp) while the repetition used round(pos/sp), so every bubble was split into 8 octants with
     different radii. Now centres and IDs both come from the same lattice index.
  c. Camera-inside-bubble: ro=(0,0,-8) sits 1 unit from lattice centre (0,0,-9); once the warp is coherent the camera
     can be inside a bubble for whole seconds, and HEAD's `d < 0.001` test "hit" at dist 0 -> blank frame. Now the
     march uses the sign of map(ro) so inside-start rays reach the inner film (normal flipped to match).
KEPT-AS-IS NOTE: HEAD spring writes extraBuffer[133..138] at (0,0); that range is re-zeroed each frame so it is inert
  (cursor == raw mouse). Left untouched per contract.

---

# Idea Card — gen-symbiotic-bismuth-crystal-dragon-core

```
SHADER: gen-symbiotic-bismuth-crystal-dragon-core
IDENTITY (one sentence): a raymarched, breathing KIFS bismuth labyrinth (stepped-domain box folds,
  palette iridescence) fused by smooth-union to a liquid-gold sinew artery — the "symbiotic core" —
  with a mouse gravity well that drags the labyrinth toward the pointer.
KEEP VERBATIM: map() crystal branch (period-4 repetition, abs-fold + two time rotations per iteration,
  floor(bp*5)/5 stepped modulation, x1.5 scale, box SDF), sinew rotation r3 + sin^3 noise + radius 0.3,
  smin(k = 0.2*zoom) union and the crystal-0.1 material rule, sin(t*speed)*0.1+1 breathe, the mouse
  gravity well (mouse_pos, 2.0 radius, 0.5 pull), camera ro/rd, 100-step march + step AO + d^2 fog,
  palette(), crystal/gold shading formulas. Param roles: x Zoom, y Complexity (fold count),
  z Breathing Speed, w Iridescence Shift — all four saved `parameters` byte-exact.
ADD (3 native ideas):
  1. Ichor seep along the symbiotic seam — the smin blend weight h (where crystal and sinew
     distances meet) becomes a capillary stain: molten-gold ichor wicks outward from the seam into
     the bismuth with fingering, plus an emissive capillary line on the seam itself. The file's
     whole premise is the crystal/sinew symbiosis; this makes the union visible instead of a blend.
  2. Peristaltic heart-bolus — lub-dub double pulses travel down the sinew artery toward the viewer,
     bulging its radius and heating its emission; the artery mouth flares when a bolus arrives.
     Paced by Breathing Speed (heart rate). The description promises a core that "pulses like a
     heart"; HEAD only had a uniform global scale sine.
  3. Furnace underlight through the labyrinth — the artery is a heat source: crystal facets whose
     normals face the artery axis pick up warm core light that swells with each bolus, and the march
     accumulates a thin volumetric heat haze from sinew proximity so the core glows through gaps.
FORBID on this file: hopper terraces, oxide thin-film, twin-boundary seams, terrace-lip glints,
  flux lines (shipped bismuth siblings); iris/pupil/cornea (plasma-dragon-eye owns those);
  springs, click ripples, IQ-palette stamps, extraBuffer state.
A PACKING: ACES display RGBA (alpha = surface coverage x fog transmission + core haze). No C read —
  stateless; A mirrors the display frame for downstream history consumers.
```

## Silent bugs fixed (read path)
- **Camera inside the sinew (whole frame was a flat gold wash).** The sinew was an infinite z-cylinder
  of radius 0.3 around the view axis; the camera at (0,0,-4) sits inside it, so map(ro) < 0 and every
  ray "hit" at step 0 (numpy port: 100% of pixels hit at i=0, 100% sinew). The labyrinth was never
  visible. Fix: the artery is capped in world space at z = -2.5 (mouth in front of the camera, zoom-
  independent) and bores a lumen (radius 0.6 in folded space) through the crystal so it is seen
  running down a crystal-walled channel. Port after fix: ~1–11% sinew core at centre, labyrinth
  walls elsewhere, hits at median 1.5–1.7 units.
- **Audio read from `extraBuffer[0]`** (not audio). Now `plasmaBuffer[0].x` bass (breathe phase,
  bolus amplitude, flash).
- Floor: header, ACES, semantic alpha, depth write, A write were missing.
