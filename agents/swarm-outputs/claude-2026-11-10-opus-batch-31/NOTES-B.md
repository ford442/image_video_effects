# opus/batch-31 — fork B notes (directional-blur-wipe, kimi-ripple-touch, vaporwave-horizon)

Measurement: SwiftShader mini-renderer, 160², synthetic photo source (`SRC=img`), JSON default params.
Δ = % of RGB pixels with max-channel |Δ| > 0.02, final file vs the same file with that one idea switched off.
Frame times are SwiftShader at 320² with three other forks rendering concurrently — noisy. directional-blur-wipe and kimi were not slower; vaporwave-horizon was about 2× (see below).
Saved `params` untouched in all three JSONs (no JSON edits at all). Real-GPU visual QA: external.

## directional-blur-wipe (second pass)
- Kept verbatim: pointer-anchored line + angle lean, split_pos/angle/strength/samples roles, wipe ramp, comet shutter, highlight streak weights, treble chroma taps, click flashes, depth scatter.
- A packing: ACES display RGBA (unchanged); C is now read back (exact `textureLoad`) as display history.
- Ideas added:
  4. luma-keyed wipe front (`lumaKey` shifts `dist`) — Δ 8.0 % at default.
  5. stroboscopic multi-exposure: 3 discrete ghost taps past the comet, mids deepen — Δ 22.0 %. (A first try that pulsed the in-comet tap weights was 0.0 % at default strength — the comet is only ~0.025 uv long — so it was replaced by ghost taps beyond it.)
  6. exposure persistence: blur side mixes with C (0.78 + bass·0.1, display domain, no re-tonemap) — Δ 14.7 % with a circling pointer; it converges to the same image when the pointer is still.
- Rescue: uv now pixel-centred.
- Timing (ms/frame, 320²): HEAD 110/131/63, new 48/44/41.

## kimi-ripple-touch (first pass)
- Kept verbatim: packet_source gravity-capillary packets, kLocal / vg / vp dispersion, RGB group-velocity refraction, phase colour ramp, param roles (x→kLocal, y→k0, z→sigma, w→amp; the names don't match these roles, but that was already so at HEAD and is left alone).
- A packing: raw sim state, r = h·0.5+0.5, g = v·0.5+0.5 with **v = Δh·8** (was Δh·60, which capped Δh at 1/60 per frame), b = crest foam (was vg/2.5, written but never read), a = phase.
- Rescues:
  - The sim never propagated. The whole update was ×1/3600, so h settled near 0.004. At HEAD, holding the mouse down vs up gave Δ 0.0 % and two click ripples gave 0.1 %. The update now uses c² = clamp(0.25vg+0.12vp, 0.02, 0.45) per frame (CFL-bounded) and sources ×0.12. Clicks give 10.3 % and mouse-down 7.5 % vs idle.
  - A zero-cleared C was decoded as h = v = −1 (a full trough), so the screen had a dark-blue wash for seconds after the effect loaded. An all-zero texel now means flat water.
  - The ripple loop now uses `min(config.y, 50)`, so empty slots at (0,0) no longer emit during the first seconds.
  - The bass packet was aged by time·0.15 forever (dead after about a minute). It now re-launches every 8 s.
  - Header gains `mouse-driven` (the JSON already had it).
- Ideas added (Δ measured with the mouse held down and circling):
  1. caustic focusing from −lap — Δ 7.5 %.
  2. low-sun specular glint from the grad normal, treble tightens the lobe — Δ 6.5 %, 0.0 % on flat water (max 0.008).
  3. crest foam memory in A.b, decay 0.965 per frame — Δ 12.2 %.
- Timing (ms/frame, 320²): HEAD 62/68/62, new 52/24/21.

## vaporwave-horizon (first pass)
- Kept verbatim: horizon = mouse y, curve = mouse x · warp, perspective 1/dy grid mapping, Beer-Lambert sky haze and floor fog, all 4 param roles.
- A packing: ACES display RGBA (HEAD wrote no A).
- Rescues:
  - No `dataTextureA` write, and no ACES despite the `upgraded-rgba` tag.
  - Hardcoded alpha 0.95 / 0.8: alpha is now sky transmission / sun coverage, and fog plus line coverage on the floor.
  - Bass multiplied grid speed inside time·speed, so at large t the grid jumped whole cells. Bass is now a bounded +0.08 phase nudge plus sun and halo pump.
  - The floor reflection sampled raw photo rows rather than the squashed sky shown above it.
  - uv is pixel-centred, and the depth store no longer smuggles alpha into .w.
- Ideas added:
  1. striped retro sun on the horizon (bands widen toward its base, scroll with grid speed, bass pumps the radius) — Δ 24.9 %.
  2. two-tone neon line bloom: distance-filtered core plus halo, cyan longitudes and magenta latitudes, replacing the `step(0.45)` mask — Δ 46.9 %.
  3. the mirror floor reflects the displayed sky (shared `sky_color`, so the sun drops a column onto the floor, rippled by the grid cells) — Δ 40.5 %.
- Default look changed noticeably (sun, ACES, two-tone grid); the identity (photo sky over a neon perspective floor) is kept.
- Timing (ms/frame, 320²): HEAD 9/23/13, new 24/36/41. That is about 2× on paper, but HEAD was the cheapest shader here: the floor now calls `sky_color` a second time for the reflection, plus the sun. Re-time on a real GPU.

## Gates (each file)
`wgsl_precommit_gate.py --files` OK ×3. `verify-naga-wasm.mjs --files` OK ×3. `audit:dead-sliders` on the 3 ids: 0 new. `audit:extrabuffer`: PASS.
The audits rewrote `reports/*audit*` and `reports/wgsl_precommit_report.json`; those are shared files, and the coordinator decides what to stage.
