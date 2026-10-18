# Cursor batch-03 — notes

2026-10-17. Idea cards were written before the WGSL edits (`BRIEFS.md`).

## rd-on-video-pass1

Kept: Gray-Scott feed/kill/diffusion/dt, 5-point laplacian, luma seed and memory, hover inoculation, click fronts. A stays `(U, V, luma memory, reaction activity)`. B is not written. ACES is only on the preview.
Added: contour stretch (V diffuses along the stored-luma tangent); spot fission (central kill where V is high and `|laplacian V|` is small).
Prelude migrated this pass.

## rd-on-video-pass2

Kept: four-stop palette, pattern gamma, edge gain, seed gain, hue shift. B stores pre-ACES palette rgb + pattern. Does not write A.
Added: isochrone threads at pattern 0.33 and 0.66; substrate core (depleted U cools the interior of a high-V spot). Display ACES is on `writeTexture` only.
Prelude migrated this pass.

## rd-on-video-pass3

Kept: luma gate, mask softness, glow, blend. Does not write A.
Added: dye take-up (overlay leans into the video color where the pattern is dense); gate meniscus (hairline on the luma threshold).
C is exact `textureLoad`. Feedback copies B then A, and A wins, so C is pass 1's chemistry, not pass 2's palette. The composite stains that chemistry over the video.
Prelude migrated this pass.

## liquid-optimized-pass1

Kept: laplacian/biharmonic split, meniscus, click packets, three ambient sines. A stays `(h_prev, h_curr, velocity, age)`. Heights are not tone-mapped.
Added: seiche beat (slow envelope on the ambient ripples); shore set-down (velocity-squared drop on the depth contact band).
Turbidity (default 0) multiplies damping and shortens click packets so that slider is live on this pass. At 0 the previous damping is unchanged.

## liquid-optimized-pass2

Kept: height normal, Schlick Fresnel, per-channel Beer absorption, turbidity. Does not write A.
Added: Snell offset of the photo along the normal; velocity glint (spec power falls as `|velocity|` rises, plus a tangent sheen).
Gravity and damping now scale normal exaggeration and spec power. At the saved default 0.5 both match the old constants (height scale 1, spec power 128). Display is ACES RGBA. Alpha is liquid coverage over the photo alpha, not a hardcoded 1.

## gen-tectonic-plasma-crucible

Kept: Voronoi slabs, isostatic bob, bass rift, incandescent crack ramp, eruption spikes, heat haze, display-history A.
Added: pillow rind on the thermal margin; strike-slip striae along the slip direction, denser with tectonic stress.
Prelude migrated this pass. Prior ideas kept.

## gen-luminescent-chrono-fluid-astrolabe

Kept: limb graduations, gear train, almucantars, azimuths, stars, ecliptic, sun bead, alidade rule, existing spring, display-history A.
Added: unequal-hour arcs on the rete; alidade shadow offset from the rule (the rule stays bright, the chart under it darkens).
Prior ideas kept. No new spring.

## gen-navier-stokes-ink

Kept: semi-Lagrangian back-trace, viscosity mix, divergence clear, Fedkiw confinement, Boussinesq sink, click drops, vortex tubes, corona. A stays `(vx, vy, ink, coverage)`. ACES is display-only.
Added: Marangoni skim (velocity pushed against the ink gradient); coffee-ring rim where the ink edge is steep and the fill is still moderate.
Prelude migrated this pass.

## gen-magnetic-ferrofluid

Kept: Rosensweig lattice, labyrinth mix while held, Rayleigh l=2/l=3, softbox, droplet smooth-min, spring orbit, display-history A.
Added: secondary peak bifurcation (hex peaks pair up once the field is well above critical); magnetite chains (dark field-aligned streaks on the shaded surface).
Prior ideas kept.

## gen-auroral-ferrofluid-monolith

Kept: spike SDF, sheath, co-wound field, tip corona, cusp-knot whorls, substorm curtains, display A.
Added: stable red arc at `|y| = 2.35`; black-aurora lanes that cut the curtain and the substorm bands.
Prior ideas kept.

## Floor

Prelude include on all ten (five migrated this batch). 16×16. Exact C loads where this batch touched a filtering sample of C (pass 3). Saved `params` byte-exact; `x-meta.upgrade.params` added where the definition had no upgrade block. A packing as documented above.

## Gates

Naga 10/10. Precommit 10/10. extraBuffer pass. Dead sliders pass (the two defs that only store sliders under `x-meta.upgrade.params` are not in that audit's param scan; both shaders already read all four `zoom_params`). Catalogs regenerated, no duplicate ids.

Jest 159 suites, 1332 passed, 1 skipped. `SKIP_WASM_BUILD=1` build compiled. Ledger recorded with `--ids` for these ten.

Real-GPU visual QA: external.
