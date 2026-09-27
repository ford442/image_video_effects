# NOTES — grok 2026-09-27 generative unused ten

## gen-radiant-cyber-bismuth-nebula-colossus

Kept the IFS fold, octahedron smooth-union, mouse orbit, click dolly, kaleido stars, and the four slider roles. Added hopper stair displacement on the octahedron (Iridiscent Shift), bass lip light (Audio Reactivity), and a `textureLoad` of C.a as nebula residue. Dropped the `extraBuffer` FFT tint; treble carries that haze. A.rgb is ACES display, A.a is raw nebula.

## gen-radiant-cyber-chrono-void-stag

Kept body/antler/core/hoof SDFs, mouse orbit, tine bifurcation, and segmented hoof packets. Added growth rings inside the existing antler loop and a leap-shifted C afterimage on miss and trail pixels.

## gen-radiant-cyber-plasma-astro-griffin

Kept warp, wing span, fractal depth, plasma glow, material ids, and the mouse twist. Feather cells are inset so slots open between them. Treble glints the beak-forward normal on material 3. Flap ghost is an exact C load, wings only. A changed from packed normals to ACES display RGBA because C was unread.

## gen-radiant-quantum-plasma-kraken-core

Kept eight arms, sucker rows, peristalsis, and mouse rotation. Siphon jet sits on the nearest arm when bass rises. Ink wake mixes a shifted C load on hits; Core Heat sets the stain.

## gen-raptor-mini

Kept the spring in `extraBuffer[133..138]`, ripple strikes, held pounce, scent `textureLoad`, and Gray-Scott as background energy. Added a three-streak rake gated by the existing strike, and a tail opposite the pursuit direction. ACES is on `writeTexture` only so the scent history in A stays pre-tone-map.

## gen-reaction-diffusion

File names stay `gen_reaction_diffusion.wgsl` / `.json`. Kept both solvers, mouse and click seeds, and the B slot-chain store. Refractory trough darkens the FHN band behind the front (Recovery). Gray-Scott feed stretches along the concentration gradient (Excitability). A remains raw sim state.

## gen-recursive-ancestral-terrains

Kept φ persistence, Koch–Sierpinski dimension, mouse lineage, and bass erosion. Generation Depth terraces height where the last octave disagrees with its parent. Valley silt reads previous height from C.a and Erosion drains it. A.a is raw height.

## gen-relay-psychedelia

Chunk order unchanged. Second curl octave lives in `applyDomainWarp`. Directional smear uses `textureLoad` in `applyTemporalFeedback` (Trail Echo sets reach). Complementary fringe is only in `applyPalette`. `main` only wires the seam scalar returned by `sampleField`.

## gen-resonant-crystal-canyons

Kept the three crystals, walls, floor, river, and mouse warp. River boil splits along the flow by Refractive Index, with a faint C reflection on the river only. Mids and treble add a harmonic to the existing crystal heights, scaled by Audio Reactivity. Alpha is no longer a constant 1.

## gen-resonant-quantum-obsidian-astro-manta

Kept orbit camera, ripple plate buckle, kaleido sea, and read-only FFT veins. A thin membrane trails the wing stroke (Evolution Speed). Existing ripple displacement etches hull cracks. Display tonemap is ACES. A.a is wing coverage and tints the shard sea from C.

## Gates

- `wgsl_precommit_gate.py`: 10/10 naga, 0 extraBuffer violations on these files
- `audit:extrabuffer`: pass (0 new writes into [0..132])
- `audit:dead-sliders`: 0 dead on all ten (reaction-diffusion stem is `gen_reaction_diffusion`)
- Catalog regenerate: 1,373 shaders, search index 1,373 embeddings reused
- `npm test` (craco): 107 suites, 764 passed, 1 skipped
- `SKIP_WASM_BUILD=1 npm run build`: compiled

`npx react-scripts test` without craco fails six WASM-bridge suites because `.js` specifiers are not mapped. That is the craco Jest mapper, not these shaders.

Real-GPU visual QA was not run. This VM has no WebGPU adapter.
