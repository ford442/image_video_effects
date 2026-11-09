# NOTES — Fork C (sonnet/batch-25): glass-wall-prismatic, gen-depth-refracted-liquid-stained-glass

Renders: scratchpad/forkC/ (fin_*_{192,576}_{idle,held}.png final; *_head_* HEAD; gd_abl_* ablations; m_gw_cmp576_*.png, m_gd_cmp576_*.png, m_gw_sliders.png, m_gd_sliders.png; spring_f16.py = float16 emulation; mean.py = panel-0 mean RGB). No git operations performed; only the two WGSL, two JSON and these notes were touched. The audits rewrite reports/* (coordinator reverts).

---------------------------------------------------------------------------------------------------
## 1. glass-wall-prismatic (1st pass) — `Upgraded: 2026-11-09`

**Kept verbatim:** 4 params and roles (grid_size → tile count, curvature → refraction offset, dispersion → Cauchy B (+bass), thickness → absorption); 4-wavelength `refract()` loop with Cauchy IOR; bevel profile; tilt toward the lamp (influence 0.85, mids/hold gain); white lamp lobe `pow(.,36)` (now per channel); mortar; transmission/alpha formula (unchanged); capped click ripple fronts + cursor ring; ACES; A = display RGBA; depth passthrough; orbit-unless-pressed pointer behaviour (HEAD's evident intent).

**A packing:** display RGBA (ACES) in A and writeTexture. Texels (0,0) = (pointer pos.xy, vel.xy), (1,0) = (fract(lastTime), click impulse, prevDown, 0.7371 sentinel) are STATE in A only (writeTexture unaffected); C read as history is masked on those two texels.

**Rescues**
- R1 pointer state (`glass-wall-prismatic.wgsl:71`): extraBuffer[133..138] spring/prevDown/impulse written by thread (0,0) and read by all others in the same dispatch; extraBuffer is re-uploaded zeroed each frame → tilt point ~(0,0)/racy and click ring racy in the app (minirender persists extraBuffer so HEAD looked fine there). Now A-texel state with sentinel; every thread integrates the same dt-based under-damped spring (K 600, c 12 ≈ HEAD's per-frame 0.18/0.82: ω≈24, ζ≈0.24), velocity clamp ±3 uv/s (= HEAD ±0.05/frame), f16 rest-snap, impulse `exp(-3.7 dt)` (= 0.94/frame), prevDown press-edge. Orbit Lissajous kept verbatim. float16 round-trip emulation (spring_f16.py, 60 & 30 fps, idle→held→release): settle error 1.1e-4, residual |vel| 0, orbit lag ≤2e-3 — no stall.
- R2 spectral white balance (`:185`): the four `wavelengthToRGB` weights sum to ≈(2.5, 1.0, 1.0) and only a scalar `2.2/Σabs` followed, so a tile that refracts nothing returned ≈(1.5,0.5,0.5)·scene. Measured on the minirender photo (mean RGB 0.433,0.400,0.392, chroma 0.128): HEAD → (0.646,0.361,0.351) chroma 0.315 (red cast, greens wiped); now → (0.503,0.487,0.500) chroma 0.103 (neutral preserved; ACES lift only). Division is by the per-channel basis sum at the DEFAULT thickness so Thickness keeps its role relative to the default (thk 0 → cooler/brighter (0.537,0.547,0.584), thk 1 → warmer/darker (0.470,0.429,0.416)).
- R3 history in display space (`:241`): HEAD mixed ACES-display C into pre-ACES radiance (tone-mapped twice); now `mix(ACES(x), C, 0.1+mids·0.06)` after ACES; zero weight on the state texels.

**Ideas (all findable from the `// ── Idea n` comments)**
1. Cast-glass wedge per tile (`:159`) — hash(cellID) tilt added to the normal before the Cauchy loop; flat tile interiors now refract/fringe differently tile to tile. Rides curvature/dispersion sliders; no new param.
2. Fresnel–Schlick bevel sheen (`:227`, §12.2F) — promotes the HEAD `fresnel` (alpha-only) to colour: reflect view about the wedged/tilted normal → soft-box (×7) + sky gradient, taken out of the transmitted light, zero in mortar.
3. Prismatic lamp (`:204`) — lamp lobe evaluated per channel with the facet slope scaled by (n(λ)−n(540))/(n(540)−1) from `cauchyIOR`; coloured rim ring of tiles around the lamp (blue inner / warm outer) instead of one white blob.
Formula rows: Fresnel–Schlick (§12.2F, budget C/A-chroma-lens ✔). Ideas 1, 3 are tactic-derived. Snell/Cauchy rows not newly used (refract()/cauchyIOR already HEAD).

**Default look changes: YES (R2 mainly).** 192 idle meanL/stdL/meanA 0.453/0.149/0.937 (HEAD, 24 frames) → 0.497/0.161/0.937 (new, 90 frames @60 fps); 192 held+audio 0.460/0.140/0.953 → 0.542/0.138/0.945; 576 idle 0.411/0.155/0.901 (HEAD, 90 frames) → 0.479/0.172/0.901; 576 held+audio 0.444/0.146/0.913 (HEAD) → 0.522/0.154/0.906. Brighter because the red cast no longer eats G/B and ACES lifts a neutral mid-grey; chroma 0.315 → 0.103 (photo colours back).
**Gates:** naga ✅ (precommit gate), extraBuffer audit ✅ (file no longer touches extraBuffer), dead-slider audit ✅ (4 sliders live: grid/curv/disp/thk sweeps in m_gw_sliders.png), 192 + 576 idle/held/audio no NaN. Timing 192 (back-to-back, 2 rounds, load-noisy: 4 forks rendering): HEAD 14–17 ms vs NEW 17–28 ms then 8–11 ms vs 11–20 ms HEAD — ≈1.0–1.2× quiet round (+2 hash12, 3 pow, 1 reflect, 3 normalize).
**Open:** (a) pointer behaviour is HEAD's: press-and-drag steers the tilt, hover alone does not (orbit unless pressed) — taste call, left. (b) all A-state verified by float16 emulation only, no real rgba16float GPU. (c) lamp-ring colour saturation (LAMP_FRINGE 2.4) and glint intensity (soft-box ×7) are eyeballed on a blurry synthetic photo — worth a real-photo look. (d) tile identity flips at the borders while ripples shift `scaledUV` (HEAD behaviour; wedge follows it).

---------------------------------------------------------------------------------------------------
## 2. gen-depth-refracted-liquid-stained-glass (2nd pass) — `Upgraded: 2026-10-10, 2026-11-09`

**Kept verbatim:** all 4 params and roles; polar fold, depth-gradient normal refraction, threePointLighting, thinFilmTint, ornamentSample; ALL four HEAD ideas (came highlight, caustic glow, lead lattice, solder nodes); click flex ripples, held gain, C tint ghost, ACES, semantic alpha, relief depth. `Ideas:` line extended, nothing removed. **A packing:** unchanged — A/C = ACES display RGBA, no state texels.

**Rescues:** none required (no dead control, NaN, packing lie, pointer-state bug; ACES input ≥0). Verified at HEAD before editing.

**Ideas** (card ideas 1-3 are numbered 5-7 in the WGSL because HEAD's comments already use Idea 1-4)
5. Beer–Lambert pigment absorption (`:206`, §12.2F) — T = exp(−σ(path−ref)), σ=(1−hue2rgb(materialHue))·k(chroma), path=(0.30+0.70(1−depth))·(0.45+1.1·wisp)/max(normal.z,0.35); relative to BL_REF_PATH 0.65, clamped [0.2,1.6]. Far/steep glass richer and darker, near/flat paler. Ablation (576 idle) changes 25 % of pixels by >0.02 (mean |Δ| 0.015, max small: tonal).
6. Antique-glass wisps (`:193`) — domain-warped `vnoise` (smooth lattice noise) in the folded sample_uv space shifts materialHue ±0.10 and thickness ±55 %; mirrors with the facets. Ablation: 38 % of pixels >0.02 (mean |Δ| 0.018, none >0.08: soft streaks inside panes, visible in gd_wisp_zoom.png).
7. Grisaille trace line (`:221`) — dark brown vitreous-paint line where the depth slope (gradient/(2·eps), so the Bevel slider only widens it) exceeds a threshold; multiplicative so the chromatic-edge fringe still tints it (first version mixed to brown and overpainted the Chromatic slider's fringe — fixed); dry-brush density from `vnoise(sample_uv·70)` (hides depth-texel stairs); adds 0.2·trace to alpha coverage. Ablation: 2.2 % of pixels change, 2.1 % by >0.08 (thin high-contrast lines).
Formula rows: Beer–Lambert (§12.2F, budget gen-depth/frost ✔). 6 and 7 tactic-derived.
**Default look changes: modest.** 192 idle meanL 0.415 → 0.378, stdL 0.128 → 0.132, meanRGB (0.481,0.353,0.411) → (0.442,0.316,0.375), chroma 0.152 → 0.179; 192 held 0.433/0.122 → 0.403/0.120; 576 idle 0.420/0.128 → 0.396/0.131, held 0.436/0.119 → 0.417/0.120. meanA 1.0 unchanged (source α=1).
**Gates:** naga ✅, extraBuffer ✅ (untouched), dead sliders ✅ (facet/bevel/drift/chroma sweeps, m_gd_sliders.png), no NaN at 192/576 idle/held/audio. Timing 192 back-to-back: round 2 HEAD 15 ms = NEW 15 ms (round 1 11 vs 19, load noise); +4 `vnoise` (16 hash12) + 4 depth-free ops.
**Open:** (a) corner/edge flat radial colour bands from the `sample_uv` clamp at r>1 left untouched (identity/taste). (b) grisaille shows stair-steps on the synthetic hard-edged depth; real estimated depth maps are soft — check on a real photo/depth. (c) the shared pre-ACES `mix(col, prevTint*0.9, …)` (4–6 %) left as HEAD. (d) at Bevel 1 the trace is fat (width rides the sampling radius by design).

## JSON
- glass-wall-prismatic: features += `upgraded-rgba` (ACES + ideas implemented); `feedbackPacking` string documents the state texels; params/tags byte-exact.
- gen-depth: features += `audio-reactive` (plasmaBuffer[0].xyz modulates refraction, hue, caustic, came), `upgraded-rgba` (header already claimed it; the JSON lacked both tags); params/tags byte-exact.

## Formula names per file (for COORDINATOR_REVIEW)
glass-wall-prismatic: Fresnel–Schlick (F). gen-depth: Beer–Lambert (F). No other §12.2 rows used.
