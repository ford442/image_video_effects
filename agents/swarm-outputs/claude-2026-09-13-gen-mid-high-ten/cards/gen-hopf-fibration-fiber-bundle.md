SHADER: gen-hopf-fibration-fiber-bundle
IDENTITY: 40 Hopf fibers (great circles of S3 over sampled S2 base points) stereographically projected and 4D-rotated into glowing, hue-by-base-point linked loops with crossing bloom, treble specks and click phase-fronts.
KEEP VERBATIM: Hopf lift (z1r/z2r/z2i, psi fiber phase), stereographic projection + rz rotation, 40x32 segment distance loop, hsv hue from (phi, theta), params rotation_4d / fiber_thickness / crossing_bloom / particle_drift and their roles, crossingInt bloom, treble drift specks, click phase-front blooms, A/C display-RGBA feedback blend, alpha formula (alphaAcc*crossing*maxDepth).
EXISTING IDEAS: none (2026-06-06 header had no Ideas: line).
ADD:
  1. Knot-diagram over/under gaps — the nearest fiber at each pixel cuts a dark gap in the strands behind it, so the pairwise LINKING of Hopf circles (the defining topological fact) becomes readable instead of an additive tangle.
  2. U(1) fiber-phase beads — a bright bead travels around each circle at its psi phase (speed = Particle Drift, brightness pumped by bass), visualizing the circle group action that defines each fiber.
  3. Base-space S2 inset — a small orthographic sphere in the lower-left showing the 40 base points in their fiber hues, rotating with 4D Rotation and steered by the pointer, making the projection S3 -> S2 of the bundle explicit.
FORBID: spring cursor, extraBuffer state, IQ cosine palette, new ripple shockwaves beyond the existing click fronts, conveyors, replacing the Hopf lift or projection.
A PACKING: ACES display RGBA (unchanged; C read via exact textureLoad as display history).

## Notes
- Kept verbatim: Hopf lift, stereographic projection, rz 4D rotation, 40x32 segment loop, hue mapping (hoisted out of the inner loop, same values), crossingInt bloom, treble specks, click phase-fronts, C blend, alpha formula, all four param roles. Params byte-exact.
- A packing: ACES display RGBA in writeTexture and dataTextureA; C read via textureLoad(dataTextureC, coord, 0).
- Idea 1 (over/under gaps): WGSL lines 84-89 (slots), 182-195 (front selection + gap cut; gap depth scales with Crossing Bloom).
- Idea 2 (U(1) beads): line 164-167 (speed from Particle Drift, brightness from bass).
- Idea 3 (S2 inset): lines 90-98 (placement), 119-131 (base-point dots, rotated by rot4D, pointer via s2phi/s2theta), 197-207 (limb + alpha/depth coverage).
- Floor fixes: guarded z1r (max 0.001) and depth4 denominator (max 0.05) against div-by-zero; JSON gained "upgraded-rgba"; header Upgraded 2026-09-13 + Ideas/A packing lines. Audio already plasmaBuffer[0].xyz, ACES/alpha/depth/A already correct.
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations; plasmaBuffer[ count 3; no textureStore(dataTextureC).
- Real-GPU visual QA: external.
