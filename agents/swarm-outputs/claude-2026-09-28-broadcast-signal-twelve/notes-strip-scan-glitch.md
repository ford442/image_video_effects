# strip-scan-glitch — implementer notes (2026-09-28)

Files: `public/shaders/strip-scan-glitch.wgsl`, `shader_definitions/interactive-mouse/strip-scan-glitch.json` (Idea Card #12).

## Kept verbatim
Strip count mapping `mix(10, 300, p + mouseX*0.5 + mids*0.15)` (now clamped), speed mapping `((p-0.5)*4 + (mouseY-0.5)*4)*(1+bass*0.5)`, per-strip hash speed `0.5 + 0.5*hash`, brightness-weighted scan `0.6 + g*0.8`, row sine warp `sin(uv.y*10+time)*0.05*jitter`, tear threshold/offset, RGB split `0.02*w`, wrapped `fract()` sampling with `non_filtering_sampler`, alpha averaging + jitter/strip corruption, bass scan bar (`0.35` sweep, 900 width), slider roles (x strips, y speed, z jitter, w rgb).

## A packing
`A.rgb` = pre-ACES linear display RGB (clamped `[0,4]`), `A.a` = the source-derived alpha. C read back as colour: same-coord for the brake freeze (line 177), two shifted exact `textureLoad`s for the streak (lines 153-160). ACES on `writeTexture` only (line 181).

## Ideas (line ranges)
1. **Vertical-blanking seam** — lines 116-138. `sv = fract(uvG.y)`, `seamDist = min(sv, 1-sv)`; a black bar of ±0.006 source height (`bar`), bright sync-pulse ticks along its centre line hashed per strip (`tick`), and a 2-tap vertical smear of the source in the ±0.045 zone around the bar along the scroll direction (`smear`). Only strips that actually scroll get a seam (`seamPresent`). Bar raises alpha to opaque.
2. **Held brake** — lines 164-178. While held, `brake = 1 - smoothstep(0.05, 0.42, |stripCenterU - mouseX|*aspect)`; the output is mixed toward last frame's C at that weight (capped 0.97), so the strips under the cursor freeze and the neighbours slow. Treble flutter (`hash(frame, strip) > 0.75` × treble) lets fresh frames slip through. Release drops `brake` to 0 and the strips are instantly back at speed because the freeze only lived in C.
3. **Speed-streak ghost** — lines 150-161. `streakAmt = clamp(|stripSpeed|*0.22, 0, 0.55)`; two exact C taps 4 and 8 px up-stream (sign of the strip's scroll) mixed in as `max(color, ghost*0.9)`, so fast strips trail a short vertical smear and slow strips stay crisp. Mixed, not added: feedback cannot run away.

## Floor fixes
- `pow(uv.y - scanY, 2.0)` (NaN for negative base) → `dy*dy` (lines 141-143).
- Strip-count mix argument clamped to `[0,1]` (line 72) — HEAD extrapolated past 300 strips.
- Unbounded `yOffset = speed*time*...` → `fract(stripSpeed * tWrap)` with a 600 s wrapped clock (lines 75-80).
- Half-texel UV; depth via `textureLoad`.
- ACES on display; A stores pre-ACES.
- Added `updatedParams` (HEAD had none).

## Deviations from the card
- "Drags the strips to a halt": there is no persistent phase state, so a real speed ramp would jump the strip position. The halt is implemented as a C freeze-frame mix instead, which visually stops the strip and releases cleanly (documented in the header line).
- The seam smear samples the source (not C) so it stays registered to the strip's own picture.

## JSON
`params` byte-exact (python diff vs HEAD: True). `updatedParams` added mirroring the four params (index/name/default/min/max). Description rewritten to name the ideas. Features: kept `mouse-driven`, `glitch`, `audio-reactive`, `upgraded-rgba`; added `held-drag`, `aces-tone-map`, `temporal-feedback`. Not click-reactive (no ripple use).

## Gates
- `wgsl_precommit_gate.py --files public/shaders/strip-scan-glitch.wgsl`: naga OK, bindgroup compatible, 0 extraBuffer violations.
- `audit_extrabuffer.py`: PASS. `audit_dead_sliders.py --files strip-scan-glitch`: PASS (0 dead).

## GPU risks (no WebGPU on this VM — nothing was viewed)
- Seam bar height 0.006 of source height is ~6 px at 1080p; ticks are 5 per strip width and may be sub-pixel at 300 strips.
- `sign(stripSpeed)` with `speed ≈ 0` (mouse Y and speed slider both at 0.5) gives no scroll: seam and streak both gate off, so the default look with a centred pointer is the plain HEAD strips — intended.
- Streak `max()` against a 0.9× ghost may make bright scrolling content slightly bloomed; lower 0.9 if it reads as smearing at moderate speeds.
- The 600 s clock wrap causes one phase jump every 10 minutes.
