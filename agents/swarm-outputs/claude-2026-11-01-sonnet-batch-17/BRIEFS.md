# Sonnet batch 17 — kaleidoscope and prism ten — Idea Cards (written before any WGSL edit)

Batch: `claude-2026-11-01-sonnet-batch-17` · 2026-11-01 · explicit list from the task (sonnet/batch-17): astral-kaleidoscope, astral-kaleidoscope-gemini,
astral-kaleidoscope-grokcf1, astral-kaleidoscope-julia, astral-kaleidoscope-morph, kaleidoscope, prismatic-mosaic, prism-displacement, liquid-prism, spec-prismatic-dispersion.
Theme: optical (mirrors, prisms, glass). Ideas are therefore device-native: what a kaleidoscope's mirrors / eyepiece / object chamber do, and what glass does to light.
None is multipass; none starts with `_`. Ledger: prismatic-mosaic and prism-displacement upgraded 2026-10-04 (second passes); the other eight have no event.
HEAD `Ideas:` lines are NOT re-added. All ten paste the 13 bindings (nine migrate with `migrate_to_prelude.py`; `astral-kaleidoscope-morph` is refused by the tool and is hand-migrated, see finding 1).
Pre-state: naga-wasm 10/10 valid on main.

## Findings that shape the cards

1. **astral-kaleidoscope-morph is wired wrongly, not just old.** It declares `struct Uniforms` with `zoom_params` BEFORE `zoom_config` (engine layout: config, zoom_config, zoom_params) and renames bindings (`videoTex`, `outTex`, `historyBuf`, `historyTex`, `depthTex`…). `migrate_to_prelude.py` refuses it by design ("struct-field-order … needs its own reviewed change"). Consequence at HEAD: its `u.zoom_params.*` reads engine time / mouse, so **segments = 3 + 12·time (grows without bound)**, rotation = mouse x, morph blend = mouse y, trails = mouse-down; and its four saved sliders (segments, rotation speed, morph blend, trail persistence) drive hue shift, aberration, centre oscillation and pulse power instead. Repair (hand migration, own change): canonical prelude, sliders read from `zoom_params` in their saved roles, and the four reads that were never sliders (hue shift, aberration, centre osc, pulse power) become the old slider midpoints, the same remedy applied earlier to `chromatic-crawler` / `chromatic-folds-2`.
2. **astral-kaleidoscope-julia** uses `u.zoom_config.x` (engine **time**) as its fractal zoom: `zoom = mix(1.5, 4.0, time)` extrapolates without bound, so the Julia set shrinks to a dot within seconds. (`morphSpeed`, `colorCycles`, `detail` read mouse x / mouse y / mouse-down: bounded, left.) Repair: zoom = the old midpoint 2.75.
3. **Seam at non-integer segment counts** (astral ×4, kaleidoscope): the segment count is a continuous slider but a mirror fan only closes for an integer count; otherwise a fixed seam shows along the atan2 branch cut. Defaults are integer in the five astral files (9) but **`kaleidoscope` defaults to 4.8** and its alternating-parity cells need an EVEN count. Repair: round the count (any integer for the astral wedge-fold, an even integer for the rose kaleidoscope: default 4.8 → 4).
4. **Per-band "FFT" reads zeros** in `kaleidoscope` (`plasmaBuffer[segBandIdx+1]`) and `liquid-prism` (`plasmaBuffer[bandIdx+1]`): the engine only writes `plasmaBuffer[0]`; real FFT bins are `extraBuffer[5+bin]`. Repair via a guarded `fftBand()`.
5. **spec-prismatic-dispersion's spectral reconstruction has a strong red cast.** I computed it for a white input at default sliders: output (2.30, 0.74, 0.59) before ACES (R:G:B 3.1 : 1 : 0.8). prism-displacement fixed the same flaw in 2026-10-04 ("white stays white"); this file never got that.
6. gemini/grokcf1 `feedback = max(color, prev·decay + shimmer)` has a veil floor of shimmer/(1−decay) (≈0.38 luminance at default trails, more at max). Flagged, not changed: it is how the trail looks.
7. astral/gemini/grokcf1 read C with a (non-filtering) `textureSampleLevel`; changed to exact `textureLoad` (plumbing).
8. Tone curves: all use ACES already (astral-julia, spec-prismatic, etc.); no tone-map change.

---

## SHADER: astral-kaleidoscope
IDENTITY: depth-parallax kaleidoscope fold of the photo with spiral twist, chromatic split, hue ripple, light-trail history.
KEEP VERBATIM: 4 params (segments, rotation speed, spiral strength, trail persistence); fold maths; depth parallax; chroma rotation; HSL grade; `max(color, prev·decay)` trails; HEAD's pointer-anchored centre, seam glint, click-front overlay; A = pre-ACES feedback + 1.0.
MECHANISM INTERROGATION: tactic 2 — each reflection in a real mirror loses energy and picks up the silvering's tint; this fold treats the image of every wedge as the original. Tactic 2/5 — real scopes have an end cap, which makes the tunnel of reflections; here the pattern just stops.
ADD:
1. Mirror reflectivity per bounce — the wedge index gives the number of reflections the sample took (min(k, N−k)); colour × ρ^bounces with ρ = (0.945, 0.955, 0.96), a faint silvered fall-off toward the far wedges.
2. End-cap tunnel ghost — beyond a cap radius (0.45, bass-breathing) a second tap samples the radius reflected about the cap (2·R_cap − r), blended up to 45 %, a ring of end-mirror reflection.
REPAIR/floor: segment count rounded to an integer (default 9 unchanged); exact `textureLoad` of C.
FORBID: springs, new overlays, IQ palettes, new params.
A PACKING: unchanged — pre-ACES feedback colour in A (read as C colour), ACES on writeTexture.

## SHADER: astral-kaleidoscope-gemini
IDENTITY: the astral kaleidoscope with a noise warp field that bass swells and a held pointer that becomes a second warp epicentre.
KEEP VERBATIM: everything in HEAD incl. warp swell, pointer epicentre, shimmer in the feedback.
MECHANISM INTERROGATION: tactic 5 — a kaleidoscope is seen through a round eyepiece; the frame has no field stop and no cos⁴ fall-off. Tactic 2 — the object chamber is out of focus away from the eye's axis.
ADD:
1. Eyepiece field stop with cos⁴ fall-off — brightness × 1/(1+(ρ/0.55)²)² (cos⁴θ with ρ = aspect-corrected distance from frame centre), plus a soft circular stop at ρ ≈ 0.62 that dims to 0.35 outside (§12.2A cos⁴ vignetting).
2. Object-chamber defocus — four extra taps (±radial, ±tangential in the folded space) average into the sample, growing with r², so the rim of the field is softer than the centre.
REPAIR/floor: integer segment count; exact `textureLoad` of C.
FORBID: springs, new warps, palettes.
A PACKING: unchanged — pre-ACES feedback in A.

## SHADER: astral-kaleidoscope-grokcf1
IDENTITY: the astral kaleidoscope where bass/mids torque the spin and a held pointer grabs the spiral toward the cursor angle.
KEEP VERBATIM: everything in HEAD (bass/mids torque, grab spiral, warp, shimmer).
MECHANISM INTERROGATION: tactic 2 — a kaleidoscope's loose objects tumble in a chamber that turns independently of the mirrors; HEAD has one object layer. Tactic 1 — spiral is linear in r (Archimedean); the self-similar kaleidoscope spiral is logarithmic.
ADD:
1. Second object chamber — a second tap through the same fold with a counter-rotating angle (−0.7 × the spin + a fixed offset), screen-blended at 50 %, a counter-turning set of objects.
2. Log-spiral twist term — `0.12·spiralStr·ln(r + 0.05)·sin(0.2t + 1)` added to the angle, so the spiral arms are self-similar toward the centre.
REPAIR/floor: integer segment count; exact `textureLoad` of C.
FORBID: springs, new torque engine, palettes.
A PACKING: unchanged.

## SHADER: astral-kaleidoscope-julia
IDENTITY: a 4-D quaternion Julia set ray-marched through a kaleidoscope-folded view, with chromatic separation on the background.
KEEP VERBATIM: 4 params (segments, rotation, spiral, aberration); fold; Julia DE and marching; mouse orbit; chroma on background; A raw colour + alpha.
MECHANISM INTERROGATION: tactic 3 — the surface normal `n` and view `rd` are computed but the photo is only a background; a glossy fractal would reflect it. Tactic 5 — the fold mirrors the rendered view but shows no mirror gap.
ADD:
1. Photo-mapped Schlick reflection — reflect `rd` about the Julia normal and look the photo up at 0.5 + refl.xy·0.5; weighted by Schlick Fresnel (F0 0.04) and added to the hit colour (§12.2F Fresnel–Schlick).
2. Mirror-gap seam — the fold's distance to its seam (min(a, seg/2 − a)) darkens a thin line (to 40 %) with a bright bevel just beside it, on both hit and background.
REPAIR/floor: **zoom was engine time** → 2.75 (old midpoint); integer segments; gate `kUV`; nothing else changed.
FORBID: springs, new params, replacing the DE.
A PACKING: unchanged — raw colour + alpha in A (no reader), ACES on writeTexture.

## SHADER: astral-kaleidoscope-morph
IDENTITY: the astral kaleidoscope followed by morphological erosion/dilation, gradient halo and top-hat sparkle.
KEEP VERBATIM: fold; chroma; HSL grade; disc structuring element (erosion/dilation/gradient/top-hat); trails; top-hat alpha; the four saved sliders as named (segments, rotation speed, morph blend, trail persistence).
MECHANISM INTERROGATION: tactic 7 — morphology here uses a disc; the picture's own structure (the mirror fan) is radial, so a line element along the radial direction is the natural oriented kernel. Tactic 3 — the morphological gradient is computed and used only as a glow; a real lens shows lateral CA only where the gradient is strong.
ADD:
1. Radial line structuring element — a 7-tap line dilation along the radial direction of the folded sample, blended by Morph Blend, which streaks bright edges along the mirrors.
2. Gradient-driven lateral chroma — R and B retaps displaced along the radial direction by an amount proportional to the morphological gradient luma (≤ 0.02 uv), so fringing sits on edges.
REPAIR (own change, finding 1): hand migration to `_prelude.wgsl` with canonical names; uniform reads corrected so the saved sliders drive their roles; the four non-slider reads (hue shift, aberration, centre osc, pulse power) become midpoint constants (hueShift 1.0 as in the siblings, aberration 0.01, centreOsc 0.075, pulsePower 0.75); history via exact `textureLoad`.
FORBID: springs, palettes, new params.
A PACKING: unchanged — feedback colour + luma in A, display = linear (HEAD wrote no ACES; ACES added on display as plumbing, A stays pre-ACES).

## SHADER: kaleidoscope
IDENTITY: rose-petal FBM kaleidoscope with a steerable mirror pivot, per-segment FFT bands, squircle aperture, hypocycloid frame, Gabor interiors.
KEEP VERBATIM: 4 params; spring pivot in extraBuffer[133..134]; rose segments; FBM distortion; epicycloid wobble; superellipse mask; Gabor; hypocycloid frame; click shockwaves; persistence; ACES; A = display RGBA.
MECHANISM INTERROGATION: tactic 2 — an aperture diffracts: bright and dark fringes run just inside its edge, which differ by wavelength. Tactic 1 — the per-segment RGB split is a fixed ±δ; glass disperses by Cauchy's law (blue bends 1.75× as far as red).
ADD:
1. Aperture diffraction fringes — a superellipse value `e` (0 at centre, 1 at the edge) gives three-wavelength cosine fringes in 0.7 < e < 1, phase offset per channel (§12.2F Airy/diffraction), added inside the aperture.
2. Cauchy-weighted channel split — R shifts by +0.57 δ and B by −1.0 δ instead of ±δ (n(λ)−n(550) ∝ 550²/λ² − 1 gives −0.28 : +0.49).
REPAIR/floor: per-segment FFT band read from real bins (`fftBand`); even integer segment count (default 4.8 → 4; HEAD had a seam).
FORBID: new springs, palettes, new params.
A PACKING: unchanged — display RGBA.

## SHADER: prismatic-mosaic
IDENTITY: five zooming layers cut into prism tiles that split colour, with depth-edge glints, cursor vortex and volumetric fog.
KEEP VERBATIM: everything in HEAD (tile prisms, Sobel depth glint, layer windows, vortex, fog, ACES, C blend).
MECHANISM INTERROGATION: tactic 5 — a prism facet also catches specular glints, but tiles here are flat. Tactic 1 — each tile's R/B split is ±1 along its axis; Cauchy's law is asymmetric.
ADD:
1. Facet specular glints — each tile gets a hashed tilt normal; a light that sweeps with time lights Blinn glints on tiles whose normal aligns with the half-vector (pow 64), gated by treble.
2. Cauchy-weighted tile split — R +0.57, B −1.0 along the tile axis (HEAD ±1), so the fringe is bluer on one side like real glass.
FORBID: springs, new params, replacing the tiling.
A PACKING: unchanged — ACES display RGBA.

## SHADER: prism-displacement
IDENTITY: a prism lens at the cursor: white-balanced 7-tap spectral dispersion with a Cauchy fan, an anamorphic axis and a Fresnel rim.
KEEP VERBATIM: everything in HEAD.
MECHANISM INTERROGATION: tactic 2 — glass absorbs (Beer–Lambert): a dome is thicker at its centre, so it tints the centre and passes the rim; HEAD's glass is perfectly clear. Tactic 4 — the dispersion offset has constant magnitude; lateral CA grows with distance from the optical axis.
ADD:
1. Beer–Lambert dome absorption — thickness 2·R·cosθ (cosV, already computed for the rim), transmittance exp(−(0.55, 0.20, 0.14)·thickness), applied inside the lens (§12.2F Beer–Lambert).
2. Radial lateral CA — the dispersion scale × (0.3 + 1.4·clamp(r / R_lens, 0, 1.5)), so the fringe is weak on-axis and strong toward the rim.
FORBID: springs, new params, replacing the fan.
A PACKING: unchanged — ACES display RGBA.

## SHADER: liquid-prism
IDENTITY: ripple glass with Cauchy dispersion, bounded click caustic fronts, afterglow persistence, spring cursor.
KEEP VERBATIM: everything in HEAD (spring cursor, ripples, Cauchy offsets, highlight, caustic fronts, persistence, alpha); param double role of Aberration.
MECHANISM INTERROGATION: tactic 3 — the displacement map is `dir · A(r)`; its Jacobian is free (A', A/r) and light concentrates where its determinant → 0, which is what a caustic IS. Tactic 2 — steep ripple faces beyond the critical angle show total internal reflection, not refraction.
ADD:
1. Caustic focusing from the refraction Jacobian — det = (1 + A′)(1 + A/r) from the analytic radial ripple; brightness × mix(1, clamp(1/(|det| + 0.25), 0.6, 2.0), 0.6) (§12.2F Snell-driven focusing).
2. Total internal reflection flash — where the surface normal's z falls below cos(asin(1/n)) the sample is replaced by a mirrored tap (uv − n.xy·0.12), lifted slightly, weight by a soft step (§12.2F Snell / critical angle).
REPAIR: per-band read `plasmaBuffer[band+1]` (always 0) → real FFT bin.
FORBID: new springs, new ripple system, palettes.
A PACKING: unchanged — display RGBA.

## SHADER: spec-prismatic-dispersion
IDENTITY: 4-band Cauchy spectral dispersion through a mouse-centred glass lens, with caustic rings, an AR-coating sheen, astigmatic streaks and a glow.
KEEP VERBATIM: everything in HEAD (spring cursor, bands, refractThroughSurface, caustic rings, AR sheen, streaks, glow, C blend).
MECHANISM INTERROGATION: tactic 8 — the reconstruction Σ w·(w·sample) is not energy-neutral (finding 5). Tactic 2 — the AR coating exists to suppress internal-reflection ghosts, which the file never draws.
ADD:
1. White-balanced spectral reconstruction — each channel is normalised by Σ w_c·Σ(w) (the response to white without absorption), so a white input stays white while the absorption still tints by thickness (energy accounting, the fix prism-displacement got).
2. AR-tinted internal-reflection ghost — a dim copy of the bright (> 0.62) highlights sampled at the point reflected through the lens centre (× 0.35), tinted by the coating's purple/amber, as lens-flare ghosts are.
FORBID: new springs, palettes, new params.
A PACKING: unchanged — ACES display RGBA.

---

## Formula / mechanism ledger (≤ 2 files per §12.2 row)

| row / mechanism | files |
|---|---|
| F Cauchy dispersion weighting | kaleidoscope, prismatic-mosaic |
| F Fresnel–Schlick | astral-kaleidoscope-julia |
| F Beer–Lambert | prism-displacement |
| F Snell / critical angle | liquid-prism |
| F diffraction (Airy-like fringes) | kaleidoscope |
| A cos⁴ vignetting | astral-kaleidoscope-gemini |
| mirror reflectivity per bounce | astral-kaleidoscope |
| oriented morphological SE | astral-kaleidoscope-morph |
| none (tactic-derived) | astral-kaleidoscope-grokcf1, spec-prismatic-dispersion (energy accounting), the rest |
