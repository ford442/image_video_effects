# NOTES — fork C (gen-liquid-neon-cyber-metropolis, gen-cyber-organic-liquid-neon-pulsar)

Cards + mechanism interrogation + HEAD table: `BRIEFS-forkC.md` (written before any WGSL edit). Scratch/renders/scripts: `/tmp/claude-0/-root-image-video-effects/914950b4-f44b-4d87-a537-edda39759ec7/scratchpad/forkC/` (`metro_cam*.py` = numpy port of `map()`, `vis.py` = % |Δ|>0.02, `mr_perf.mjs` = min-of-drained harness copy, `v/` = idea-off variants). Definitions JSON untouched on both (saved params / features already true; no description change).

## gen-liquid-neon-cyber-metropolis
KEEP VERBATIM held: yes — `map()`, KIFS crowns, neon rib shell, density slider mapping, audio extrusion, gravity warp + ring, Ideas 1–5 code, neon persistence, ACES→0.4545, depth/alpha formulas, the four `zoom_params` reads (x neon, y density, z audio, w warp).
A packing: unchanged — ACES then gamma display RGBA, C read as persistence (`max(col, prev·0.3)`).
Header: `Upgraded: 2026-10-10, 2026-11-18`; `Ideas:` appended (3 ideas + the camera rescue); no JSON change. Definition has no `params` key (only `x-meta.upgrade.params`, defaults 0.5) so `audit:dead-sliders` scanned 0 defs for it — sliders checked by hand: x → glow/neon/apron/traffic/`neonGain`; y → `cityRepSize`; z → `audioAmp`; w → `gravityWarp`/ring. Slider sweep min→max with audio (192, T0=12): x 96 %, y 96 %, z 72 %, w 48 % of pixels change → all live.

**Rescue 1 (L161) — camera clearance. CONFIRMED.** HEAD camera `y = 14 ± 3` at orbit radius 28 sits inside the tower field: numpy port of `map()` over the 125 s period: d < 0.05 for **23 %** of samples (mouse extremes included), within 1.5 of a surface 55 %. HEAD renders at T0=12/30 are flat lilac/cyan walls. New `y = 28 ± 2`: 0.00 % inside at idle (min d 3.5), 0.02 % at bass 1.0, 0.2 % only at bass 1.5 × Audio Reactivity 1.0 (scan `metro_cam3.py`). Default-look change: aerial orbit instead of street-level; the magenta "sky wall" of accumulated glow is gone because rays no longer skim the skyline.
**Rescue 2 (L272) — `pow(negative, 2.0)` in both traffic-lane profiles. CONFIRMED by reading** (`cl.x - 0.45` < 0 on half the street-edge ground); SwiftShader returns the even power (nan = 0) so no gate sees it, real GPUs may NaN it into the persistence history. Replaced by `d*d`; identical value where HEAD was defined.

| Idea | Where | Measured visibility (% px with max-ch |Δ|>0.02 / mean |Δ|) |
|---|---|---|
| 6 neon sign columns (native): 4-cell-wide LED strip per face on ~60 % of faces, bits scroll DOWN with the packets, dark backing, bass flicker | L326–347 | 192: T0 0/12/30 = 3.1 / 12.1 / 3.8 %; 576 (T0 30) 4.3 % |
| 7 roof panel seams (native): panel lattice on up-facing neon skin (n.y>0.85; rib crests only reach 0.75), anchored to the tower cell | L349–357 | 192: 16.3 / 16.4 / 25.0 %; 576: 26.3 % |
| 8 obstruction beacons (native): red lamp on one roof corner per tower, per-tower blink phase (42 % duty), halo | L359–367 | 192: 3.2 / 0.2 / 5.6 %; 576: 2.2 % (local idea; t12 has no lit roof in view) |
| all three | | 192: 19.6 / 28.5 / 29.3 % |

§12.2 rows: none (city nouns: signage, roof panels, obstruction lights). No spring / ripple / IQ palette. Idea 7 is the same on every roof by construction (panel lattice) — it is the dominant new feature of the default picture (see open items).
Timing (SwiftShader, 192², min-of-drained, interleaved, load average 21–32 from sibling forks — **not trustworthy**): min over 4 rounds, HEAD / rescues-only / full = T0: 40.5 / 115 / 95 ms (HEAD inside a tower terminates rays early, so cheaper); T30: 145 / 154 / 147 ms. Ideas-only cost (full vs rescues-only) ≈ 1.0× (all three are one-shot shading on a neon hit). The camera lift costs more rays than HEAD's inside-geometry frames; coordinator re-time alone.
Gates: precommit ✅, `verify-naga-wasm --files` ✅ (30.0), audit:extrabuffer ✅ (file does not use extraBuffer), nan 0 at 192/576, idle/held/audio, A16=1 not needed (A is display RGBA as HEAD).

Open items / flagged:
- The towers are fully skinned by the neon shell (`neonSize` > concrete box on every axis, margin 0.03·rep > the ±0.08 rib), so `mat < 0.5` only occurs on the KIFS crowns and the ground. The window lattice (Idea 5) and the ground ideas (apron, traffic, wet reflections, warp ring) therefore cover a small part of the frame, even smaller from the lifted camera (street slots are 1.4 wide). Not re-plumbed (identity). If the owner wants street-level back, the right fix is a canyon flythrough along a street centreline, not a lower orbit.
- The default picture is pastel: neon skin = `neonCol·1.8·0.5` ≈ 0.9 per channel, then ACES, then another 0.4545 gamma. Left alone (look, not a defect).
- JSON has no `params` array, so the host shows no sliders for this shader (they sit at the 0.5 fallback). Adding `params` mirroring `x-meta.upgrade.params` would expose them; not done (rule: don't invent params).

## gen-cyber-organic-liquid-neon-pulsar
KEEP VERBATIM held: yes — `map()` (field warp, fBM core, Voronoi fibres, smin), scene spin, palette, fibre packets (Idea 2), hotspots (Idea 3), lighthouse beams (Idea 1), Crab strobe / field-line glow, ripple wavefronts, C blend 0.25+mids·0.08 / decay 0.96, chromatic aberration, ACES, alpha, the `mix(bg, col, t/10)` fade, all four saved params (byte-exact; JSON untouched).
A packing: unchanged — HDR display RGB + alpha in A (C colour history), ACES on `writeTexture` only. `A16=1` 8-frame run: nan 0.
Header: `Upgraded: 2026-10-10, 2026-11-18`; `Ideas:` appended.
Slider sweep (192, T0=12, audio): hue x=0.25 90 % (note: x is added twice in `palette`, so x = 0, 0.5, 1 are all the same colour — the slider cycles twice; role kept), fibre y=5 78 %, pulsation z 53–59 %, glow w 68–89 % → all live.

**Rescue 1 (L104–121 helpers, L125–133 dent, L252/261–268 lighting, L339/343 beams) — screen/object frame. CONFIRMED by test.** HEAD cursor-held test at T0=40, 192 px: cursor x=0.2 → dent centroid x=136 px (right half), cursor x=0.8 → x=48 px (left half) = mirrored; at T≈1 within 22 px of the cursor. After the fix at T0=40: left → 83 px, right → 113 px (correct order; changed area 40 %/42 % because the dent now sits on the body). Also fixed in the same change: diffuse/spec/rim use the un-spun normal and position (HEAD: flat brown ball at T=40, now a lit sphere), and the beam axis/`facing` use `unspinObj(magAxis)` so the beams pass through the hotspots (the hotspots live on the object-frame axis). Identical at t = 0.
**Not rescued, flagged (magnitude rule):** `col = mix(bg, col, clamp(t/10, 0, 1))` is inverted — the sphere is hit at t ≈ 2.4 so the surface keeps 24 % of its colour (idle meanL 0.12). A scratch fix (`v/pulsar_fadefix.wgsl`) gives idle meanL 0.44, cream-pastel. Owner's call; the new ideas are added after the fade, so they are not attenuated.

| Idea | Where | Visibility (192, T0 2 / 12 / 25 / 40; 576 T0 12) |
|---|---|---|
| 4 spark carousel (native, drifting subpulses): six sparks circulate on a broad ring (ac ≈ 0.86 ± 0.08) about each cap at a Pulsation-Speed-tied rate | L300–307 | 1.3 / 5.1 / 6.3 / 2.1 %; 576: 2.9 % (local idea: depends on how much of the pole faces the camera) |
| 5 dipole L-shell rings (native): rings at geometric L = 1/(1−c²) shells, poleward drift, faded at equator and in the hotspot | L308–316 | 7.0 / 29.9 / 29.0 / 40.8 %; 576: 17.1 % |
| both | | 7.5 / 33 / 31.5 / 42 % |

§12.2 rows: none (Airy disc deliberately unused — the body fills the frame, a point-source PSF would be a costume). Both ideas are in the core (non-fibre) branch only and are post-fade additions.
Default-look change (meanL/stdL HEAD → new, idle 192, 20 frames): 0.121/0.082 → 0.146/0.116; audio 0.200/0.134 → 0.233/0.175.
Timing (load 20–32, untrustworthy): min over rounds head 922 ms, rescue-only 670, full 960 at 192², T0=12. Ideas are one-shot shading on a hit pixel; the rescue adds 2 `spinObj`/`unspinObj` pairs (~8 sincos) per `map()` call out of ~70 calls/pixel, small next to the fBM + 27-cell Voronoi inside the same call. Coordinator to re-time alone.
Gates: precommit ✅, `verify-naga-wasm --files` ✅, `audit:dead-sliders` ✅ (1 def scanned, 0 new), audit:extrabuffer ✅ (unused), nan 0 idle/held/audio/A16.

Open items: real-GPU look for both default looks (metropolis aerial camera + roof grid; pulsar ring bands on a nearly black body); sparks at 576 are small; the exposure inversion above; the hue slider cycling twice.
