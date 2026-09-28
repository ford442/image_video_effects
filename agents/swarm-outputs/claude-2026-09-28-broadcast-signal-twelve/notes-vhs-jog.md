# notes — vhs-jog (Idea Card #2)

Files: `public/shaders/vhs-jog.wgsl`, `shader_definitions/interactive-mouse/vhs-jog.json`

## Kept verbatim
Wrapped vertical roll (`fract(uv.y + vertical_tracking + ...)`), head-switch band, click slip bands (ripple loop capped
`min(u32(u.config.y), 50u)`, `age = time - ripple.z`), held slip band at mouse Y, `noise()` tear bands, horizontal streak, R/B
bleed, static noise, C max-hold streak (`max(color, hist*0.42 ...)` with `direction`-signed offset), vignette. Sliders:
x noise, y distFreq, z bleed, w scanlines — unchanged roles.

## A packing
`pre-ACES linear display RGB + alpha`; C read back as colour (max-hold streak, line 176, and pause field, line 187). HEAD stored
post-rolloff colour; the rolloff is gone so A is now linear. Only A is written (no B, no extraBuffer).

## Ideas (line ranges in the WGSL)
1. **Cue/review noise bars** — lines 131–142 (mask + row skid) and 169–171 (bar body). `cueAmt = smoothstep(0.30, 0.95, shuttle)`;
   bar count `2 + floor(cueAmt*5)` (2…7); bars scroll with `+ time*(0.8+1.4·cueAmt)*direction`, i.e. opposite sign to the
   head-roll term (`- time*...*direction`). Inside a bar the row skids sideways and the pixel is 85 % coarse row-streaked snow.
   Alpha also lifts under the bars (line 206).
2. **Pause-mode field flutter** — lines 179–194. `pauseAmt = 1 - smoothstep(0, 0.09, shuttle)`. Odd screen rows
   (`(coord.y + rowJitter) & 1`, `rowJitter` ∈ {−1,0,1} re-rolled 30×/s) take a C row offset by the same jitter, mixed 80 % held /
   20 % live so the field converges to a lagging copy through C rather than fading; a ±0.03 per-row flutter is added. Even
   rows are live source. X = 0.5 (`sign()` = 0 at HEAD, dead zone) now shows this instead of a static picture.
3. **Reverse-play colour phase error** — lines 156–163 plus `rotateChroma` helper (lines 50–60). Active only for backward
   shuttle (`step(mouse_x, 0.4999)`), amplitude `smoothstep(0.06, 0.55, shuttle)` so it settles to zero as speed drops. Each
   row band (`6 + cueBars` bands, drifting with direction) gets its own hashed CbCr rotation up to ±117°, re-rolled 6×/s.

## Floor fixes
- Head band `exp(-pow(x, 2))` → `exp(-(x*x))` (lines 104–105); `pow(abs(...), 2)` → `shuttle*shuttle` (line 90).
- `tapeSlip` capped at 1.5 (line 120).
- Scanlines on the screen row `uv_raw.y` (line 197) — HEAD used the rolled tape row.
- HEAD's ad-hoc `color/(1+0.35 color)` rolloff removed; ACES on `writeTexture` only (line 208); A gets linear (line 207).
- Header rewritten (Category `interactive-mouse` to match the JSON folder; HEAD said `image`).

## Deviations from the card
- None in substance. The pause field uses an 80/20 held/live mix instead of a pure C copy: a pure copy through a
  `max()`-streaked history either decays (with any <1 factor) or stacks (with the max-hold), so the 20 % live bleed keeps it a
  stable lagging field.
- Default pointer position: if the runtime's resting mouse is (0.5, 0.5) the effect now shows the pause flutter at rest, which
  is the intended still-frame look; HEAD showed a plain picture there.

## JSON
- `params` byte-exact (python diff identical). `updatedParams` already aligned; untouched.
- `description` rewritten to name the ideas.
- `features`: `mouse-driven`, `click-reactive`, `audio-reactive`, `upgraded-rgba` all already present and all true (bass/mids/
  treble scale noise/freq/bleed/slip). Pre-existing `fast-motion`, `depth-aware`, `temporal-trail`, `glitch` left as found —
  not mine to remove, but note `fast-motion` is not a brief this file opted into.

## Gate / audits
- `wgsl_precommit_gate.py --files public/shaders/vhs-jog.wgsl`: PASS (naga OK, bindgroup compatible, 0 extraBuffer violations).
- `audit_extrabuffer.py`: PASS. `audit_dead_sliders.py --files vhs-jog`: PASS (0 new).

## GPU risks (no WebGPU on this VM — nothing was viewed)
- Two exact C loads per pixel in pause mode (streak + field); cheap.
- The `& 1` parity on `i32` and `select` with a bool are naga-clean; verified by the gate.
- Cue bar snow brightness (0.25–0.95) may read too bright on dark sources; tune `cueMask * 0.85` if so.
- Reverse hue rotation up to ±117° is strong by design (colour-under phase reversal); reduce `PI * 1.3` if it looks garish.
