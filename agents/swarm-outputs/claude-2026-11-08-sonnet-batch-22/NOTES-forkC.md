# sonnet/batch-22 — fork C notes

Shaders: gen-vitreous-chrono-chandelier, gen-celestial-glass-tornado (both second pass). Edited: the two WGSL files and
`shader_definitions/generative/gen-vitreous-chrono-chandelier.json` (features only). Nothing committed, no lists/ledger/build touched.
All renders: minirender (SwiftShader, rgba32float — cannot show f16 A-texel quantisation), default params, idle cursor unless stated.

## gen-vitreous-chrono-chandelier

**Kept verbatim:** 4 slider roles (x Shatter Threshold, y Chime Density, z Refraction Index -> iorR/G/B, w Transmission -> colour gain); `round(q/spacing)` lattice + `hash3` len/damping/theta0; `pendulumAngle` physics constants; cluster phase-lock; crystal rounded box + cleavage cut; mount torus; link box; tick-mark disc; mouse repel; `refractRay` x3 + `causticPattern`; floor caustic web; temporal C mix (5%); chromatic aberration; ACES; alpha from fresnel; depth passthrough.
**A packing:** ACES display RGBA, unchanged; no state texels. JSON has no top-level `params` (app feeds 0.5 x4) — none added; `x-meta.upgrade.params` left alone (documents never-fed defaults 0.5/4/1.3/0.5, coordinator may want to align it).

**Rescues (default look changes on purpose):**
- R1 upside-down camera (`rd.y = -uv.y`) + framing `ro (2.0, 1.6, -6.5)`, pitch 0.30 rad; mouse repel point follows the camera frame. (`:139`)
- R2 Chime Density: `spacing = mix(7, 1, y)` (default 0.5 -> 4.0, the x-meta intent; HEAD fed 0.5 as a 0.5-unit cell so 1-3 unit pendulums were clipped by neighbouring cells = noise). Direction now matches the name. (`:131`)
- R3 floor web only where the floor is the first surface (`!hit || tf < hitT`), distance fade `exp(-0.045 tf)`. (`:216`)
- R4 swing never died: strike at the lowest point every 6 half-periods (position continuous). At t=300 geometry-only motion over 3 s: 2482 px changed vs 515 with HEAD's envelope (alpha-panel diff >8/255, 192 px). (`:37-47`)

**Ideas in the diff:**
1. Pendulum-projected floor foci (`:225`, tactic 3; no §12.2 row) — disc + ring per chime on the floor following that chime's `chimeSwing`; per-channel radius 1/0.94/0.88.
2. Cleavage shards (`:99`, `:137`; tactic 2, wires the dead Shatter Threshold) — `shard = clamp((bass - thr)/(1 - thr)) * 0.9`, second box displaced along the cleavage normal, uniform-gated `if (shard > 0.001)`. Zero at silence; visible at bass 0.95 (render `chf_mv`).
3. Hub lamp, soft inverse-square (`:192`, §12.2F) — r0 = 1.5 (`2.25/(d²+2.25)`), Lambert 0.5 + glint 48-power 1.6, bass pulse; post-hit only.
**Formulae:** soft inverse-square (1 file in the batch from this fork). No Cauchy/Snell/AO/Airy on this file.
**Measured default-look change:** HEAD meanL 0.141 / stdL 0.167 (noise soup) -> 0.109 / 0.135 at 192 px, audio 0.4/0.3/0.2; silent 0.090 / 0.114. At 576: 0.109 / 0.135. Moved cursor + bass 0.95: 0.139 / 0.166 (shards). Density 0 / 1: meanL 0.072 / 0.193.
**Gates:** `wgsl_precommit_gate` pass (naga OK, 0 extraBuffer violations, 0 pasted headers); `audit:extrabuffer` PASS; dead sliders: all four read by hand (x `:130`, y `:132`, z `:133`, w `:134`); no NaN in any render.
**Timing:** load average was 8–14 during the run; HEAD 45–109 ms vs current 71–150 ms per frame at 192 px, round-to-round noise larger than the gap, and the scenes differ (HEAD's noise soup terminates rays early; the rescued scene marches empty void to t=50). Per-step additions: the re-strike (one floor, one divide) in `pendulumAngle`; shard box only when bass > threshold. Not accepted or rejected on timing.
**Open items:** void above the horizon is empty by design (abyssal cavern; mounts/links only appear near the camera); crystals read warm gold from the HEAD R>G>B caustic weights; `x-meta` defaults untouched; features array added to the JSON (`raymarched`, `audio-reactive`, `mouse-driven`, `upgraded-rgba`) to match the header — drop if a coordinator test objects.

## gen-celestial-glass-tornado

**Kept verbatim:** 4 params + roles; tornado radius law; 4-fold KIFS debris sphere; Cauchy 3-tap channel ramp (offsets from Chromatic Split); fresnel + thin-film + glint; helical arcs, meteors, confinement rings, accretion dust, click glass rings; C trail mix; `acesToneMap(col*1.1)`; depth from the hit; camera sweep math (cursor up -> look up).
**A packing:** display RGBA (RGB ACES, A glow opacity) as HEAD; texels (0,0) = spring (pos.xy, vel.xy), (1,0) = (fract(time), 0, 0, 0.7371); C read masked on those two texels (`isState`). Saved params byte-exact; JSON untouched (its feature tag `sprung-mouse-attractor` is now true).

**Rescues:**
- R1 upside-down: `nuv.y` flipped (funnel now wide-top/narrow-base, accretion band at the bottom); pull target `(0.5 - mouse.y)` so cursor up pulls up. (`:121`, `:26`)
- R2 dead spring -> A texels (`:129-142`, `:282-284`). Verified: state reads back (haveState = 1, pos = cursor) and after a goal jump 0.2 -> 0.8 the position is 0.604 mid-travel (HEAD: raw cursor, never smoothed). Idle cursor (0.5, 0.5) is a zero sweep, so the idle camera is unchanged by this rescue.
- R3 ramp pole + saturation (`:190-198`): inside taps clamped at -0.01 and ramp clamped to [0,1]; `glowC = 1 - exp(-0.25 glow)` carries body and alpha. HEAD body was flat yellow (blue < 0), meanA 0.274; now teal glass, meanA 0.178.

**Ideas in the diff (footprint = pixels changed >12/255 inside the hit area when the idea is zeroed; 288 px, 23746 hit px):**
1. Helical glass flutes (`:45-53`, tactic 3+7) — T5(x/r) ribs on the twisted frame, 0.07 amplitude, +60% on bass. 17226 px, mean diff 37.9/255. Twist slider now changes the pitch (renders twist 0 / 1 / 3), `t` spins them.
2. ~~Refracted sky through the wall (Snell vector refraction)~~ — CUT by the coordinator: 164 of 23,746 funnel px, mean diff 0.75/255 (sparse starfield), so the idea was not findable in the picture. The direction-cell `starAt` helper it required was reverted too; the background stars are HEAD's per-pixel hash again. `u.zoom_params.z` (Chromatic Split) is still consumed by the existing split at the glint/rim, so no dead slider.
3. Step-count AO (`:94-105`, `:205`, §12.2E) — 5 taps, reach 0.08–0.88; darkens the funnel's necks, flute grooves and debris contact. 3709 px, mean diff 6.5/255. (First draft reach 0.02–0.18 changed 5 px — invisible — so it was widened.)
**Formulae:** step-count AO (§12.2E) only. No Cauchy added (already on this file), no Snell (cut), no row repeated. The tornado now carries 2 new ideas: helical glass flutes + step-count AO.
**Measured default-look change:** HEAD meanL 0.198 / stdL 0.257 / meanA 0.274 -> 0.166 / 0.221 / 0.178 (192/288 px, audio 0.4/0.3/0.2); silent 0.118 / 0.192 / 0.165; audio 0.9/0.5/0.8 at 576: 0.208 / 0.259 / 0.186. Cursor UR / LL renders lean the funnel toward the cursor.
**Gates:** precommit gate pass (naga OK, 0 extraBuffer violations — the file no longer touches extraBuffer); `audit:extrabuffer` PASS; dead sliders: x `:32`, y `:62`, z `:185/:210`, w `:31/:52/:173` all read; no NaN.
**Timing:** not re-timed to a tight bound under load; per-hit-pixel additions only (5 `map()` taps for AO, 3 `refract`s); per-step addition in `map()` is ~12 flops for the flutes (288 px frameMs 84–160 across my runs vs a single HEAD run of 116, load-noisy — no usable comparison).
**Open items:** the spring is critically damped at omega 8 as HEAD; real-GPU check of f16 A-texel quantisation on balanced/battery tiers is external. Funnel top is cropped by the frame at default (camera unchanged). HEAD's confinement-ring dashes / arc overlay are still screen-space (left as HEAD). (Refracted-sky idea cut by the coordinator, see idea 2.)

## Real-GPU visual QA: external. All renders above are SwiftShader/minirender.
