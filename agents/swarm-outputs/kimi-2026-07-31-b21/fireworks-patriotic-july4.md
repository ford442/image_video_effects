# Swarm Notes: fireworks-patriotic-july4 (Batch 21)

## Lines
- Before: 107 → After: 162 (+55, inside target 157–197)

## Bugs fixed (Priority 1+2)
1. **Mouse-coord-units bug** — `(u.zoom_config.yz - res*0.5)/min(res.x,res.y)` → `(u.zoom_config.yz * res - res * 0.5) / min(res.x, res.y)`. Held-click 40-spark ring now centers on the cursor (zoom_config.yz is normalized [0,1]).
2. **Flat-0.0 depth clobber** — `writeDepthTexture` now stores `clamp(dot(col, vec3(0.299,0.587,0.114)) * 0.9 + stripe * 0.15, 0.0, 1.0)` (brief-exact formula); shells and stripes sit forward, dark sky recedes. "depth-aware" tag is now honest.
3. **Dead mids read** — added `let mids = plasmaBuffer[0].y;` and wired into the stripe wave: stripe phase rocks via `mids*0.3*sin(uv.x*7.0 + time*1.7)` and stripe mix amplitude scales by `(0.7+mids*0.3)`. All three audio bands (bass/mids/treble) now live.

## New techniques (expansion)
- **Click grand-finale shells**: ripple loop guarded `min(u32(u.config.y), 50u)`; each live ripple launches a one-shot shell at its click point using the same normalized→centered coord fix (`rip.xy * res - res*0.5) / min(...)`). Ascending comet head + tail until age 0.6, then burst with sparkPos/softGlow/patriotColor pipeline; color cycles red→white→blue by click index (`f32(ri % 3u) * 0.11` lands on band boundaries 0 / 0.33→white / 0.66→blue via fract(t*3)).
- **Twinkling star field**: hashed 24×24 cell grid, stars hide in dark sky regions `(1.0 - lum)`, density and twinkle ride Sparkle slider.
- **Bass mortar flash**: warm launch glow off the bottom edge synced to the probe loop's launch clock (`time*(0.75+bass*0.15)/1.8`), decays `exp(-phase*6)`.
- **Crackle afterglow**: 8 Hz ember grid with `exp(-fract(time*8)*5)` decay riding treble — complements the fast `spk` sparkle.

## Slider map (roles unchanged, all honestly wired)
- x Patriot Mix (0.3–1.0): image-hue ↔ red/white/blue palette blend in patriotColor
- y Burst Power (0.35–1.6): shell energy, spark counts (probe n, finale fn_), velocities, mortar glow
- z Stripe Wave (0–1): flag-stripe tint amplitude + scroll speed
- w Sparkle (0.2–1.0): star-field density, fast sparkle threshold, crackle brightness

## VERBATIM preserved
acesToneMap, hash1, softGlow, sampleImg (centered-UV `uv*0.5+0.5`), sparkPos, patriotColor (exact band math 0.33/0.66/0.34), 8-probe launch loop incl. `continue` guards, temporal feedback `mix(prev*0.92, col, 0.33)`, `dataTextureB` write `col*0.5+prev*0.4`, A=display / C=prev read, 13-binding layout, `@workgroup_size(16, 16, 1)`, `textureSampleLevel(..., 0.0)`, writeTexture/dataTextureA/dataTextureB written every frame. extraBuffer untouched (no writes). No reserved words (`fn_` used instead of `n` clash; no `target`).

## JSON changes
`shader_definitions/image/fireworks-patriotic-july4.json`: added ONLY `"updatedParams"` (index 0–3, names/defaults/min/max/step exactly per brief) and `"updated": true`. Param ids/defaults untouched. Validated with `json.load`.

## Deviations
- Stripe line and stripe-mix line modified (mids wiring) — mandated by the brief's "wire the dead mids read into the stripe wave". Everything else in the probe loop / feedback / color pipeline is byte-identical.

## Gate result
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/fireworks-patriotic-july4.wgsl` → **GREEN**: Passed 1/1, naga OK, bindgroup compatible, 0 warnings, 0 extraBuffer violations, 0 workgroup errors.
