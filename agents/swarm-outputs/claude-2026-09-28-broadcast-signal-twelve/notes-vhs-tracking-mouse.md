# notes — vhs-tracking-mouse (Idea Card #3)

Files: `public/shaders/vhs-tracking-mouse.wgsl`, `shader_definitions/interactive-mouse/vhs-tracking-mouse.json`

## Kept verbatim
Band mask `smoothstep(barHeight, 0, distY)` at mouse Y; click tears (ripple loop capped `min(u32(u.config.y), 50u)`,
`age = time - rp.z`, yBand/xWindow/damage/shear formulas); row wobble, hold wobble, jitter; 3-tap R/G/B bleed offsets
(1.0 / 0.3 / −0.8); treble flash; vignette; IGN grain term. Sliders: x barHeight, y distortion, z noise, w colorShift —
unchanged roles and mappings (`*0.3+0.05`, `*0.1*bass_env`, `*0.02`).

## A packing
`ACES display RGB + source alpha`. No C read (unchanged: HEAD never read C).

## Ideas (line ranges in the WGSL)
1. **Dash-noise texture** — lines 123–147. Each screen row is cut into cells of hashed length (18–48 px, × (1+2·detune)) with a
   per-row phase so cells never stack into columns. Per cell, per 1/18 s: 20 % roll a bright streak, 12 % a dark carrier-loss
   dash, rest clean; ends fade (`dashEnds`). The dark dashes replace HEAD's column-shaped `rand(uv.x*200, time*10)` dropouts;
   `dashSignal` (−1/0/+1) carries the band noise with a small fine hiss between dashes.
2. **Tracking knob on mouse X + held auto-track** — lines 86–98 (and the `lastPress` scan inside the ripple loop, line 81).
   `detune = |X−0.5|*2` widens the band (×(1+1.2·detune)), raises wobble strength (×(1+1.5·detune)) and lengthens dashes.
   Holding (`zoom_config.w > 0.5`) engages `lock = smoothstep(time − lastPress)` over 1 s: band height ×(1−0.75·lock),
   strength ×(1−0.85·lock), noise ×(1−0.8·lock), detune ×(1−lock), AGC ×(1−0.7·lock). Releasing sets `lock = 0` at once.
   X = 0.5 unheld reproduces HEAD's mappings exactly.
3. **AGC lift in the band** — lines 149–155. `agc = bar_intensity*(0.55+0.45·detune)*(1−0.7·lock)`: chroma drains 65 %·agc toward
   luma, blacks lift by 0.16·agc with gain ×(1−0.22·agc).

## Floor fixes
- extraBuffer spring (HEAD lines 55–80) deleted; `mousePos = u.zoom_config.yz` (line 58). No extraBuffer access remains.
- Dead `plasmaBuffer[rowBin]` (`fftHiss`) removed; treble from `plasmaBuffer[0].z` scales the band noise instead (line 145).
- Soft band gate: `bandGate = 1 − smoothstep(0.85·barHeight, barHeight, distY)` (line 103) replaces the hard `in_bar` bool
  everywhere (`bar_intensity`, noise gate, dash gate); the displaced-UV select is now a mix (line 112).
- Alpha = source alpha (lines 121, 166) instead of the band/luma/treble formula.
- ACES on display and A (line 168). Header rewritten in CONTRACT format.

## Deviations from the card
- "Converges and locks over ~1 s" needs a press timestamp and `extraBuffer[133..]` is zeroed each frame, so the lock clock uses
  the newest ripple `z` (a press registers a ripple). If a hold ever starts without a ripple, `lastPress` defaults to `time − 1`
  and the lock is immediate. Holding also fires the existing click tear at the press point, as at HEAD.
- `damageMix = bandGate + clickDamage*50` (clamped) approximates HEAD's `clickDamage > 0.02` threshold smoothly.

## JSON
- `params` byte-exact (python diff identical). `updatedParams` already aligned; untouched.
- `description` rewritten to name the ideas.
- `features`: `mouse-driven`, `audio-reactive`, `upgraded-rgba`, `click-reactive` — all already present; all true now
  (mouse-driven was already true at HEAD via mouse Y; X and held now act too).

## Gate / audits
- `wgsl_precommit_gate.py --files public/shaders/vhs-tracking-mouse.wgsl`: PASS (naga OK, bindgroup compatible, 0 extraBuffer
  violations).
- `audit_extrabuffer.py`: PASS. `audit_dead_sliders.py --files vhs-tracking-mouse`: PASS (0 new).

## GPU risks (no WebGPU on this VM — nothing was viewed)
- If the runtime does NOT push a ripple on mouse-down (only on click release), the lock will engage instantly on hold instead
  of converging over 1 s; the visual is still correct, only the ramp is lost.
- Bright-dash probability (20 %) inside the band is a guess at the HEAD white-noise density; tune `0.80` in `brightDash` if the
  band reads too busy or too quiet.
- Dash cell hashing uses `rand()` (sin-hash) with `max(seed, 0.001)`; large `rowId*0.37 + cellId` seeds are fine in f32 at
  1080p but may show repetition at very large resolutions.
