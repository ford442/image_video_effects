SHADER: gen-fractal-ember-lattice
IDENTITY: triangular/hex crystal lattice with white-hot ember edges over charcoal faces; mouse click shatters it into rigid square shards that fly out and reform (~1.5s), with treble sparks on shard edges.
KEEP VERBATIM: triLatticeDist3 kernel; 5-colour ember palette and hot-ramp mix chain; rigid shard grid + seed/reform state machine (explosion vector, per-shard rotation, 0.987 decay, reform rate); boundary glow, chromatic shard separation, motion streak, treble sparks; semantic alpha formula; CA + ACES + composite over input; slider roles (Glow Intensity, Shard Size px, Lattice Scale, Spark Density); saved params.
EXISTING IDEAS (2026-09-06):
  1. triple-junction glow (all three line families meet -> white-hot node, treble-lifted)
  2. cell-core heat (faces far from every line get a faint inner ember)
ADD:
  3. Heat crawl along lattice lines — bright ember beads travel along each of the three line families (per-line phase from floor() line index, per-family speed, bass-lifted, density follows Spark Density), fused into the edge mask; native because the lattice lines are the heat conductors this effect already draws, and triLatticeDist3 already gives per-family distance.
  4. Shard cooling and re-ignition — a flying shard's lattice glow cools toward deep red/charcoal in proportion to shatterAmt (staggered by the shard seed), and as reform crosses its final stretch a brief incandescent flash re-ignites that shard's edges and junctions; native because it reads the existing seed/reform state (a detached ember loses heat, a rejoined one flares) rather than adding a new field.
FORBID: spring cursor, u.ripples shockwaves, IQ cosine palette, conveyors, new extraBuffer state, dataTextureB, replacing the triangular lattice or the rigid-shard sim.
A PACKING: raw shard state (unchanged): A.rg = displacement, A.b = seed, A.a = reform; C read with exact textureLoad as those fields. Not tone-mapped.

## Notes
- Kept verbatim: triLatticeDist3 kernel, ember palette + hot-ramp chain, shard state machine (explosion/rotation/decay/reform), boundary glow, chromatic shard separation, motion streak, treble sparks, alpha formula, CA/ACES/composite, all four slider roles. Saved `params` byte-exact (only `features` + description changed in JSON).
- A packing: unchanged raw shard state (A.rg displacement, A.b seed, A.a reform), C read via exact `textureLoad(dataTextureC, coord, 0)`; no tone-map on stored fields.
- Idea locations (public/shaders/gen-fractal-ember-lattice.wgsl): Ideas 1–2 existing (~L158–164); Idea 4 cooling factor + reignite ~L172–177 (applied to `hot` L177 and junction glow L183); Idea 3 heat crawl ~L185–199 (Spark Density scales bead amplitude, bass speeds crawl); Idea 4 colour shift + re-ignition flash ~L201–203.
- Floor: already compliant (13 bindings, 16x16, plasmaBuffer[0].xyz audio, ACES on display, semantic alpha, depth write, A-only). Fixes: header normalized (single Upgraded 2026-09-13, full Ideas list, honest A packing); JSON features gained "audio-reactive" and "mouse-driven" (both true).
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations. No textureStore(dataTextureC. No GPU visual QA.
