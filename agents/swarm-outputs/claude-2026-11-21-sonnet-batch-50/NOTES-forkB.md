# NOTES — fork B (gen-neuro-cosmos, cosmic-web) — sonnet/batch-50

Cards are in `BRIEFS-forkB.md`. Scratch renders: `/tmp/claude-0/-root-image-video-effects/12631154-16b4-44ad-a621-195684eec032/scratchpad/b/` (`f_nc_sheet.png`, `f_cw_sheet.png`, `nc_halo_cmp.png`, `nc_ahp_cmp.png`, `cw_ablate.png`, `cw_sheet.png`, `nc_head.png`, `cw_headfix.png`). VM = SwiftShader, no real GPU: structural + SwiftShader pictures only, no visual-QA claim.

## gen-neuro-cosmos

**Pass:** 2nd+ (header `Upgraded: 2026-09-14, 2026-11-21`). Already on the prelude (no codemod).

**KEEP VERBATIM (held):** 4 params + roles/mapping (JSON `params` byte-exact, checked against HEAD); orbit camera with mouse yaw/pitch and time drift; `evoked` electrode/click fronts; all four shipped ideas still present and live (`saltatoryConduction`, `integrateAndFire`, pruning shadows, Hebbian `prevFrame.a`); palette, rim light, ACES on display, depth, alpha formula.

**A packing:** unchanged — ACES display RGBA (read back as `prevFrame.rgb` colour trail + `prevFrame.a` Hebbian memory). Stated truthfully on the card; nothing to fix.

**ADD (2 ideas):**
1. *Action-potential undershoot (after-hyperpolarization)* — `saltatoryConduction()` returns a third value `ahp` (`smoothstep(0.3,0.45,age)·(1−smoothstep(0.6,0.95,age))`); the strand colour is mixed toward a dimmer, cooler tint `(0.55,0.62,0.9)` by `ahp·web·(1−flash)·0.8` at the `// Idea 1 lands here` line. Visible as discrete one-node-long dark/cool segments trailing each hop (`nc_ahp_cmp.png`: amplified diff shows them on thick near strands). Ablation px diff >8/255: 8.1%, mean 1.9 — subtle by design (only the hit strand surface is touched).
2. *Soft inverse-square somatic halo (§12.2F)* — in the march: `halo += (spike + 0.8·refractory)·(0.022·glow)·stepLen/(r² + 0.012)` with `r = f1/scale` from the nearest-soma distance and `integrateAndFire(hash)` that `map()` already returned each step; added in warm white to `col` and to `glowDensity`. Visible as soft warm clouds around firing somas (`nc_halo_cmp.png`). Ablation (at the earlier 0.03 gain, trimmed to 0.022 afterwards): px diff >8/255 86.6%.
Formula row: **Soft inverse-square only** (owned by this file). No other §12.2 row used.

**RESCUES (default picture changes — loud):**
- **R1. Foam → strands.** HEAD's web `F2−F1` is the 2-D Voronoi bisector, i.e. foam membranes: the camera (inside the infinite lattice) saw giant flat teal sheets (`nc_head.png`, stdL 0.057), somas floated disconnected, and the comments' "f1 = position along a strand away from the soma" were false. Now the web SDF = distance to axon *segments* from the nearest soma to the 2nd/3rd nearest (`axonDist`); links are sparse (short < 1.15 lattice units and a symmetric per-link hash < 0.5 — a full 3-D Delaunay graph is ~15 links/soma = a thicket); strand radius multiplier 1.5× `thickness` (a 1-D strand needs more radius than a 2-D sheet to be seen; slider role unchanged), somas still `thickness·3`. Needed side changes because the camera now sits in an open lattice: near-clip bubble `d = max(d, 0.45−t)`, step-length-weighted glow (HEAD's per-step glow × 48 open steps saturated cyan), pixel-footprint hit threshold, 48 steps / far plane 9, depth still `t/20`. Seed jitter is confined to [0.15,0.85] so a **2×2×2 seed block** replaces HEAD's 27-cell search (3.4× cheaper per step; hash `cell_id.x` range 0.15–0.85 instead of 0–1, so IAF rates shift slightly).
- **R2. Saltatory conduction did not conduct.** HEAD: `wave = floor(nodeCoord) − t·k + 5h; flash = exp(−fract(wave)·5)`. `fract()` drops the integer node index, so every node of a soma's strands flashed in unison (numpy: fract values identical for nodes 0..5), and the flash profile over one period was a slow ramp (0.014→0.61) then an instant cut, i.e. reversed. Now `age = fract(t·k + 5h − floor(nodeCoord)·0.18)`, `flash = exp(−5·age)`: the spike hops node-to-node outward from the soma (ages 0.33, 0.15, 0.97, 0.79, … for nodes 0..5) with instant onset and exponential decay.
- Tiny comment-only fix: "neuron radius ~ thickness × 2" said ×2, the code is ×3.

**Evidence / numbers (SwiftShader, 256 px unless noted):**
- Default: nan 0, meanL 0.399 / stdL 0.134 / meanA 0.492 (HEAD 0.309 / 0.055 / 0.923). t≈20: nan 0. Held pointer (0.3,0.6) + audio 0.9/0.5/0.4: nan 0. Sliders (3,5,2,0.5) = very fat somas (expected for max thickness, nan 0); (0.5,0,0,0.01) = sparse web on near black (nan 0).
- Pixel diff vs HEAD: 99.5% of pixels >8/255, 84% >24/255 (foam → strands; expected).
- **Timing: 5.25× HEAD (interleaved min and paired-median 5.25, `mr_ab.mjs 256 5`); earlier variants 13–20× (27-cell, 80 steps).** Over the 1.3× cap and cannot meet it: HEAD's rays stop at the first foam wall within a few steps; a sparse strand lattice needs ≥ 10× more steps whatever the stencil. Trims already taken: 80→48 steps, far plane 14→9, 27→8 seed cells, 2 axon pairs not 3, `sin`-free link hash, step factor 0.85, pixel-footprint hit threshold. Absolute cost is now in the range of the batch's other heavy generative files (≈1.3–2.0 s/frame at 256 px here vs the coordinator's 1.1–1.3 s for alpha-aurora / light-networks under a 5-parallel load); HEAD was cheap only because it was broken.
- Open call for the coordinator: ship R1 at 5.25× (picture is a real neural web; ideas visible), or revert only R1 and keep R2 + Ideas 1 and 2 on HEAD's foam (cap-compliant, but the default picture stays teal sheets and the halo would be integrated over ~5 steps). I did NOT keep a second variant file.

**Gates:** precommit 1/1, naga-wasm 1/1, `audit_dead_sliders` pass (all four `zoom_params` read: x scale, y pulse, z glow, w thickness, checked by grep), `audit_extrabuffer` pass. No extraBuffer use. JSON: `description` appended; `features` unchanged; `params` byte-exact.

**Not verified:** real-GPU look and speed; whether the 8-cell search leaves rare missed-strand cracks at block boundaries (none seen in 6 renders); behaviour at non-square aspect (harness is square).

## cosmic-web

**Pass:** first creative pass (banner written; `Upgraded: 2026-11-21`). Coordinator's prelude codemod already applied (header-only).

**KEEP VERBATIM (held):** 4 params/roles (JSON `params` byte-exact); fbm domain warp; 3-octave filament stack with per-octave `plasmaBuffer[(o%8)+1]` spectrum; void path through the feedback mix; spring-damper well code (extraBuffer[133..138]) untouched; accretion arms; click waves/flow; galaxy field (jittered grid + `GALAXY_THRESH` + twinkle); temporal feedback (`DECAY`, `FEEDBACK`, integer history drift); chromatic shift; ACES; layered alpha; depth out.

**A packing:** pre-ACES HDR temporal colour + temporal alpha (read back as colour history), ACES only on `writeTexture` — unchanged and now stated in the header.

**ADD (2 ideas):**
1. *Junction clusters (F3−F1)* — new `voronoi3x()` for the base octave only (same 27-cell loop, same F1/F2 caps as `voronoi3`, plus F3 and the wall normal): `junction = smoothstep(NODE_THRESHOLD, 0, F3−F1)` reduces the filament border by `0.10·junction` (filaments swell into nodes) and drives `nodeMetric = junction·density` (the warm node bloom). Ablation (`junction=0`): px diff >8/255 17.4%, mean 9.1; thick bright junction nodes visible in `cw_ablate.png`.
2. *Golden-angle galaxy groups (§12.2E "Golden-angle layout")* — each host galaxy gets 4 satellites on a Vogel spiral (`θ = (i+½)·2.39996 + hostPhase`, `r = 0.0046·√(i+½)`), stretched ×1.35 along the filament tangent (perpendicular to the wall normal `r2−r1` from the same Voronoi loop) and ×0.6 across, windowed to the grid cell interior. Ablation (`GROUP_SATS=0`): px diff >8/255 3.2% (small dots by nature), clusters visible in `cw_ablate.png`.
Formula row: **Golden-angle layout only** (owned by this file). Junction clusters is a native mechanism, not a §12.2 row.

**RESCUES (loud):**
- **R1. Did not compile.** `let __finalRGB` (identifier may not start with `__`) and a second `let rippleCount` / `let aspect` in the same scope; the id was in `wgsl_validation.json` `knownFailures` (it is now naga-clean, so `verify:shaders:fix` will drop it). The tail overlay that caused it (screen-wide concentric `clockRings` × IQ-cosine `spectral` + a click front mis-timed against `ripple.z`, duplicating the real `clickWave`) is REMOVED, not renamed; `writeTexture` = the ACES'd `color` with semantic `alpha`. Before = `cosmic-web_headfix.wgsl` (compile-fix only): concentric rings across the whole frame (`cw_sheet.png` panel 1).
- **R2. Dead node mask.** `nodeMetric = smoothstep(0.35,0,f1)·density` keyed on F1 = the seed of a VOID cell where density is lowest (numpy port, statistical: mean² 0.0010, p99 0.014; junction mask mean 0.068, p99 0.905). Now junction-based (Idea 1). `NODE_THRESHOLD` re-valued 0.35 → 0.22 with a comment.
- **R3 (minor).** Galaxy `gd` multiplied the already aspect-corrected `uv` by `aspect` again (dots squeezed horizontally on a wide canvas); fixed; no-op at 1:1 (harness is square, not checked at 16:9). Galaxy host positions shift ≤ 0.2 cell (centre pulled into the cell interior so satellites are not clipped).
- Checked and NOT a bug: hueShift of the filament colours never goes negative (min component 0.138 / 0.308 over a full colorShift sweep), so no negative-into-ACES here.

**Evidence / numbers (SwiftShader):**
- Default (mouse 0.5,0.5), corner pointer (0.95,0.05), t≈20, click ripples, slider extremes (0,0.1,0,0) and (2,3,2,1) with audio 0.9: nan 0 in all. Default meanL 0.394 / stdL 0.136 / meanA 0.12 (HEAD-fix 0.381 / 0.101 / 0.102).
- Pixel diff vs compile-fixed HEAD (corner pointer): 83% of pixels >8/255, mean abs 24 — dominated by the removed ring overlay.
- Timing (interleaved `mr_ab.mjs`, 320 px, vs the compile-fixed HEAD which still carries the overlay it removed): min ratio 1.21, paired-median 1.11 (earlier 256 px run: 1.15). Within the 1.3× cap.

**Gates:** precommit 1/1, naga-wasm 1/1 (note it still lists cosmic-web in `knownFailures` — coordinator's `--fix` removes it), `audit_dead_sliders` pass (x warp, y density, z flow, w colorShift all read), `audit_extrabuffer` pass. JSON: `description` appended, `upgraded-rgba` added to `features` (ACES in WGSL + ideas implemented, §8), `params` byte-exact.

**Not verified / pre-existing, untouched:** the Batch-17 spring in `extraBuffer[133..138]` is re-zeroed every frame library-wide (seen in batch 48), so `springInitialized` is always false and the well follows the raw pointer; real-GPU look; 16:9 aspect.

## Formula names per file (for COORDINATOR_REVIEW de-dup)
- gen-neuro-cosmos: Soft inverse-square (§12.2F). (+ native: after-hyperpolarization undershoot.)
- cosmic-web: Golden-angle layout (§12.2E). (+ native: junction clusters via F3−F1; tidal tangent alignment.)
