# sonnet/batch-22 — fork A briefs (written before any WGSL edit)

Shaders (all 2nd pass, each already has an `Ideas:` line): gen-ethereal-quantum-glass-nautilus, gen-radiant-chrono-glass-nautilus, gen-symbiotic-chrono-mycelium-engine.
HEAD diagnostics were done on scratch copies only (scratchpad/forkA/scr/), never on the real files. Baselines: scratchpad/forkA/out/*_head.png (288 px, t=2 and t=9, JSON defaults, 0.5x4 for the mycelium which has no top-level `params`).

Minirender caveats that matter here: it never re-uploads extraBuffer (none of these three uses extraBuffer state, so nothing is hidden), it has no source image by default (ethereal's `envRefr` samples a black/flat texture), and 8-frame renders are fine because none of the three reads C as history beyond a 0.04 mix.

Library-wide trap seen in all three: `uv.y` is NOT flipped. `base_uv.y = id.y/res.y` (ethereal) and `(fragCoord - 0.5*res)/res.y` (radiant, mycelium) are 0 at the TOP row of the texture, so world +y points DOWN the image. Ethereal's camera sits at y=+2, radiant's face-on swirl is mirrored, and the mycelium's key light (1,1,-1) lights it from below.

---

## 1. SHADER: gen-ethereal-quantum-glass-nautilus (abyssal / pearl)

IDENTITY: a bioluminescent glass-and-pearl chambered nautilus — a log-spiral shell with chamber septa, pearl nacre ridges, siphuncle, aperture lip, siphon jet and abyssal pressure fractures, under an orbiting camera.

KEEP VERBATIM: 4 params + roles (refractionIndex -> env-refraction offset + lip highlight, spiralTightness -> whorl growth `b`, iridescenceShift -> iridescence/nacre phase, audioReactivity -> pulse + glow); the `n / nf / r0 / r1` two-whorl tube map, septa plane, siphuncle, voronoi grit, audio `pulse`; iridescence, env refraction, core glow, pearl nacre, edge, lip highlight, siphon jet, pressure fractures; C mix 0.04; ACES display RGBA in A; depth = 1 - d/MAX_DIST.

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): the map is an infinite log spiral: both whorl tubes have radius `0.4*r_whorl` with spacing only `(e^b - 1)*r` = 0.22 r at the default b = 0.2, so adjacent whorls overlap into one flaring solid cone that extends to r = infinity. A real shell is a FINITE tube that ends in an aperture. The terminating whorl is the same mechanism with an end.
- Tactic 2 (physics one step further): a glass shell has thickness; the light that reaches the eye from behind it (env refraction + the core glow) has crossed a chord of glass = `2 R cos(theta_t)` and been absorbed per wavelength. HEAD adds `envRefr*0.3 + glow` unattenuated, so the 2-unit-thick outer whorl is exactly as transparent as the thin apex.
- Tactic 3 (promote an intermediate): `r` / `a` / `b` give the whorl radius at the hit (tube radius = `0.4 r`) and `nf`/`a/TAU` give the growth coordinate `k` (turns since the apex). Both are already computed in `pearlNacreLuster` / the lip block; the new ideas reuse them. `NdotV` and `n` exist.
- Tactic 5 (artifact of the real organism): Nautilus pompilius shows dark conchiolin "tiger flame" stripes running along the growth lines on the outer whorl; the newest shell at the aperture is still unpigmented. HEAD has nacre luster and fractures but no pigment.
- Tactic 6 (history): C is blended at 0.04 only; no history idea.

RESCUES (documented as rescues, not ideas)
- R1 upside-down camera: `uv.y` flipped (and `mouse_uv.y` flipped so the held-pointer pull still follows the cursor). HEAD scenes were upside-down.
- R2 unbounded slab: whorl tubes are clipped at an aperture `kMax = ln(2)/b` (end-face distance = arc length along the whorl, x0.8 for safety) and the whole map is bounded by a sphere of radius 2.9. HEAD at the default b was a flaring cone filling the frame; the camera sat ON its surface (r=4.47, y=2, tube radius up to 1.8-2.2) so the HEAD picture is "sand dunes", not a nautilus. Measured scratch: HEAD meanL 0.605 stdL 0.099 (flat sand) -> meanL 0.27 stdL 0.32 (shell on a dark sea).
- R3 Lipschitz-safe aperture lip: `mix(8.0, apertureLip, gate)` overestimated the distance in the gate ramp (up to 8x) and the march stepped THROUGH the thin shell producing black rings once the solid was bounded. The lip is now the same tube with its radius blended 0.4 -> 0.5 by the existing gate (same swelling, same gate), and it is clipped at the same aperture.
- R4 camera elevation 26 deg -> 42 deg (`ro = (0, 3.0, -3.3)`, same distance 4.46, same orbit): from 26 deg the spiral reads as concentric rings. Plus the hit test now rejects rays that ran out of steps (HEAD counted every ray with `d < MAX_DIST`, giving white speckle in the void), and the siphon jet is anchored at the actual aperture mouth instead of the fixed point (1.5, 0, 0).

ADD (3 ideas):
1. Beer–Lambert shell absorption (§12.2F "Fresnel–Schlick / Henyey–Greenstein / Beer–Lambert", Beer–Lambert term) — the transmitted terms (`envRefr*0.3 + glow`) are multiplied by `exp(-sigma * chord)` with `chord = 2 * 0.4 r * cos(theta_t)` (theta_t from `refrIndex` and `NdotV`) and `sigma = (1.8, 0.7, 0.25)`. Thick outer whorls go deep abyssal teal, the thin apex and the lip stay clear. Native: thick glass.
2. Conchiolin flame stripes (tactic 5) — dark indigo stripes along the growth lines of the outer whorls: `fract(N k)` with an integer N per turn (seam-safe), forked by a sine warp, strongest on the flanks (|y|/tube radius), fading toward the unpigmented aperture and toward the embraced inner whorls. Multiplies the iridescent surface term only, not the nacre/glow.
3. Siphon plume (tactic 1 on the existing "bioluminescent siphon jet") — HEAD's jet only sparkles on the shell skin within 0.5 of a fixed point. The plume is an analytic ray/segment closest-approach cone leaving the aperture mouth along the growth tangent, so it is visible against the void as well; billow from the existing voronoi. No loop, no extra map().

FORMULA ADMISSION: idea 1 is a §12.2F row on this file (glass -> Beer–Lambert); consumes `r`, `NdotV`, `refrIndex`, glow terms already in the colour sum; deletion leaves HEAD's colour sum. Idea 2 is not a §12.2 row (tactic 5), consumes `a`, `nf`, `r`, `p.y`. Idea 3 is not a row (analytic cone). 1 row used, row budget respected (the other two files in my fork use Golden-angle and Additive domain twist).
FORBID: springs, ripple fronts, IQ palette, new params, changing the saved defaults, rewriting the spiral map beyond the aperture/bound/lip rescue.
A PACKING: ACES display RGBA in A (unchanged).

---

## 2. SHADER: gen-radiant-chrono-glass-nautilus (chrono-glass spiral)

IDENTITY: a face-on, infinitely winding chrono-glass nautilus — alternating shell / plasma-interior / septum strips of one log spiral, a siphuncle plasma conduit, clockwork escapement ticking and a chamber-by-chamber plasma tide, in magenta/cyan glass.

KEEP VERBATIM: 4 params + roles (x spiral tightness -> arm winding, y plasma bloom -> glow gain, z glass refraction -> Fresnel exponent + lamellae separation, w audio reactivity -> shell breathing + tide speed); `spiral_a` structure (angle term + 2 ln r + ticking), the 3 strip SDFs and their ID mapping, septa + scallops, siphuncle + travelling pulse, `chamberTide`, glow accumulation, Fresnel shell/interior colours, birefringent lamellae, striae, shatter, mids/treble terms, alpha/depth, A = display RGBA; the mouse gravity-well rotation.

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): `spiral_a = a*tightness + ...` is not periodic in the angle `a` for any non-integer `1.5*tightness*TAU`, which is every slider value except a few. atan2's branch cut at the negative x axis therefore tears the spiral (seen at HEAD: a cut arc from the centre to the upper left). The kernel's real intent is "N interleaved arms"; N must be an integer.
- Tactic 2 (physics one step further): the escapement already ticks (`floor(t*4)` step + eased last 20%). A real anchor escapement does not land cleanly: the pallet drops, the wheel recoils and rings down. HEAD's tick is a perfectly damped step.
- Tactic 3 (promote an intermediate): `wallPhase` (distance in phase to a septum) and `septumThick` are computed in `map()`; the ratchet teeth only modulate the same thickness. `ticking` is a quantity `map()` already owns.
- Tactic 5 (artifact of the real organism): nautilus chambers are partly liquid-filled for buoyancy (cameral liquid); the free surface is flat and horizontal. HEAD's interior strips glow uniformly.
- Tactic 6 (history): HEAD does not read C. No history idea.

RESCUES
- R1 angular seam: the winding coefficient `a*tightness` becomes `a*arms/(1.5 TAU)` with `arms = max(round(1.5*tightness*TAU), 1)`, so the pattern is periodic in `a` (every other term already is). The slider still means winding density but is quantised to whole arms (the default 0.5 -> 4.71 -> 5 arms, +6% winding; the range 0.1..1 gives 1..9 arms). Visible effect: the cut arc is gone.
- R2 upside-down uv: `uv.y` flipped, and the gravity-well centre flipped in y so the cursor still pulls where it points (idle cursor 0.5,0.5 -> centre (0,0), unchanged). The swirl is the mirror image of HEAD.

ADD (3 ideas):
1. Escapement recoil ring-down (tactic 2) — `ticking` gains a damped overshoot after each beat: `recoil = exp(-9 f) * sin(32 f) * 0.12` with `f = fract(t*4)` measured from the beat, so each tick lands, rebounds and settles. Native to "clockwork escapement ticking"; replaces nothing (the step + ease stay).
2. Ratchet-toothed septa (tactic 3/5) — the septum thickness is modulated by an asymmetric saw tooth along the angle (integer 36 teeth per turn, seam-safe) that advances with the tick, so the septa read as escapement-wheel teeth engaging the pallet. Uses `septumThick`, `wallPhase`, `ticking`.
3. Cameral liquid level (tactic 5) — in the plasma-interior strips (ID 2) a flat horizontal free surface: below the per-chamber level the interior glows (`glow` gain unchanged), above it the chamber is gas and dims; a thin bright meniscus line at the level. Level = hash(`g_chamber`) with a slow breathing. If it reads as a scanline overlay in the renders it is dropped.

FORMULA ADMISSION: none of the three is a §12.2 row (the file is a generative nautilus; the nearest family rows do not fit). All consume quantities `map()`/`main()` already compute (ticking, septumThick, wallPhase, g_chamber, glow). 0 rows used.
FORBID: spring/ripple overlays, IQ palettes, replacing the spiral, new params, Cauchy (taken).
A PACKING: ACES display RGBA (unchanged).

---

## 3. SHADER: gen-symbiotic-chrono-mycelium-engine

IDENTITY: a vertical mycelial stalk threaded through a fractal-folded quantum gear, wrapped by a helical hypha, glowing magenta/cyan plasma, with the net lagging the gear's clock.

KEEP VERBATIM: 4 params + roles (x mycelial density -> fbm scale, y plasma glow -> glow gain, z temporal warp -> pos warp rate, w mouse influence -> pos offset); the 4-fold KIFS gear, the stalk `length(pos.xz) - 0.1 - noise*0.2`, the chrono lag (`u.config.x - 0.55`), the helical wrap `sdf_wrap`, the smooth_min union, plasma glow fbm, gear/mycelium colour mix, wrapLit, alpha/depth, A = display RGBA. The JSON has no top-level `params` (x-meta only) so the app feeds 0.5 x4; NOT adding params.

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): the stalk is a single noisy cylinder. A real mycelial cord is a bundle of strands that twists; `fbm(pos)` is the only structure on it, so the noise shows no direction of growth.
- Tactic 2 (physics one step further): a mycelium's defining organs after hyphae are fruiting bodies (primordia) which bud off the cord in phyllotactic order, and the cytoplasm streams along the cord in pulses. HEAD has neither.
- Tactic 3 (promote an intermediate): `lagTime` (the chrono lag) and `plasma_glow` are already per-pixel; the streaming pulse rides the same lag and the same `bass` the noise uses. `length(p.xz)` is the stalk-axis distance, already what the stalk SDF is made of.
- Tactic 6: C is unused (documented), stays unused.

RESCUES
- R1 upside-down uv: `uv.y` flipped, mouse y offset flipped for consistency (idle cursor: zero offset, unchanged). HEAD lit the gear from below (light (1,1,-1) with +y down the image).

ADD (3 ideas):
1. Golden-angle fruiting primordia (§12.2E "Golden-angle layout") — small buds on the stalk at azimuth `i*2.39996` and height `i*h`, found by domain repetition along y (2 nearest cells, two sphere SDFs, no loop), smooth-unioned with the stalk; radius swells with bass; pale warm cap colour via a `sdf_buds` mask like `wrapLit`.
2. Cytoplasmic streaming pulses (tactic 2) — bright pulses travelling outward from the gear along the stalk (`pow(0.5+0.5 sin(|y| k - t v), 6)`, phase from the chrono lagTime so the pulses trail the gear clock), masked to the stalk by `length(p.xz)`.
3. Rope twist on the stalk (§12.2E "Additive domain twist") — `pos.xz = rot(k*pos.y + lag)*pos.xz` before the existing fbm so the stalk's lumps spiral up the cord like a twisted rhizomorph; the stalk SDF and its radius are unchanged.

FORMULA ADMISSION: golden-angle row — family sentence: the buds are a dot field that now exists on a stalk, spaced phyllotactically; consumes the stalk axis and height; deletion leaves HEAD's stalk. Additive-twist row — "columns, towers, tendrils" is the stalk; applied before the existing map, deletion leaves HEAD's noise. Idea 2 is not a row. 2 rows used, each once in my fork (and nowhere else in my fork).
FORBID: new params, a new solver, replacing the gear, a spring on the mouse, IQ palette.
A PACKING: ACES display RGBA (C unused) (unchanged).
