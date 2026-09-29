# scan-distort — implementer notes (2026-09-28)

Files: `public/shaders/scan-distort.wgsl`, `shader_definitions/retro-glitch/scan-distort.json`.

## Kept verbatim
Colour quantisation (`quantize`, edge-preserving mix 0.3), block-grid edge darkening + edge noise + slight tint, MV dot grid (`smoothstep(0.15, 0.1, |blockUV|)` dot, `mvVisibility*0.5` mix), garble gate (`blockHash < 0.02 && timeHash < 0.3`), glitch pulse (`glitchProbability`, per-pixel hashed shift + additive noise), cursor vertical ripple (`push`, `vOffset`, `bendStr`, `dist*20 - time*2`), scanline count from mouse Y (`lines = 100 * (1 + mouse.y*0.5)`), held glitch-frequency boost, capped click ripples (age = time - ripple.z, `min(u32(u.config.y), 50u)`), C feedback smear (`tentAlpha` × `mix(0.1, 0.22, z)`), scanline darkening `0.8 + 0.2*scanLine`, slider roles (x block size 4..16, y quant 2..64 levels, z MV visibility + feedback amount, w glitch frequency).

## A packing
Pre-ACES linear display RGB + semantic alpha in `dataTextureA` (line 239). `dataTextureC` read exactly (`textureLoad`) as that linear colour in three places: the feedback smear (line 226), the tear band's stale rows (line 219) and the per-block temporal difference (line 165). ACES only on `writeTexture` (line 240). HEAD stored ACES-mapped colour in A and re-tone-mapped it through the smear (compounding), and stored a bass envelope in A.a.

## Ideas (line ranges in the WGSL)
1. **Sync-tear band** — lines 208-221, inside the existing `if (isGlitch)` pulse. Per pulse a band (top hashed in 0..0.8, height 0.08..0.2) loses h-sync: `ramp` is a 2-step sawtooth over the band, `slide = ramp² * (0.12 + treble*0.05)` with a hashed direction, and the slid rows are read from C at `coord.x - slide*dims.x` (exact `textureLoad`), so the tear shows last frame's picture. Soft 2 % edges, 90 % opaque.
2. **DCT-basis garble** — lines 184-199. `garbleRoll = floor(time * effectiveGlitchFreq)` re-rolls both the block selection hash and the pattern; a garbled block shows the 8×8 DCT basis `cos((2x+1)kuπ/16)·cos((2y+1)kvπ/16)` with `(ku, kv)` hashed per block, colour phases from `hash3(blockIdx, roll)` (HEAD's per-pixel noise formula reused on the basis level).
3. **MV arrows from temporal gradient** — lines 152-182. One-pixel Lucas–Kanade at the block centre: 4 source taps for `grad(L)`, 1 C tap for `Lprev`; `Lcur` is the current quantised, scanline-attenuated luma so the processing bias against C mostly cancels; dead-zone 0.06 on `dt`; `flow = -grad*dt/(|grad|²+0.002)`, clamped to length 4 → arrow length ≤ 0.4 block. Shaft is a segment SDF from the block centre, head a disc at the tip; both only when `arrowLen > 0.05`, so still content keeps HEAD's dot. `mvColor` keeps HEAD's `0.5 + v*k` encoding. Total: 6 extra taps per pixel.

## Floor fixes
- Removed the extraBuffer spring (HEAD lines 80-105); pointer is `u.zoom_config.yz` (line 90). No extraBuffer access remains.
- Dropped `bassEnv`/A.a envelope; `bass` used directly in `bendStr` and alpha. A.a is now the display alpha.
- `plasmaBuffer[bandBin]` (never written) → `plasmaBuffer[0].xyz` three-band lift (line 231).
- Pre-ACES linear stored in A, ACES on display only; C reads clamped ≥ 0.
- `hash3(vec3(blockIdx, roll))` replaces HEAD's static `hash2(blockIdx*0.1)` garble selection.

## Deviations from the card
- The card's "cheap per-block temporal gradient from C (a few taps)" is implemented with 4 source-gradient taps + 1 C tap (+1 centre source tap), not a search. Because C holds *processed* colour, the temporal difference is compared against the current processed luma (quantised × scanline factor) rather than raw source luma, plus a 0.06 dead-zone; residual bias from the feedback smear and quantisation steps is possible (see risks).
- Tear band: implemented as a 2-step sawtooth (two ramps across the band) so the tear reads as a tear rather than a single shear; the card's "sawtooth ramp" wording allows either.

## JSON changes
- `params`: byte-exact (python dump diff identical; original file text restored via `git checkout` and edited with a targeted string replace, so formatting is untouched too).
- `updatedParams`: unchanged (already aligned).
- `description`: rewritten to name the three ideas; "spring cursor" removed.
- `features`: `click-ripples` → `click-reactive`, `spring-cursor` removed (no spring); kept `mouse-driven`, `audio-reactive`, `temporal-feedback`, `upgraded-rgba`, `held-drag`, `aces-tone-map`.

## Gate / audits
- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/scan-distort.wgsl` → PASS (naga OK, bindgroup compatible, 0 extraBuffer violations).
- `python3 scripts/audit_extrabuffer.py --files …` → AUDIT PASS.
- `python3 scripts/audit_dead_sliders.py --files scan-distort` → AUDIT PASS.

## GPU risks (not visually verified — the VM has no WebGPU)
- MV arrows on still content: if the processing-bias cancellation is imperfect (feedback smear near the cursor, quantisation boundary flips, garbled/torn blocks in C), some blocks may show short arrows that jitter. The dead-zone should suppress most; if it does not, raise the 0.06 dead-zone or the `+0.002` gradient floor.
- The base look no longer goes through a compounded double-ACES via C, so the feedback smear is slightly less contrasty than HEAD's — intended per contract.
- Garble now re-rolls every glitch tick (~1.1 Hz at default), so garbled blocks flicker between positions rather than staying fixed.
- Tear-band stale rows are read at the same row from C: the band shows last frame, which at high frame rates is nearly identical to the current frame on still content; the sawtooth slide still reads as a tear.
