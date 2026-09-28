# holographic-projection-failure — implementer notes (card #8)

Files: `public/shaders/holographic-projection-failure.wgsl`,
`shader_definitions/retro-glitch/holographic-projection-failure.json`.

## Kept verbatim
Tear bands (`scanlineBand`/`bandNoise`/`step(0.92 − instability·0.15)` with the same 0.08 amplitude), V-hold
wobble (`sin(uv.y*3 + rollPhase*TAU)*0.03*vHoldDrift`), repair circle (`0.22`/`0.38` held radius, `0.85` mix),
R/B split scaled by depth (`chromaticSplit*0.03*(0.8+depth*0.4)`), fringe amplitude (`0.85+0.15 sin`), block
fault (`step(1−instability·0.3)`, 0.7 mix), DAC bit truncation, static (`0.35·staticAmount`), ripple flash/jitter,
60 Hz flicker, history persistence `0.065`, slider mapping (`0.2 + p·1.8` ranges and audio multipliers).

## A packing
Pre-ACES linear display RGB + carrier-transmission alpha. C is read back as linear colour by both the beam
persistence (`history.rgb*0.065`) and the stale tear bands. ACES on `writeTexture` only. HEAD stored the ACES
result and re-tone-mapped it through C.

## Ideas (WGSL line ranges)
1. **Emitter cone** — lines 85-95 build `eDist`, `coneRatio`, `coneEdge` (65 % fade outside a ~50° half-angle,
   which only reaches the bottom corners on 16:9) and `throwFalloff` (35 % over the throw); line 158 makes the
   interference fringes concentric on the emitter with pitch tightening with distance
   (`eDist·res.y·0.8·(1+eDist·0.45)`); lines 184-188 apply the carrier gain and a cyan tint that grows as the
   picture thins; line 197 makes alpha = carrier transmission (`(0.55 + luma·0.25 + fringe·0.15 + repair·0.15)
   · carrier · srcAlpha + lockLine`).
2. **Stale-frame tear bands** — lines 151-154: `tearBand` (the same mask that drives `scanGlitch`) mixes in
   `historyAt(driftUV + scanGlitch·1.5)` at 0.8, so torn rows show the previous frame, shifted, not the live
   image. Suppressed inside the repair circle.
3. **Re-sync sweep** — lines 126-141: a lock line `sweepY` sweeps from the top to the bottom of the repair circle
   at 0.45 Hz (1.1 Hz held); rows above it get the full repair, rows below only 45 %; the line itself glows
   carrier-cyan (line 188) and adds to alpha.

## Floor fixes
- `blockSize = clamp(mix(32,6,instability), 3, 32)` (line 163) and `bitDepth = clamp(…, 1, 8)` (line 168):
  instability reaches 2.9 with bass and both went negative at HEAD.
- `rollPhase = fract(time·(0.2+vHoldBase·0.6) + bass·0.06)` (line 120): bass offsets phase rather than scaling
  the rate; `vHoldDrift` still scales the wobble amplitude with bass as at HEAD.
- Depth via exact `textureLoad` (HEAD used the non-filtering sampler — equivalent, now explicit).
- Pre-ACES in A (line 199); ACES on display only (line 200). History clamped [0,4].
- `updatedParams` defaults 1 and 3 corrected to 0.3 / 0.2 to match `params` (they were 0.5/0.5 at HEAD — the
  saved `params` are authoritative and untouched).

## Deviations from the card
- None in substance. The emitter's cone fade only touches the bottom corners at common aspect ratios (top
  corners sit at ratio ≈ 0.89, inside the soft edge), so the default look keeps the full picture readable.
- The repair circle's lower half is now 45 % repaired instead of 85 % until the sweep passes — that is the idea,
  but it changes what a viewer sees inside the circle at rest.

## JSON
- `params` byte-exact (parsed-array diff and raw text block diff: identical).
- `updatedParams`: defaults for index 1 (RGB Split) 0.5→0.3 and index 3 (Static) 0.5→0.2 to match `params`.
- `description` names the three ideas; `features` adds `upgraded-rgba` (ACES + ideas), keeps `audio-reactive`,
  `mouse-driven`, `click-reactive`, `depth-aware`, `temporal-feedback` (all true).
- `feedbackPacking` updated to pre-ACES linear + transmission alpha.

## Gates
- `wgsl_precommit_gate.py --files public/shaders/holographic-projection-failure.wgsl`: naga OK, bindgroup
  compatible, 0 extraBuffer violations.
- `audit_extrabuffer.py`: AUDIT PASS. `audit_dead_sliders.py --files holographic-projection-failure`: AUDIT PASS.

## GPU risks (no WebGPU on this VM — nothing was viewed)
- Stale tear bands read C at a shifted coordinate; with the 0.065 persistence C is mostly last frame's picture,
  so the tears should read as a one-frame-late copy. If C is black on frame 0 the first tears are dark for one
  frame.
- Carrier alpha lowers alpha toward the top of the picture (long throw); if the host composites over a
  background, the top will show more of it than HEAD did.
- The concentric fringe phase replaces HEAD's horizontal fringes — intended by idea 1, but it is a visible
  change to the base texture.
