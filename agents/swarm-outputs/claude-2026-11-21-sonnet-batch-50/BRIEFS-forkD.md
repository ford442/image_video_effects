# BRIEFS — fork D (sonnet/batch-50): gen-symbiotic-bismuth-crystal-dragon-core, gen-quantum-chrome-serpent-ouroboros

Written BEFORE any edit of the repo WGSL (scratch copies in `.../scratchpad/d/` were rendered only to read HEAD and the fixed baseline).

---

## 1. gen-symbiotic-bismuth-crystal-dragon-core (2nd pass)

### HEAD facts (measured)
- **Dead sliders / mis-routed uniforms (proof):** HEAD pastes `Uniforms { config, zoom_params, zoom_config, ripples }`; the engine layout is `config, zoom_config, zoom_params, ripples`. Render with sliders `1,3,.5,0` vs `2,6,1.5,.7` at identical mouse/time → **mean |pixel diff| = 0.0000** (all four sliders dead); moving the mouse changes the picture (13.3). So `zoom_level` = time, `complexity` = mouse x, `breathing_speed` = mouse y, `iridescence_shift` = mouse_down, "mouse_uv" = slider 2/3. HEAD picture = a gold smear (labyrinth never visible).
- Baseline for ideas = the prelude-fixed file (scratch `dragon_fixed.wgsl`): purple stepped bismuth labyrinth + a gold artery mouth, sliders live.
- A packing at HEAD: ACES display RGBA, written to A, no C read (stateless) — consistent, keep.

### Idea Card
```
SHADER: gen-symbiotic-bismuth-crystal-dragon-core
IDENTITY: a breathing techno-organic heart core — a bismuth hopper-crystal KIFS labyrinth with a liquid-gold sinew artery boring through it.
KEEP VERBATIM: 4 param roles (zoom_params.x zoom, .y complexity = fold iterations, .z breathing speed, .w iridescence phase); the abs-fold/rotate/stepped-modulation KIFS loop; modulo repetition; sinew artery + mouth cap + lumen; smin seam; the three existing ideas (ichor seep along the seam, peristaltic heart-bolus, furnace underlight + heat haze); mouse gravity well; ACES display RGBA in A, depth, semantic alpha; stateless (no C read).
RESCUE (not an idea): replace the pasted header+struct by #include "_prelude.wgsl" by hand (codemod refuses: struct-field-order) so the four sliders and the mouse read the right slots. Default picture changes (loud). Second rescue only if verified: rays that exhaust MAX_STEPS without hitting keep mat_id >= 0 and are shaded as hits (speckle) — verify before touching.
ADD:
  1. Fold-count oxide terraces (§12.2E "fold count as material") — the KIFS loop already reflects the point with abs() every iteration; the number of reflections each terrace saw is thrown away. Real hopper bismuth owes its colour to an oxide film whose thickness differs terrace by terrace; folds-per-point is that thickness proxy, so it offsets the existing iridescence palette phase (the iridescence_shift slider keeps its role: global phase).
  2. Silver edge wear from SDF curvature (§12.2E "SDF curvature") — at the hit, a central-difference Laplacian of map() over the stepped terraces: convex step edges rub through the oxide to bright un-oxidised silver-white metal; concave risers darken (tarnish). Real bismuth crystals show exactly this bright-edge / dark-recess contrast.
  3. (supporting, not a visual idea) over-relaxed sphere tracing (§12.2E) with the standard fall-back so the added hit-only taps stay inside the 1.3x budget. Dropped if it leaves artefacts on the stepped (discontinuous) SDF.
FORBID on this file: springs, ripples, a new SDF primitive, replacing the palette with a different look, any C/B state.
A PACKING: ACES display RGBA in A (unchanged, stateless).
```

### §12.1 mechanism interrogation
- **Tactic 1 (kernel):** the kernel is a KIFS fold + box DE with a stepped (floor) domain modulation; next-better approximation of the same operator = a marcher that exploits the DE (over-relaxation) — idea 3.
- **Tactic 2 (physics one step further):** real bismuth: stair-step hopper terraces; interference colours from a thin oxide whose thickness varies per terrace; silver metal where edges are worn. → ideas 1 and 2.
- **Tactic 3 (promote an intermediate):** (a) the per-fold reflection count (`bp` before `abs`) is computed and discarded → idea 1; (b) the 4/7 `map()` taps at the hit exist for the normal → idea 2 reuses a 6-tap central-difference stencil as both normal and curvature (net +2 map calls at hit pixels only).
- **Tactic 6 (history):** n/a — the file is stateless and stays so.

### §12.4 formula admission
| Row | Family match | Operates on what exists | Deletion test |
|---|---|---|---|
| fold count as material | KIFS (E) | the existing fold loop | removing it leaves the identical shape/shading (additive); the idea alone is not a bismuth labyrinth |
| SDF curvature | hard-surface/crystal SDF (E) | the existing `map()` | idem |
| over-relaxed tracing | any raymarched SDF (E) | the existing march loop | pure cost offset |

---

## 2. gen-quantum-chrome-serpent-ouroboros (2nd pass)

### HEAD facts (measured)
- JSON has no `params` (x-meta stripped from the app list) → the app always feeds 0.5 to all four slots; the intended x-meta defaults (1.5, 1.0, 2.0, 1.2) never reach the shader. HEAD at 0.5: **meanL 0.072, stdL 0.024** — dark navy bands, the serpent is not recognisable. At x-meta defaults: meanL 0.11.
- Diagnosis of the near-black picture (three independent causes):
  1. **Chrome in a black void:** the environment map peaks at ≈0.1 (`… * 0.1`), the only other light is a `0.1*ndotl` diffuse, so a chrome body reflects ~black.
  2. **Camera is edge-on to the ring:** `ro.y = sin(0.05 t) * 2` at radius 8 → elevation ≤ 14°, exactly 0° at t=0. The torus plane is XZ, so the loop that makes it an *ouroboros* is never visible: at p4=2.0 (widest FOV) HEAD renders a horizontal band.
  3. **Twist is a shear:** `pos.x = …; pos.z = pos.x*… + pos.z*…` reuses the already overwritten `pos.x` (not a rotation) → the "magnetic twist" skews the SDF instead of twisting it.
- A packing at HEAD: header says "ACES display RGBA", but the code stores the PRE-ACES `col` (raw linear) in A, reads it back as colour history (`prev.rgb*0.92` mix); ACES is applied only on `writeTexture`. The code is self-consistent; the header was wrong → corrected to "raw linear pre-ACES col + alpha; ACES on writeTexture".
- Schlick Fresnel (conductor F0), audio chromatic reflection aberration and the additive twist are ALREADY at HEAD: kept; Cauchy dispersion NOT added (metals do not disperse, a fixed ±δ aberration on a reflection direction is the file's idea; expert test fails).

### Idea Card
```
SHADER: gen-quantum-chrome-serpent-ouroboros
IDENTITY: a liquid-chrome serpent ring coiling in an abyss, scaled hide, core-heat leaking through the plates, camera orbiting.
KEEP VERBATIM: 4 param roles (p1 coil twist, p2 scale frequency, p3 core heat — trail glow/aberration/leak, p4 the FOV "dispersion"); torus r1=3/r2=0.8; sine-product scales + audio bump + KIFS micro term; Schlick conductor Fresnel; audio chromatic reflection aberration; quantum dispersion trail; fbm plasma leak; fog; 5% temporal blend through C; under-relaxed (0.7) march; A = raw pre-ACES col + alpha, ACES on writeTexture only.
RESCUES (loud): (a) environment strips raised from 0.1 to a few x with sharper falloff, SAME two cyan/purple bands, so chrome has something to reflect (the void stays dark between them); (b) camera lifted to a ~25-35 deg elevation so the loop reads as a ring; (c) twist shear fixed (temporary variable). Header A-packing text corrected.
ADD:
  1. Ouroboros head-swell / tail-taper profile — the minor radius gets a continuous profile around the ring: thin tail that narrows toward the head, a swollen head/neck just past it, the whole profile slowly circulating (the snake chasing the tail it is swallowing). Without it the ring has no head and no tail; with it the file earns its name. Pure r2 modulation: torus, scales and KIFS untouched.
  2. Plate-crevice step-count AO on the reflection (§12.2E "step-count AO") — 5 map() taps along the normal darken the env reflection and diffuse where overlapping scale pits trap light (reflection occlusion), so the sine scales read as plates instead of a smooth wave. Consumes the existing map(); no state.
FORBID on this file: springs, ripples, IQ palettes, replacing the env with a new scene, any new param, Cauchy/thin-film colour on the metal.
A PACKING: raw linear pre-ACES col + alpha in A (unchanged behaviour; header corrected); ACES on writeTexture.
```

### §12.1 mechanism interrogation
- **Tactic 1:** the torus SDF with a constant minor radius is the base; the next-better anatomy is a varying radius along the centreline (a snake body profile) — idea 1.
- **Tactic 2:** chrome's visible physics is *what it reflects* and *where reflection is blocked* — the first is the env rescue, the second (occlusion in plate crevices) is idea 2.
- **Tactic 3:** `theta` (toroidal angle) is already computed for the scale pattern and thrown away otherwise → idea 1 uses it as the ring coordinate.
- **Tactic 6:** C is read as colour history (5% blend) — kept; no new use.

### §12.4 formula admission
| Row | Family match | Operates on what exists | Deletion test |
|---|---|---|---|
| step-count AO | raymarched SDF (E) — shared with the griffin (fork E), max 2 files | the existing `map()` + normal | delete → identical effect minus crevice shading; AO alone is not a serpent |
| (idea 1) taper | not a §12.2 row; native anatomy (tactic 5/7) | the existing `theta` and `r2` | delete → today's constant-width ring; the taper alone is not chrome scales |

---

## AMENDMENTS after measurement (written before the serpent WGSL edit; dragon-core edits were already in when these were found)

### dragon-core — Idea 2 changed, Idea 3 dropped (evidence, not taste)
- **SDF curvature DROPPED.** Measured on a scratch debug view: the crystal DE is one-sided (`d_box = length(max(abs(bp)-0.5, 0))/scale` is 0 inside the box) and floor()-stepped (discontinuous at every terrace wall). A plain tetra Laplacian was positive on 39 % of crystal pixels and never negative (bias from clamped-inside taps); a one-sided shell stencil (taps offset out along the normal) is clean on the sinew but on the crystal only ~1 % of pixels register and as isolated speckle (3 stencil sizes tried: h=.045/.09/.16). Not usable → not shipped.
- **Idea 2 is now "Schlick conductor Fresnel silver rim" (§12.2F row Fresnel–Schlick, owned by dragon-core + serpent).** Same story as the dropped idea (worn terrace walls show un-oxidised silver) but driven by the normal, which is clean. First version (F = .05 + .95 (1-n.v)^5) greyed the whole labyrinth (the tunnel is mostly seen at grazing angles) — tightened to F = .04 + .5 (1-n.v)^9 and the silver tinted 22 % by the oxide colour so identity survives.
- **Over-relaxed tracing (ω=1.3, Keinert fall-back) DROPPED:** interleaved min 427 ms vs 423 ms (same file without it): no speed-up on this discontinuous DE, only artefact risk.
- Extra rescue found: pow(1-n.v, k) base clamped to [0,1] (n.v = max(dot,0) is not bounded above, a tiny negative base would be NaN).

### serpent — the card's Idea 2 had no substance; re-carded
- Measured geometry: scale pattern is `sin(theta*f)*sin(phi*f*0.5)*0.05` with f = 10*p2 (=5 at the app's 0.5): wavelengths ≈ 3.8 x 2 world units, amplitude 0.05, and the KIFS term is `length(q)*0.01`. The tube is a gentle undulation: **there are no crevices**, so step-count AO alone would darken nothing. (Idea by itself fails the "pointable in the picture" test.)
- **Camera rescue (b) DROPPED.** Lifting the camera to 25–35° elevation puts the ray through the ring's hole and, with the app's FOV (p4 = 0.5 → focal 4, ~14° total FOV; there are no sliders because the JSON has no `params`), the picture would be empty void. The edge-on orbit (<= 14° elevation, near-tube in the centre of the frame) is the author's framing; p4 is the user's FOV control. Recorded as an open call for the coordinator, not changed.
- **New card (3 ideas):**
  1. Ouroboros head-swell / tail-taper profile (native anatomy, no §12.2 row) — unchanged from above.
  2. Shingled keeled scale plates — a sawtooth overlap (free edge lower than the next row's rim) on a brick-offset (θ, φ) lattice, plate density keyed to the existing Scale Density slider, soft keel along each plate; amplitude 0.045. This deepens the *same* scale operator (tactic 1: sine undulation -> overlapping plates); the sine-product stays as the large-scale swell. Native on a snake (imbricate, keeled scales).
  3. Step-count AO on the chrome reflection (§12.2E, shared with the griffin) — now has crevices to read: dims env reflection and diffuse in the overlap grooves.
  KEEP VERBATIM list unchanged; FORBID unchanged. Rescues: (a) env strips raised, (c) twist shear fixed; header A packing corrected.
