SHADER: gen-fractured-monolith
IDENTITY: a tall dark slab, cell-fractured into drifting/rotating shards, levitating and bobbing over a wavy liquid floor, with cyan light accumulating in the cracks; mouse orbits the camera.
KEEP VERBATIM: raymarch (120 steps, t*0.8, 30.0 far), map() SDF (sdPlane floor + wave, sdBox 1.5x4x1.5 base, 1.5 cell grid, hash drift * spread, per-cell rotation, crackNoise carve), crack glow accumulation, mouse camera orbit, floor fake reflection, sky gradient, vignette, C max-feedback (previous*0.82), ACES display packing, param roles (x spread, y levitation speed, z glow, w rotation speed).
EXISTING IDEAS: 1. per-shard identity tint; 2. fracture-plane glints.
ADD:
  3. Seam light pool on the liquid — the crack light leaks down onto the floor beneath the monolith as a pool patterned by the same rotated 1.5 cell grid (bright seams, dark shard shadows), brighter as the bob brings the slab toward the water and wider as Fracture Spread opens the gaps — native because the glow is literally the light escaping through this slab's fractures onto this scene's liquid sea.
  4. Rising seam pulse — a bass-lifted energy band that climbs the monolith's local Y axis and boosts the crack-glow accumulation only where it passes, paced by Levitation Speed — native because it is the existing inner crack light (description: "pulse with an inner, ethereal light"), animated along the slab's own height, not a new overlay.
FORBID: springs, click ripple shockwaves, IQ cosine palettes, conveyors, extra raymarch/shadow inner loops, new materials or a different monolith shape, dataTextureB.
A PACKING: ACES display RGBA (unchanged; C read via exact textureLoad as color history).

## Notes
- Kept verbatim: raymarch loop/limits, map() SDF (floor wave, base box, 1.5 cell fracture, drift, per-cell rotation, crack carve), crack glow formula (now multiplied by pulse factor), mouse orbit camera, floor reflection, Ideas 1–2, vignette, C max-feedback, ACES, alpha/depth, all param roles. JSON `params`/`updatedParams` byte-exact.
- A packing: ACES display RGBA in A and writeTexture; C read with exact `textureLoad` as color history (unchanged).
- Idea locations (public/shaders/gen-fractured-monolith.wgsl): Idea 3 seam light pool L246–263 (floor branch of main; Fracture Spread widens footprint/seams, Glow Intensity scales, bob/Rotation Speed shape it, treble lifts); Idea 4 rising seam pulse L153–158 (map() glow; Levitation Speed paces it, bass brightens). Ideas 1–2 L267–274.
- Floor fixes: standard 9-line banner (Features/Upgraded/Ideas/A packing); renamed noise() local `u` that shadowed the `u` uniform to `w`; `var` -> `let` for immutable locals. Audio already plasmaBuffer[0].xyz, alpha semantic, depth written, no extraBuffer/dataTextureB use. JSON features gained "audio-reactive", "mouse-driven" (mouse orbits camera); description refreshed.
- Perf: no new loops; pool is ~15 scalar ops on floor hits only, pulse is 3 ops per map() call.
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations. No `textureStore(dataTextureC`. No GPU visual QA.
