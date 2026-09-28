# Notes — batch 1 of 2 (organic/optical mid-high ten)

All 5 files: `naga` clean and `python3 scripts/wgsl_precommit_gate.py` passed (5/5, 0 extraBuffer violations, 0 workgroup issues). JSON files parse valid. Saved `params` (ids/names/defaults/min/max/step) left byte-exact in all 5; only `updatedParams`/`features`/`feedbackPacking` were added or aligned.

## gen-bioluminescent-neural-lattice
- Kept verbatim: dual-voronoi SDF, camera flythrough, mouse warp, all 4 param roles.
- A packing: display RGBA, afterglow-blended (`max(current, decayed history)`); same value in `writeTexture` and `dataTextureA`.
- Ideas in diff: `voronoi_edges_id()` (new) → `fire_pulse` term in `map()` and `fire_glow` accumulation in `main()` (Idea 1); `textureLoad(dataTextureC, id, 0)` + `afterglow_decay`/`trailed` (Idea 2); `ambient * (1.0 + treble * 0.6)` (Idea 3).
- Plumbing fixed: real `plasmaBuffer[0].xyz` (was self-sampling `dataTextureC` as fake audio); `dataTextureA` now written; `writeDepthTexture` now written (was never called at all).
- Naga: clean.

## gen-biomechanical-hive
- Kept verbatim: hex-prism `map()`, core/wall material split, breathing/pulse mechanic, all 4 param roles, orbit camera.
- A packing: raw HDR display RGBA history (pre-ACES) in A/C, ACES only on `writeTexture` — documented in header and JSON `feedbackPacking`.
- Ideas in diff: `history`/`growthDecay`/`trailedColor` block before ACES (Idea 1); `vein_pattern`/`veins` term added to `d_organic` in `map()` (Idea 2); `nerveSeed`/`nerveFlicker` in the wall shading branch (Idea 3).
- Plumbing fixed: `dataTextureA`/`dataTextureC` wired for the first time (previously both dead).
- Naga: clean.

## gen-celestial-aether-seraphim-wings
- Kept verbatim: KIFS fold loop, flap oscillator, lift/stall model (C_L, stall smoothstep), all 4 param roles.
- A packing: display RGBA, unchanged (same value in `writeTexture`/`dataTextureA`).
- Ideas in diff: `alphaAOA_map`/`stallAmt`/`shedPhase`/`vortex` perturbation inside the fold loop in `map()` (Idea 1); `liftHueShift` term added to the iridescence `hue` calc in `main()` (Idea 2).
- Plumbing fixed: `textureSampleLevel` → `textureLoad` (exact) for `dataTextureC` history read; `writeDepthTexture` now writes real `t / max_t` depth (was hardcoded zero).
- Naga: clean.

## gen-crystalline-mandala-bloom
- Kept verbatim: kaleidoscope-on-image mechanic, petal/ring SDF layer, all 4 param roles, ripple bloom.
- A packing: raw HDR display RGBA history, unchanged.
- Ideas in diff: `segIndex`/`facetHash`/`facetOffset`/`kFaceted` before the image sample (Idea 1); `edgeProximity`/`facetSparkle` block after the existing star sparkle (Idea 2).
- Plumbing fixed: none required — already fully plumbed.
- Naga: clean.

## gen-cosmic-slime-mold
- Kept verbatim: 6-seed `veinStructure` SDF network, growth-pulse timing, mouse-feeding mechanic, all 4 param roles.
- A packing: exact HDR temporal history, unchanged.
- Ideas in diff: `hasGrowthMemory`/`growthMemory` read near the top of `main()`, `+ growthMemory * 0.01` added to `growth` inside the vein loop, `matureGlow` block in the vein loop (Idea 1+2 combined mechanism), single-writer update block (`global_id.x == 0u && global_id.y == 0u`) at the end of `main()` writing `extraBuffer[133]`.
- Plumbing fixed: removed a shadowed duplicate top-level `"params"` JSON key (hyphenated `color-shift`, dead — the real one is the second `"params"` array with `color_shift`, left untouched).
- Naga: clean.
