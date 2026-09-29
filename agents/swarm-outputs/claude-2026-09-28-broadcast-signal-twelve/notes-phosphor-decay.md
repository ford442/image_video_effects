# phosphor-decay — implementer notes (2026-09-28)

Files: `public/shaders/phosphor-decay.wgsl`, `shader_definitions/retro-glitch/phosphor-decay.json` (Idea Card #10).

## Kept verbatim
Per-channel decay rates (`0.95/0.96/0.98 - p`), OkLab history mix (`0.35 + bass*0.15`, `max(state, history*0.85)`), 4-tap box bloom gated by luma, RGB shadow mask (`pixel.x % 3`), scanline `sin(pixel.y*0.5)` (HEAD's `uv.y*res.y*0.5`), cyan cursor glow with held boost, capped click blooms (loop `min(config.y, 50)`, `age = time - z`), depth haze + blackbody grade, vignette, IGN dither, `to_srgb` after ACES, slider roles (x decay, y bloom, z mask, w scan blanking).

## A packing
`A.rgb` = linear HDR phosphor RGB after blackbody, before vignette/ACES (same as HEAD), clamped to `[0,16]`. `A.a` = burn-in accumulator (slow EMA of input luma, 0.995/0.005), clamped `[0,1]`. C is read back as that: `prev.rgb` decays into history, `prev.a` seeds the accumulator. Every C read goes through `finiteOr()` (lines 134-136) so a NaN/Inf can never persist.

## Ideas (line ranges)
1. **Burn-in** — lines 210-217. `burn = prev.a*0.995 + luma*0.005`; `burnExcess = max(burn - luma*0.6, 0)`; `efficiency = 1 - smoothstep(0.02,0.7,burnExcess)*0.55` multiplies the excitation. Static bright content dims a little while it stays; once it moves, the region excites at ~45% and shows as a dim negative that recovers over ~200 frames. Written to A.a at line 283.
2. **Held static charge** — `staticCrackle()` lines 138-158 (per-frame hashed radial spark filaments in 28 angular sectors, treble strikes more of them) and lines 245-259 (crackle + dust specks: 2-px hashed motes inside r=0.30 of the cursor, added to the phosphor state while held; since they enter the feedback state and nothing redraws them after release, the per-channel decay fades them over ~1 s). Crackle also lifts alpha (line 296).
3. **Blanking-interval flicker** — lines 231-238. Bottom 14% of rows dim by a per-frame hashed amount scaled by Scan Blanking (`vblDip`), plus a retrace-timing shimmer on the last 4%.

## Floor fixes
- Near-black HEAD render: `writeTexture` now gets un-premultiplied RGB with a semantic alpha (`0.15 + smoothstep(0,0.6,energy)*0.85 + click + cursor + crackle`), lines 293-299.
- OkLab cube roots guarded with `max(0, x)` (lines 49-53); blackbody `pow` bases guarded with `max(...,1e-3)`; `to_linear/to_srgb` guarded.
- Spring removed: `mouse = zoom_config.yz` (line 169); no extraBuffer reads or writes remain.
- `plasmaBuffer[y%8+1]` (always 0) replaced by `rowVoice = mids` (line 181) for the scanline wobble and click-bloom warmth.
- Half-texel UV for sampling; scanline kept on integer `pixel.y` so its frequency is byte-identical to HEAD.
- A write clamped to `[0,16]` so nothing non-finite enters C.

## Deviations from the card
None. "Burn-in reduces efficiency where the accumulator is high relative to current luma" is implemented as `burn - luma*0.6` rather than a pure difference so that a static picture is not uniformly dimmed by half.

## JSON
`params` byte-exact (verified via python diff against HEAD). `updatedParams` already aligned (unchanged). Description rewritten to name the three ideas. Features: added `click-reactive`; removed `spring-cursor` (no spring) and `click-ripples` (renamed to the canonical `click-reactive`); kept `mouse-driven`, `audio-reactive`, `held-drag`, `upgraded-rgba`, `depth-aware`, `aces-tone-map`, `temporal-feedback`, `linear-feedback`, `oklab-mixed`, `blackbody-graded`.

## Gates
- `wgsl_precommit_gate.py --files public/shaders/phosphor-decay.wgsl`: naga OK, bindgroup compatible, 0 extraBuffer violations.
- `audit_extrabuffer.py --files ...`: PASS (0 violations).
- `audit_dead_sliders.py --files phosphor-decay`: PASS (0 dead).

## GPU risks (no WebGPU on this VM — nothing was viewed)
- Burn-in ghost strength (0.55 max efficiency loss) and EMA rate (0.005) are untuned guesses; if the ghost is too strong on real video, lower 0.55 or raise the `luma*0.6` term.
- Crackle uses `atan2` sectors; the filaments may read as a starburst rather than lightning at small cursor radius.
- Alpha floor 0.15 on dark glass may look different from HEAD's intent in compositing contexts (HEAD was effectively invisible, so there is no reference look).
