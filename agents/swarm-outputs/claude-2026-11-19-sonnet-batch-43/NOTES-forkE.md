# NOTES — fork E (gen-ethereal-quantum-medusa, cosmic-web-structure)

## gen-ethereal-quantum-medusa (second pass)
SHADER: gen-ethereal-quantum-medusa
IDENTITY: raymarched bioluminescent jellyfish — bell + tentacles, chromatic core→tip, stingers, canals, feedback glow
KEEP VERBATIM: all four sliders/roles, bell contraction wave, peristaltic column pulse, stingers, radial canals, click rings, A/C packing
ADD:
  1. 8 helical marginal tentacles from the bell rim — uses the 8-fold sector index HEAD computed but never used; curl slider twists them, peristaltic swell rides them (`marginalTentacles`)
  2. mesoglea translucency — one inner-field probe `map(p - n*0.22)`; thin jelly glows with bass×Quantum Glow
FORBID: new creature, IQ palette, springs
A PACKING: ACES display RGBA (unchanged)
RESCUES (HEAD was effectively blank — meanL 0.028, a few cyan streaks):
  - upside-down: texel y downward → tentacles hung off the top; uv.y flipped, mouse y flipped to match (comment "screen-top = +Y" now true)
  - 1/r² mouse well with normalize at r→0 sits on the medusa at default pointer and shredded the SDF → bounded Gaussian displacement
  - central column rotated in xy (an infinite cylinder tipped sideways → screen-wide streaks) → twisted about its own axis, offset 0.14 (spiral oral arm), capped below bell
  - framing: bell was ~20% of height → camera (0,-0.9,-4.6); march step ×0.6 (twisted field), march far 11 (depth still /MAX_DIST)
TIMING: vs HEAD ~2–4× (HEAD rays escaped an empty frame; not a fair baseline). frameMs 147 vs HEAD-with-repulsion-0 75–111 at 192px. Coordinator: re-time; candidate trim = MAX_STEPS 100→72.

## cosmic-web-structure (first pass)
SHADER: cosmic-web-structure
IDENTITY: Voronoi dark-matter filaments over the image, LIC-streaked along structure-tensor flow, mouse gravity well
KEEP VERBATIM: fbm-warped voronoi3, structure tensor + coherency, LIC, palette by flow angle, ripple turbulence, params byte-exact
ADD:
  1. cluster knots where three cells meet (F3−F1 from `voronoi3n`), mids-scaled, treble sparkle
  2. LIC follows true filament tangent = perp(∇border), 2 extra voronoi3 lookups
  3. void redshift — interiors far from walls cool to dim red, walls blue-shift
A PACKING: ACES display RGBA, alpha = web coverage (max(webDensity, knot))
RESCUES: "filament direction" was literally dirToMouse; ripple age compared speed-scaled `time*0.5` against absolute ripple.z (rings never/oddly fired) → `config.x - ripple.z`; no A write, no audio, no tonemap.
Plumbing: bass → density, plasmaBuffer[0].xyz; JSON description rewritten, features + x-meta.upgrade.params.
Brightness: meanL 0.25 → 0.31 at 192 (ACES ×0.8).
TIMING: interleaved 4 rounds 0.99/0.75/1.08/1.45 → median ≈1.04 (load 42, noisy).

## Gates
precommit 2/2 pass, naga-wasm 2/2 valid, dead-sliders PASS, extrabuffer PASS. Not committed; generated lists untouched.
