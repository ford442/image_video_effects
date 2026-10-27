# Claude cyber-glitch-eight — Notes

2026-10-19. Eight shaders across advanced-hybrid, retro-glitch and visual-effects. Prelude migration
(six files: all except rgb-glitch-displacement and cyber-scan, which already used it) ran first via
`scripts/migrate_to_prelude.py` and is header-only, in its own commit. Saved `params` are byte-exact
in every JSON; the only JSON edits are `upgraded-rgba` on the two neural files (ACES added).

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| neural-raymarcher | ping-pong 5-layer march + noise flow + FFT-bin vortex, extraBuffer[0] chroma × baseDepth, edgeGlow, fog (w), volumetric alpha, depth | A unused (unchanged) | Idea 1 `inScatter` → `fogColor` (promotes the discarded `baseColor`); Idea 2 `firePhase`/`spike`/`membrane`/`actionPotential`. Floor: zoom_params.z (Glow) was dead, now drives both; bounds guard; clamp → `aces_tonemap` |
| neural-raymarcher-gabor | march/chroma/glow/fog, 4 orientations + pointer/camera offset, 4 palettes, activationVis mix, alpha = dominant orientation | A unused (unchanged) | Idea 1 `responseOdd`/`kernelOdd`/`energy` in `gaborResponse` (quadrature pair, same taps); Idea 2 `e2`/`pooled`/`normW`/`contrastGain` divisive normalization. Floor: `gaborFreq` read `zoom_config.x` (time) → fixed 0.125 (legacy default 0.3); ACES; alpha clamped |
| ascii-flow-structure | 4 params/roles, tensor + eigen + coherency pow, vortex, click shock, held lock, glyph set + index rules, colour mix, spring [133..138], ACES | raw (eigenvec.xy, coherency, lic), unchanged | Idea 1 `weight` arg on `draw_glyph` + `inkWeight` (stroke width follows brightness); Idea 2 `cellTexel`/`prevCell`/`prevVec`/`holdW` orientation hysteresis. Packing fix: previous coherency read from C.z (HEAD read C.a = lic) |
| cyber-trace-structure | 4 params, spring, tensor/eigen/coherency, Hessian saddle fork, brush, vortex, ripple turbulence, LIC, Ideas 1–2, ACES | trace history RGBA (unchanged) | Idea 3 `loadHistoryBilinear` + `upstream`/`history` trace current; Idea 4 `flowDir`/`routeAngle`/`routeDir` octilinear routing |
| data-stream-structure | 4 WGSL roles, strips + per-strip speed + wobble + jitter, hex, bright blocks, palettes, spring, ripples, C.r trail, ACES | (trail, lum, flowAngle, alpha), unchanged | Idea 1 `packetCoord`/`packetGap`/`inHeader`/`headerBit` packet framing; Idea 2 `coherency` (new from lambda2) + `collision`/`collideHit` lane collisions |
| byte-mosh-explosion | 4 params, spring, prismDisplace shape, ripple chroma waves, block op selector, pixel flips, pointer zone, ripple rotations, flicker, glow, ACES, alpha | ACES display RGBA (HEAD wrote bytes nothing read) | Idea 1 `sliceStart`/`slip`/`slipRoll` resync propagation (8-bit word rotation); Idea 2 `concealRoll`/`conceal`/`prevDecoded` error concealment from exact C; Idea 3 `CAUCHY_R`/`CAUCHY_B`. Floor: `finalColor.rgb =` swizzle assignment failed Naga at HEAD — whole-vector assignment; removed from `wgsl_validation.json` knownFailures (ratchet 29 → 28) |
| rgb-glitch-displacement | 4 WGSL roles, spring, every displacement fn and order, colour chain, ACES, alpha | offset.xy, energy .z, latch .w (was 0) | Idea 1 `drive`/`hi`/`lo`/`trackLock`/`trackTear` Schmitt tracking latch; Idea 2 `moshZone`/`blockTexel`/`prevBlockOffset`/`iFrame` macroblock motion carry |
| cyber-scan | 4 params, beams/trails, holo lines, hex, rain, interference, noise, chroma, sparkle, bursts, Ideas 1–2, ACES | ACES display RGBA (unchanged) | Idea 3 `surfN`/`lidarReturn` on the main beam emission; Idea 4 per-channel `smear` decay (P7) |

## §12.2 formula use

| Shader | Rows |
|---|---|
| neural-raymarcher | none verbatim (§12.1 t3 promote `baseColor`; t2 in-scatter; action potential) |
| neural-raymarcher-gabor | none verbatim (§12.1 t1 quadrature kernel; t2 divisive normalization) |
| ascii-flow-structure | none (§12.1 t1/t5 tone matching; t6 hysteresis) |
| cyber-trace-structure | none (§12.1 t6 history advection; t5 octilinear routing) |
| data-stream-structure | none (§12.1 t5 packet framing; t3 coherency) |
| byte-mosh-explosion | Cauchy dispersion (F); rest §12.1 t2/t5 |
| rgb-glitch-displacement | Schmitt-trigger lock (B); Macroblock motion carry (B) |
| cyber-scan | none verbatim (§12.1 t2 Lambert return; t5 P7 phosphor) |

No §12.2 row is used on more than one file.

## Known pre-existing oddities left alone

- neural-raymarcher(-gabor) read `extraBuffer[0]` (engine bass) as chroma and `extraBuffer[10]`
  (FFT bin 5) as "click intensity". Read-only, kept as the effect's audio coupling.
- JSON param names on neural-raymarcher, data-stream-structure and rgb-glitch-displacement do not
  describe what the WGSL does with those slots; rgb-glitch-displacement exposes 3 params while the
  WGSL reads 4. Saved params kept byte-exact; WGSL roles kept.

## Closeout

- Floor: prelude include / 16×16 / exact C loads / A packing as documented / saved params exact.
- Gates: Naga 8/8 via `wgsl_precommit_gate.py`, `audit:extrabuffer` pass, `audit:dead-sliders` 0 new
  on all 8, `generate_shader_lists.js`, vitest 169 files / 1435 tests pass, `SKIP_WASM_BUILD=1 npm run
  build` ok, `verify:toolchain-foundation` 13/13 after the knownFailures ratchet update.
- Real-GPU visual QA: external. neural-raymarcher-gabor (frequency fix) and byte-mosh-explosion
  (first time it compiles) change the most.
