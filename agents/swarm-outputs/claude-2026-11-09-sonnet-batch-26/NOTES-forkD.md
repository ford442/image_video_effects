# NOTES — Fork D (sonnet/batch-26): fractal-glass-distort-bilateral, alpha-multi-layer-glass

All evidence is SwiftShader (`agents/mr.mjs`, SRC=img, A16=1, T0=2). **No real-GPU visual QA.** Default params, 192 px, 24 frames/3 s: idle = cursor 0.5,0.5 audio 0; held = cursor 0.3,0.6 down, audio 0.4,0.3,0.2. Scratch: scratchpad/forkD/ (r.sh, rt.sh = grainy source via `agents/mr_tex.mjs` GRAIN=0.12, sweep/, scr/ ablation copies).
Gates (both files): `wgsl_precommit_gate.py` naga OK / bindgroup OK / no pasted header; `audit:extrabuffer` PASS (neither file touches extraBuffer any more); `audit:dead-sliders` 0 new. JSON files **not edited** (see each section).

---------------------------------------------------------------------------------------------------
## fractal-glass-distort-bilateral (1st pass)

**Kept verbatim:** 4 params + roles (rotation_speed = per-layer twist angle, scale 0.9–1.3, refract_strength ×(1+0.3·bass), bilateral_mix = bilateral amount + flat ±0.03·mix R/B split + sharp window at the cursor); the 4-layer rotate/scale/sine recursion around the cursor pivot (maths unchanged, factored into `glassWarp`); click-ripple pre-warp; sigma 0.1→1.0 with ×0.2 window at the cursor; alpha formula; ACES; A = display RGBA; 7 % C ghost.
**A packing:** ACES display RGBA (unchanged). Texel (0,0) = (pivot.xy, pivot vel.xy), texel (1,0) = (fract(lastTime), heldEnv, 0, 0.7371) = STATE; C is not read on those two texels (`isState`).

**Ideas in the diff** (`// ── Idea n` comments)
1. Fold caustics (tactic 3, no §12.2 row): `public/shaders/fractal-glass-distort-bilateral.wgsl:119` — two forward differences of the same recursion → det(I+∇d) → focus = clamp(1/|det|, .5, 4) → gain `(1+0.40(focus−1))·0.99` on the transmitted colour. Honest note: at the default / even refract 0.9 the map does not fold (det stays ~0.4–1.6), so this reads as soft light pooling (±~16 % low-frequency luminance), not thin filaments; filaments need folds the 4-layer sin recursion barely produces. Normalised so the default meanL stays within 0.004.
2. Cauchy dispersion along the bend (§12.2F Cauchy dispersion): `:178` — R/B sampled at distortedUV + dispUV·(n(λ)/n(550nm) − 1), n = 1 + 0.16/λ² (blue ≈1.2×, red ≈0.89× of green), added to HEAD's flat split. Fringe now follows ripple crests (visible on the black blob in the 576 renders).
3. Joint depth-range bilateral (tactic 1): `:149` — weight = exp(−|off|²/2σs² − |Δrgb|²/2σc² − Δz²/2σd²) (one exp per tap), σc 0.3→0.2, σd 0.12; tap radius 0/1/2 by sigma (<0.30 / <0.72 / else) instead of 2–3 wasted rings; tap spacing `max(1, res.y/256)` px.
**Formula rows:** Cauchy dispersion (F) only (batch budget: this file + refraction-shards). Ideas 1, 3 tactic-derived.

**Rescues (HEAD was wrong)**
- R1 dead/racy spring (extraBuffer[133..138], single writer at (0,0), zeroed every frame) → A-texel pivot spring, ω = √42 (HEAD's stiffness, critically damped), shared dt `clamp(fract(time−st1.x),.001,.05)`, f16 rest-snap; the click `held*0.2` pop is now an eased envelope (`heldEnv`, rate 12/s) also used for alpha. numpy float16 round-trip: step response err 0.0041 @1 s, 2e-4 (= f16 quantisation of the target) @2 s, vel 0; moving-then-stopped target settles to 5e-5; ±0.002 jitter target ends within 3e-5.
- R2 bilateral discarded for R/B + sub-pixel sigma: HEAD `color=(rawR, filtered.g, rawB)`; mean|Δ| mix 0→1 with the split removed = **0.0004** (G only). Now the filtered base reaches all channels (raw R/B taps add only their fringe delta). Bilateral-only effect on the smooth test image is still small (mean|Δ| 0.0011 @192, 0.0007 @576 — the test photo has nothing to smooth); on a grainy source (rt.sh, GRAIN 0.12, 576 px, `m_g.png`) mix 0 keeps the grain and mix 1 removes it while the blob edge stays crisp (and the HEAD default image still shows the grain).
- R3 audio inside `time*(1+mids·0.5)` / `time*(1+treble·0.5)` (teleport by time·Δaudio) → `time + 0.6·audio` bounded offset. Identical at audio 0.
- R4 ghost: HEAD mixed display-space C into pre-ACES colour (domain mismatch, unclamped); now `mix(aces(color), clamp(prevC,0,1), 0.07)`, masked on the state texels. Inherited C = 50: HEAD first frame meanL .542 (vs .510), NEW .465 (vs .462).
- (Fix round: an earlier R5 wrote the depth sampled at the WARPED uv. Reverted at coordinator request — writeDepthTexture is HEAD's passthrough sampled at the pixel's own `uv` again; `centreDepth` (warped uv) is only the bilateral range-weight centre. Re-render after the revert: 192 idle .506/.162/.739 and held .497/.172/.896, byte-identical image (max|Δ| 0 over all three panels) to the pre-revert build.)
- **Not changed, flagged:** `rotation_speed` is a static per-layer ANGLE, not a speed (largest mover: rot0 vs default mean|Δ| 0.098). A JSON rename would touch `params`; animating it would change the identity. Coordinator's call.

**Default-look change: yes (small).** 192 idle meanL/stdL/meanA .510/.164/.739 → .506/.162/.739; held .498/.176/.890 → .497/.172/.896 (A larger: eased held). 576 idle .510/.164/.739 → .506/.163/.739 (final build); moving-cursor held long run (90 fr/6 s) .495/.176/.787 → .523/.167/.779 (spring lags the sweep). Colour: more visible R/B/Cauchy fringe, soft light pooling.
**Cost:** HEAD radius 2–3 (25–49 taps) → 0–2 (1–25 taps) + 2 extra warp evals + depth taps. Re-timed alternately at 512 px, 4 rounds under load ≈9–10: new/head = .73, .59, .95, 1.0 → median ≈ .8× (not ≥1.25×). Load-noisy.
**Visual risk to check on a real GPU:** caustic gain pools (max gain ≈ 2.05 → "light disc" patches at refract ≥ 0.9, held); the bilateral smoothing is only visible on textured photos at mix ≥ 0.5; resolution-aware tap spacing (≥2.25 px at 576, 4 px at 1080) may look soft on 4K.
**JSON:** unchanged. features already carry `upgraded-rgba`, `depth-aware` (now genuinely used), `audio-reactive`, `temporal`; no idea-named tags added.

---------------------------------------------------------------------------------------------------
## alpha-multi-layer-glass (2nd pass)

**Kept verbatim:** 4 params + roles; per-pane noise surfaces + parallax around the cursor (Idea 1), rotated 4-tap frost (Idea 2), Beer-Lambert pane edges (Idea 3); Schlick Fresnel pseudo-angle; transmittance-weighted stack; plateWave; click ripples; spec; ACES; semantic transmittance alpha; raw pointer (the earlier raw-pointer fix stays). Header: `Ideas:` extended with 4 + 5, `Upgraded: 2026-11-09` added (it had none), `Rescued:` + `A packing:` lines.
**A packing:** ACES display RGBA (unchanged), C read as display colour (mixed 8–13 % in display space, now clamped).

**Ideas in the diff**
4. Inter-pane ghost reflections (tactic 2/3, no §12.2 row): `alpha-multi-layer-glass.wgsl:193` — per pane pair one extra tap at `uv − 2(offset_i + offset_{i−1})`, bright-pass (luma−.55)/.45, weight `min(F_i·F_{i−1}, .5)·6·T`, added to the stack. Reuses `fresnel` + `paneOffset` of both panes. Measured: ablation (ghost off) 3.4 % of pixels > 0.02 at 192 / 7.4 % at 576 (2.6 % > 0.05, max 0.28) — shows as pane-shaped glints/second image of the white blob; subtle by nature (R1·R2), clearer on photos with real lamps.
5. Press dimple: `:93`, used at `:145` — slope s(r) = (r/0.12)·exp(½(1−(r/0.12)²)) × smoothstep(.35,.2,r) × (0.5+0.5·held); front pane takes it fully, deeper panes ×(1−0.3·layer). Replaces HEAD's unit-slope cone that is singular at the cursor (idle cursor = screen centre; HEAD's held-cursor render has a visible pinwheel / bite out of the black blob). Measured: held at the centre, 13.9 % of pixels > 0.02 differ from the dimple-off version.
**Formula rows:** none (both tactic-derived). Henyey–Greenstein deliberately not used (frost radius 0.6–2 px at 192 → an HG lobe would be invisible; would have been an invisible idea).

**Rescues**
- R6 `chromatic` slider dead: relative split 3e-5 UV (0.02 px); sweep ch0/ch1 vs default mean|Δ| **0.0001** → now `chromParam·(0.40+mids·0.12)`: 0.0026 / 0.0059 (p99 .020/.043), ~1 px fringe at default@192, clear colour fringe at max (crop `m_chrom.png`).
- R7 `ior` nearly dead (mean|Δ| .005/.006, only grazing Fresnel R0): pane bend now × `(ior−1)/(0.45+0.08·layer)` — equals 1.0 per layer at ior 0.5, so the DEFAULT offset is unchanged; ior 0/1 vs default now .0142/.0154. 
- R8 inherited C unclamped: C = 50 gave meanL .487 for a frame (HEAD) vs .424 (new; normal .433).
- Existing HEAD singularity left alone: `normalize(vec2(normalX, normalY))` of the fbm pair is a pinwheel where both components ≈ 0 (two points in pane 0 at the default time, visible in the HEAD images too). Not part of this pass.

**Default-look change: yes (tiny).** 192 idle meanL/stdL/meanA .428/.159/.826 → .434/.163/.826; held .434/.160/.833 → .438/.164/.834; HEAD-vs-NEW default mean|Δ| 0.0083 (p99 .078, mostly the chromatic fringe + ghost glints). 90-frame moving-cursor run .433/.160/.823 → .438/.165/.822.
**Cost (fix round, honest interleaved timing):** +2 ghost taps. 576 px, HEAD/NEW alternated each round (order flipped every round), 8 rounds each for idle and held, machine load 2–44 (very noisy). Before trim: idle ratios .98 1.13 1.12 1.21 .71 .83 1.34 1.17 → median 1.13; held .95 .92 1.26 1.06 1.81 1.52 1.33 1.03 → median 1.16. Trim applied: the layer-0 ghost tap (weight always 0) is skipped with a uniform `if (layer > 0)` — output byte-identical (max|Δ| 0, 192 idle + held). After trim: idle .76 1.33 .88 1.14 1.37 .94 1.15 1.2 → median 1.15; held 3.61 .76 .83 1.16 1.96 .87 1.04 1.18 → median 1.10. Honest figure ≈ 1.1–1.15× HEAD (not above the 1.25× limit; the +25–30 % seen by the reviewer is inside the round-to-round spread 0.7–1.8). Per-pixel cost is dominated by the 3×2 three-octave fbm; no further trim was needed, ideas 4 and 5 untouched.
**JSON:** unchanged. Left `depth-aware` (it only passes depth through, never was real) — flagging rather than removing; description not touched (search-index length).

## Open items / for coordinator
- Idea 1 of the fractal glass (caustic) is soft pooling, not filaments — keep, or reduce k (0.40) if it reads as muddy on a real GPU.
- `rotation_speed` naming (angle, not speed) — JSON rename out of scope.
- State-texel sentinel 0.7371 is shared with the other A-texel shaders (self-heals within ~0.5 s on a direct switch).
