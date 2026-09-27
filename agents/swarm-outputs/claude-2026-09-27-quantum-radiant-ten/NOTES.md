# NOTES — claude-2026-09-27-quantum-radiant-ten

Cards: `BRIEFS.md`. Nothing in this batch uses extraBuffer. No springs. No new B usage. Saved `params` and
`updatedParams` are unchanged. Where a JSON had only `updatedParams`, a mirrored `params` block was added
(snake_case ids, `zoom_params.x..w`), so the dead-slider audit now scans all 10 (it scanned 0 for 6 of them before).

| Shader | Kept verbatim | Ideas in the diff (grep) | A packing | Floor fixed |
|---|---|---|---|---|
| liquid-metal-chronosphere | capillary modes, differential bands, held well, click rings, 4 params | `Idea 3: Rayleigh–Plateau` (bead/neck on `pull`); `Idea 4: chrono echo shells` (radially contracted `textureLoad(dataTextureC)`, void only) | ACES display RGBA; C read as echo | — |
| mycelial-neural-web | fibre SDF, entanglement twist, attractor, radial pulse, camelCase params | `Idea 1` spikes on `hitRes.y` axial coord; `Idea 2` junction flare from 2nd-nearest fibre gap | ACES display RGBA (C unused) | audio was `textureSampleLevel(dataTextureC)` → plasmaBuffer; ACES; semantic alpha; depth; A write; header |
| mycelium | septa, fusion bridges, SSS, spores, params | `Idea 3` `g_granule` beads along `q.y` + pile-up at septa; `Idea 4` `g_wound` melanin rim at the repulsion-sphere cut | ACES display RGBA (C unused) | repulsion sphere tethered to the flying camera and aligned to the cursor ray (HEAD pinned it at world z=5, so it was left behind after ~10 s and appeared vertically mirrored) |
| neural-lace | orbit cam, conveyor, pulse wave, packets, trail advection | `Idea 1` node firing via `mat` ∈ [2,3) seeded by `hash31(id)`; `Idea 2` Ranvier `gap` → strand constriction + packet gating | HDR trail RGB in A (pre-ACES), alpha coverage | ACES on writeTexture only; header |
| pollen | 3 layers, drift field, burst, spawn, palette, post chain | `Idea 1` echinate `spike` radius modulation; `Idea 2` tetrad `release`/`sep` 4-grain loop | HDR feedback RGB + age alpha (HEAD) | advection now `textureLoad` at advected coord; header |
| singularity-forge | map, KIFS, heat gradient, param mapping | `Idea 1` lensed `rdL` + `ring` in miss branch (uses Lensing Intensity); `Idea 2` Doppler `dopp`/`beaming` on disk | ACES display RGBA, alpha coverage | Lensing Intensity was dead; C sampler → `textureLoad`; alpha no longer hard 1.0 (writeTexture + A) |
| superposition | ghosts, mouse + ripple collapse, fringes, Zeno, heisenberg fog | `Idea 1` `crossTerm` = \|Σψ\|²−Σ\|ψ\|² from unused `totalRe/Im`; `Idea 2` detector `hits` in A.a | rgb display, a = detector accumulator | depth read → `textureLoad`; header |
| quasicrystal | symmetry/density/colour/projection, quasicrystal2, gems, crackle, B writes | `Idea 1` `phason` perp-space phase per wave (+ pointer push); `Idea 2` `ammannBars()` Fibonacci chain | rgb trail, a = bass envelope | **packing lie fixed**: HEAD stored bass envelope in A.r and read `prev.rgb` back as trail colour |
| chrono-glass-nautilus | spiral map, ids 1–3, septa, lamellae | `Idea 3` siphuncle SDF id 4 + log-r pulses; `Idea 4` `chamberTide(g_chamber)` on glow + interior | ACES display RGBA | — |
| crystalline-forge | fold loop, twins, welds, gravity well | `Idea 3` `blackbody()` on welds + `seamGlow` fog; `Idea 4` `cleave` glint | ACES display RGBA | — |

## Default-look changes to check on a real GPU
- singularity-forge: Lensing Intensity (default 0.5 → 1.25 internal) now bends the sky and draws a photon ring. It was dead before, so the default look changes by design.
- quasicrystal: red trail channel is now real colour (it used to be the bass envelope). There is a gentle phason drift even with the pointer idle.
- neural-lace: writeTexture now goes through ACES (it used to be raw HDR clipped at 1), so highlights compress.
- mycelium: the cursor repulsion sphere is now always in view, under the pointer.

## Gates
- naga 10/10; `wgsl_precommit_gate.py --files` 10/10 (bindgroup + workgroup + extraBuffer).
- `npm run audit:extrabuffer` PASS. `audit_dead_sliders.py --files <10>`: scanned 10, 0 dead.
- `generate_shader_lists.js` + `check_duplicates.js`: 1386 unique.
- Jest: 101/107 suites pass; the 6 failures are the known `./bridge/api.js` import (same set on clean main).
- `SKIP_WASM_BUILD=1 npm run build` OK.
- Real-GPU visual QA: external (the VM has no adapter).
