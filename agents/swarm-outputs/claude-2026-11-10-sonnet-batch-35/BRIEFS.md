# sonnet/batch-35 — Idea Cards (written BEFORE any idea edit to WGSL)

Theme (already lives in the files): fibre / kaleidoscope / lens / glass optics — a woven fibre bundle, a scale roof, a breathing mirror-wedge kaleidoscope, a ferrofluid rune wheel, a wormhole lens, a cymatic glass geode, a mushroom mandala, a rotating-snakes illusion, a rainy window and a brass gear loupe.
10 catalog ids, 10 WGSL files. Contract: `docs/SHADER_UPGRADE_BATCH.md` (§0, §2, §9, §12). Header date: **2026-11-10**.

Infrastructure done first, in its own commit (`798d840`): 4 of the 10 files pasted the 13-binding header (`fiber-optic-weave`, `biomimetic-scales`, `breathing-kaleidoscope-morph`, `mouse-wormhole-lens`); migrated with `scripts/migrate_to_prelude.py --naga` (header-only, V1–V5 proved). **No `Upgraded:` bump for that.**

Engine facts re-verified in this checkout (`src/renderer/webgpu/audioDepth.ts::writeExtraBuffer`): the whole 256-float `extraBuffer` is re-uploaded every frame (`[0..2]` audio, `[4]` history head, `[5..132]` FFT, everything else zero). The `[133..138]` pointer springs in `fiber-optic-weave`, `optical-illusion-spin`, `glass-wipes` and `steampunk-gear-lens` therefore never persist (their "seeded" flag reads 0 each frame, so they behave as the raw cursor). **None of this batch's ideas builds on that state**; it is reported, not rescued (out of scope for a idea batch). `plasmaBuffer[1..]` is not audio either (`fiber-optic-weave` per-fibre voices, `glass-wipes` per-band hue) — same: reported, untouched.

Tactics (§12.1): T1 deepen the kernel · T2 physics one step further · T3 promote an intermediate · T5 name the device artifact · T6 history the shader already owns · T7 direction not magnitude. Ideas are numbered per file so a coordinator can grep `// ── Idea n`. Second-pass files continue their own numbering.

Row ledger (§12.4, each §12.2 row on ≤ 2 files): Cauchy dispersion (F) 1 (fiber) · Brown–Conrady (B) 1 (steampunk) · Step-count AO (E) 1 (cymatic) · Snell/thin-lens inversion (F) 1 (glass-wipes) · Structure-tensor / halation / grain / dropout 0. Nothing repeats; no spring, ripple, IQ palette or conveyor is added anywhere.

---
## 1. fiber-optic-weave — interactive-mouse, 160 lines, no `Upgraded:` header
```
SHADER: fiber-optic-weave
IDENTITY: the photo cut into horizontal glowing optical fibres that weave, get plucked by the pointer, carry a coloured signal pulse along each strip, and launch one-shot pulses from clicks.
KEEP VERBATIM: 4 params (Fiber Density → strip count, Fiber Glow, Mouse Force, Weave Fray); strip/odd-even weave; pluck gate + click pulses; repulsion; edge glow `glowFactor`; golden-ratio pulse position per strip + pulse palette; the peak limiter; semantic alpha; depth relief; A = display RGBA.
INTERROGATION: T2 a real fibre pulse is not a symmetric Gaussian — chromatic dispersion makes the pulse's red and blue components travel at different group velocities, so the packet broadens and splits into colour fringes with distance travelled (here: x from the launch edge). T5 a technician names fibre artifacts: modal dispersion (above), **macrobend loss** — light escapes the core where the fibre is bent, long wavelengths first — and connector glare. Bend loss is absent. T3 the pluck displacement (`pluck`, `clickPluck`) is already a sinusoidal bend whose curvature is analytic.
ADD:
  1. Chromatic pulse dispersion (§12.2F "Cauchy dispersion"): R/G/B pulse positions get a Cauchy `B/λ²` group delay proportional to distance travelled; the packet broadens as √x and fringes red-leading / blue-trailing (normal dispersion: red is the faster group), with a sharper leading and longer trailing edge. Replaces the single `pulseGlow` Gaussian *shape*, not its timing or palette.
  2. Macrobend leakage: curvature of the pluck/click bend (`|d²offsetX/dx²|` of the existing sinusoids, closed form) leaks a red-biased glow out of the cladding exactly where a strip is bent hardest; amplitude rides Mouse Force.
FORBID: springs, extra ripples, IQ palette, any new param, changes to the weave/pluck maths.
A PACKING: display RGBA (HEAD's).
ROWS: Cauchy dispersion (F).
```

## 2. biomimetic-scales — interactive-mouse, 158 lines, no `Upgraded:` header
```
SHADER: biomimetic-scales
IDENTITY: a staggered roof of overlapping domed scales (higher rows on top) that tilt away from the pointer; the photo is seen refracted through each scale and lit by one diffuse+specular light.
KEEP VERBATIM: 4 params (Scale Size → density, Roughness, Reaction Radius, Lift Strength); 3×3 neighbour loop, stagger, radius 0.65, layer stacking, dome normal, pointer tilt; refraction `0.02·(1−roughness)`; diffuse/spec; gap branch; A = (diff, spec, 1, alpha) raw lighting terms (HEAD's documented packing).
INTERROGATION: T5 a technician (fish scale / roof tile) names: **circuli** (concentric growth ridges on every fish scale) and the **contact shadow** an overlapping scale casts on the one beneath it at the imbricate edge. Neither is present: the scales are smooth domes and the overlap edge is only a depth step. T3 `dist` (radius from the scale centre) and each neighbour's `layerDepth` are already computed.
ADD:
  1. Circuli growth ridges: radial `cos(dist·k)` ridge pattern, perturbing the dome normal along the radial direction; amplitude rides Roughness (rougher scales read more ridged).
  2. Imbricate contact shadow: a second 9-cell pass over the neighbours that sit *above* the visible scale casts a soft shadow just outside their rim (offset along the light direction) onto it.
FORBID: thin-film/iridescent paint, IQ palette, springs, any new param.
A PACKING: A = (diff, spec, 1, alpha) raw terms — unchanged; display RGB stays in writeTexture (ACES added to display RGB only).
ROWS: none.
```

## 3. breathing-kaleidoscope-morph — advanced-hybrid, 158 lines, no `Upgraded:` header
```
SHADER: breathing-kaleidoscope-morph
IDENTITY: a mirror-wedge kaleidoscope that breathes in and out around the pointer, whose folded picture is morphologically eroded/dilated per segment with a pointer-rotated disk kernel, gradient and top-hat computed from the same taps.
KEEP VERBATIM: 4 params (Cycle Speed, Segments, Rotation Speed, Breath Depth→max rotation); `ping_pong` breath; wedge fold + rotation; ripple distortion; per-segment golden-ratio erosion↔dilation blend; the disk kernel with pointer-driven anisotropy; `gradient·0.3` mix; alpha = top-hat luma.
INTERROGATION: T5 the device is a mirror tube: a real one shows the **mirror seams** where adjacent wedges meet (a bright bevelled line at each reflecting edge). HEAD folds the angle with `abs(fract·2−1)` but draws no seam. T3 the white **top-hat** (`centerSample − erosion`) is computed on every pixel and only its luma leaks into alpha; its RGB — the small bright detail the erosion removed — is thrown away.
ADD:
  1. Mirror-seam bevel: arc-length-constant bright line along both reflecting edges of every wedge (`min(m, 1−m)` of the existing `mirroredAngle`), tinted by the sampled colour, gated by the breath blend so it fades with the kaleidoscope.
  2. White top-hat detail re-injection (§12.1 T3): the already-computed top-hat RGB is added back on the dilation side of the per-segment blend, so the erosion no longer erases fine bright structure; amplitude rides the breath.
FORBID: new params, changing the kernel/blend maths, springs, IQ palette, any new fold.
A PACKING: display RGB + top-hat luma in alpha (HEAD's, unchanged).
ROWS: none.
```

## 4. gen-magnetic-liquid-glyphs — generative, 158 lines, Created 2026-07-17 (no `Upgraded:`)
```
SHADER: gen-magnetic-liquid-glyphs
IDENTITY: a wheel of seven rune glyphs fused by smooth-min into dark iron liquid metal, whose orientation follows an external magnetic field (pointer x), with bass/treble envelopes and an auroral edge glow.
KEEP VERBATIM: 4 params (Glyph Scale, Chaos, Aurora Emission, Hue Base); domain warp; the glyph wheel construction; `mask`/`edge`; dark-iron palette, spec, fresnel, aurora; bass/treble envelope history in C.rg; ACES + huePreserve + IGN dither; transmission alpha; A = (bassEnv, trebEnv, d, alpha).
INTERROGATION: T1/T3 HEAD's "gradient normal" differences the *distance value* (`d ± e`) not the position, so `gy ≡ 0` and the metal is lit by a one-axis bump — the surface-tension meniscus the SDF already implies never reaches the shading. T2 a magnetic liquid in an applied field is a ferrofluid: above a critical field it develops **Rosensweig spikes** along the field lines on surfaces that face the field — the first-order side effect of "magnetic liquid" that HEAD (which already rotates the whole wheel with the field) does not show. The field axis is the rotated frame's `p.x`.
ADD:
  1. Meniscus bevel normal: true spatial gradient of the glyph-wheel SDF (two extra evaluations of the same wheel), height profile rounded by surface tension → real bevelled metal highlights around every contour.
  2. Rosensweig spikes: a periodic spike lattice across the field (`p.y`), displacing the level set only where the contour faces the field (`|n·fieldAxis|`, from idea 1's gradient); height rises with the bass envelope above a critical threshold (sqrt law).
FORBID: new params, replacing the glyphs, changing envelopes/palette/alpha, any particle system.
A PACKING: A = (bassEnv, trebEnv, d, alpha) — d stays the pre-spike wheel distance (HEAD's documented packing).
ROWS: none (ferrofluid is this file's own noun).
```

## 5. mouse-wormhole-lens — interactive-mouse, 158 lines, Upgraded 2026-09-09 (Ideas: inverse-square lensing; exact-C throat ghost)
```
SHADER: mouse-wormhole-lens
IDENTITY: a pointer-anchored spiral portal that shows the mirrored scene through a compressed throat, with stretch along pointer velocity, a blue edge ring, hue rotation, lensing at the rim and click-spawned mini-portals.
KEEP VERBATIM: 4 params (Portal Radius, Spiral Strength, Color Shift, Lens Strength); stretch along pointer velocity; spiral/compressed mapping; `1−sampleUV` mirror; edge ring; inverse-square lensing and exact-C throat ghost (the two shipped ideas); ripple mini-portals; ACES; alpha.
INTERROGATION: T2 second pass — a spiralling portal that already rotates is the picture of an accretion ring: the real optical signature of a rotating ring near a compact object is **relativistic Doppler beaming**, the approaching side far brighter than the receding side, plus the **gravitational redshift** of light climbing out of the throat. Neither is present; the ring is rotationally uniform and the throat is only darkened with a fixed purple mix. T3 `localAngle`, `normalizedDist` and the spiral's own `time·0.5` rotation rate already exist.
ADD:
  3. Doppler-beamed photon ring: a thin ring just inside the rim whose brightness goes as `(1 + β cos(φ − ωt))³` using the spiral's own angular rate; one bright arc that orbits with the portal.
  4. Gravitational redshift at the throat: colour shifts toward red and dims with depth `(1 − normalizedDist)²`, depth scaled by Lens Strength (the file's own "gravity" slider).
FORBID: new params, changing the shipped lensing/ghost, springs, extra click systems, IQ palette.
A PACKING: ACES display RGBA (HEAD's).
ROWS: none.
```

## 6. gen-cymatic-void-glass-geode — generative, 155 lines, no header features, never upgraded
```
SHADER: gen-cymatic-void-glass-geode
IDENTITY: a raymarched Apollonian-fold geode of iridescent void-glass whose surface carries a cymatic standing-wave displacement, with orbit-trap vein glow, mouse gravity well and a deep-space background.
KEEP VERBATIM: 4 params (Speed, Cymatic Freq, Cymatic Amp, Gravity Strength); the 4-iteration Apollonian fold; `base_sdf + disp`; camera dolly; iridescent palette on Fresnel + orbit trap; vein glow; step-count SSS; gamma 0.4545.
INTERROGATION: T3 `disp = sin(|p|·freq − t)·cos(4θ)·amp` is computed in `map()` and thrown away; cymatics is *defined* by its nodal lines (where the standing wave is zero and sand collects), and that zero set is exactly `disp ≈ 0`. T2 a raymarcher that already marches has the cheap, native way to read crevice occlusion: step-count AO along the normal. T6/floor bug: the audio read is `dataTextureC(0,0).x`, which nothing in this file ever writes — the audio claim is dead.
ADD:
  1. Chladni nodal lines: the displacement is factored into a shared `cymaticDisp()`; shading adds a luminous, narrow sand-line where `|disp|` is near zero on the surface (width follows the displacement slope so lines stay crisp), tinted by the existing vein colour.
  2. Step-count ambient occlusion (§12.2E "Step-count AO"): five taps of the file's own `map()` along the normal darken crevices between folds.
RESCUE (floor, reported separately): audio now reads `plasmaBuffer[0].x` (bass) instead of the never-written C(0,0); the unused A/depth outputs get a truthful depth.
FORBID: new params, changing the fold, the palette or the camera, springs, scanline/glitch costumes.
A PACKING: display RGB (HEAD wrote none to A; it still doesn't).
ROWS: Step-count AO (E).
```

## 7. gen-mushroom-mandala-garden — generative, 155 lines, Upgraded 2026-10-10 (Ideas: lamellulae gill tiers; Buller's-drop spores; partial-veil annulus; universal-veil warts)
```
SHADER: gen-mushroom-mandala-garden
IDENTITY: a radial mandala of breathing bioluminescent mushroom caps with gills, spores, mycelium, a fairy ring, partial-veil annulus and veil warts; the pointer drags the caps, clicks release spore fronts.
KEEP VERBATIM: 4 params (Cap Count, Breathe Rate, Gill Detail, Bioluminescence); the cap/stem/ring construction; all four shipped ideas (lamellulae, Buller's drop spores, annulus, warts); sinusoidal `mycelium` lines; fairy ring; history mix; ACES; A = display RGBA.
INTERROGATION: T5/T3 a mycologist names the **striate (translucent-pleated) cap margin** — in thin-fleshed caps (Mycena, Parasola) the gills show through the margin as radial pleats; the gill phase (`gillPhase`, `lamella`) is already computed and only shades the gill layer. And T2 the **mycelium** is a single sinusoidal line family, but a real network is defined by **hyphal anastomosis** — hyphae fuse at nodes, and nutrient pulses travel the network; the `mycelium-network` feature has no nodes.
ADD (ideas 5–6; 1–4 are the shipped pass):
  5. Striate translucent margin: toward the cap's margin side (`ringCoord > 0`) the gill phase pleats the cap's own brightness, so the gills read through the cap flesh.
  6. Hyphal anastomosis nodes: a second crossing hypha family at a different orientation; where the two lines cross a bright fusion node, with a nutrient pulse that travels along the hypha (rides mids).
FORBID: new params, a new creature, changing the shipped four ideas, springs, IQ palette changes.
A PACKING: ACES display RGBA in A (unchanged).
ROWS: none.
```

## 8. optical-illusion-spin — image, 153 lines, Upgraded 2026-08-30 (no `Ideas:` line)
```
SHADER: optical-illusion-spin
IDENTITY: a "rotating snakes" illusion over the photo: two counter-rotating snake-ring lattices, their moiré, a Fraser-spiral whip and ring-packet pulse around a (sprung) pointer centre, with colour afterimage fringes.
KEEP VERBATIM: 4 params (Ring Count, Speed, Twist Force, Alternating); `snakePattern` rings × wedges, `patA/patB/moire`; packet pulse; Fraser whip; click twist; hold spin; afterimage; exact-C history mix; ACES; alpha; A = display RGBA.
INTERROGATION: T2/T5 the rotating-snakes illusion (Fraser–Wilcox / Kitaoka) is produced by one device: a repeating **asymmetric luminance ramp** (dark → dark-grey → light → light-grey) inside each wedge, mirrored on alternating rings; HEAD's `snakePattern` is a symmetric band (`edge × ringEdge`), so the pattern has the geometry but not the cue that makes it drift. Second, the effect is a *peripheral* one — it vanishes at the fixation point; HEAD paints full contrast to the exact centre where rings alias into noise.
ADD:
  1. Asymmetric four-step luminance ramp per wedge (Kitaoka order), mirrored on alternating rings via the file's own `alt`; modulates `opArt` inside the existing band so the drift cue is present.
  2. Peripheral gain / fixation dead-zone: the illusion amplitude rises with eccentricity from the pointer (`radius`) and relaxes at fixation, which also removes the centre alias.
FORBID: new params, a second pattern, springs/ripples (already present), changing packet/whip/twist/afterimage maths.
A PACKING: ACES display RGBA (unchanged).
ROWS: none.
```

## 9. glass-wipes — liquid-effects, 152 lines, no `Upgraded:` line (Batch 67 header)
```
SHADER: glass-wipes
IDENTITY: a rainy window with a persistent wetness/flow/thickness field (raw A), falling rain beads, splashes, a pointer wiper and an autonomous elastic wiper sweep; thin-film colour on the water layer.
KEEP VERBATIM: 4 params (Rain Intensity, Wiper Size, Distortion, Drying Speed); raw A = (wetness, flow, thickness, coverage); rain-cell beads and tails; splashes; pointer wiper; elastic sweep; gradient-normal refraction; fresnel/specular/absorption; thin-film hue; ACES; alpha.
INTERROGATION: T5 a driver names two things every wet windscreen shows: each water bead is a **tiny fish-eye lens that shows the scene upside down**, and a squeegee leaves a **thin line of water along its trailing edge**. HEAD refracts through the film gradient only — a bead is a smudge, not a lens — and the sweep wipes clean with no residue. T3 `drop`, `cell`, `seed`, `fall` and the sweep direction (`sweepT`) already exist.
ADD:
  1. Inverted drop-lens (§12.2F thin-lens inversion): inside each bead the source is sampled mirrored about the bead centre (centre rebuilt from `cell`, `seed`, `fall`) with magnification; the bead shows a small upside-down image of the scene.
  2. Squeegee residue line: a thin water line is deposited into the raw wetness field along the sweep blade's trailing edge (direction from `sweepT`), so it persists and dries with the field.
FORBID: new params, a new solver, springs, a second wiper, changing A's raw packing.
A PACKING: raw A = (wetness, flow, thickness, coverage) — unchanged; the residue is added to wetness *before* the A store; tone-mapping only on writeTexture.
ROWS: Snell/thin-lens inversion (F).
```

## 10. steampunk-gear-lens — image, 151 lines, Upgraded 2026-08-01 (Batch 23)
```
SHADER: steampunk-gear-lens
IDENTITY: a toothed gear-shaped lens that tracks the pointer and spins; the picture inside is sepia, the rim is copper metal; clicks kick the gear and flare the rim.
KEEP VERBATIM: 4 params (Gear Size, Teeth Count, Rotation Speed, Sepia Strength); gear radius/teeth shape, rotation + kick, mask/rim, sepia mix, metal rim mix, click flares, depth relief, alpha.
INTERROGATION: T1/T2 a magnifier-gear is a lens: HEAD's `uv_lens` is a pure *rotation* of the picture — no magnification at all, so the "lens" is a rotating window. The first-order optics of a real brass loupe is magnification with barrel distortion (compressing toward the rim). T5 the metal is a flat copper constant lit only by `toothLight`; a lathe-turned brass rim shows **concentric machining grooves and an anisotropic highlight** that does not rotate with the gear (the light is fixed in the world).
ADD:
  1. Brown–Conrady barrel magnification (§12.2B): inside the gear the lens position is scaled by `1/(M(1 + k₁ ρ²))` with `ρ = r/gear_r`, magnifying the centre and compressing toward the rim; magnification rides Gear Size's smallness (small gear = loupe).
  2. Turned-brass anisotropic rim: concentric lathe grooves in the rim band, with a world-fixed anisotropic highlight (`pow(|cos(a − lightAng)|, n)`) that stays put while the teeth spin.
FORBID: new params, springs, a second gear, changing the rotation/kick/sepia maths.
A PACKING: display RGBA (unchanged).
ROWS: Brown–Conrady (B).
```
