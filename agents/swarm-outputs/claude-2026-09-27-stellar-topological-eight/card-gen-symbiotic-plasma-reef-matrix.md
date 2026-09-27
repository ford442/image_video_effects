SHADER: gen-symbiotic-plasma-reef-matrix
IDENTITY: raymarched underwater reef — fbm seabed, tapered smin coral capsules, 8 orbiting glow entities that flee the mouse, violet->pink coral / cyan-green entity palette, caustic backdrop, orbiting camera.
KEEP VERBATIM: terrain + coralBranch SDF + smin, entity orbit/flee formulas, palettes, raymarch step count (80) and 0.7 step scale, camera, mouse mapping (no Y change), fog/ACES/temporal-persistence structure, depth write, 4 params with labels/roles, updatedParams byte-exact.
ADD:
  1. Symbiotic dock-and-pulse (IDEA 1) — the coral loop remembers its nearest branch axis; the existing entity loop (one extra length per entity, no per-branch entity loop) measures how close the nearest entity is to that axis. Near enough = the branch flares (cyan-green, the entity palette) and a light pulse climbs it from base to tip. Stateless, native to the entity/coral pair.
  2. Caustic dapples by height (IDEA 2) — sun-net caustic pattern projected on terrain/coral in world XZ, weighted by height (brighter shallows/tips, dim seabed) and up-facing normals; the backdrop already has caustics, this carries them onto the reef.
  3. (wiring, not an idea) Reef Density slider = coral branch count 3..9, exactly 5 at the saved default 0.5.
FORBID: replacing entities with particles, springs, ripples, extraBuffer state, more raymarch steps.
A PACKING: display RGBA (ACES colour, alpha = hit/glow coverage); dataTextureA matches writeTexture and is read back by C as colour.
KNOWN BUGS FIXED: (a) sampler read of dataTextureC -> textureLoad exact; (b) hard-coded alpha 1.0 -> semantic alpha; (c) dead Reef Density slider wired.
