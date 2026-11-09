# NOTES — Fork D (sonnet/batch-24): data-stream-spectral, vaporwave-horizon-prismatic, audio-voronoi-gabor

All three were first-pass. Cards + mechanism interrogation: BRIEFS-forkD.md (written before any WGSL edit). HEAD = origin/main c37e2fb0 + prelude commit 7d29bf79. All renders: SwiftShader via `agents/minirender_img.mjs` (synthetic photo + depth), machine load avg ≈ 10 the whole time ⇒ every frameMs is rough. **No real-GPU visual QA was done.** Files in scratchpad `forkD/` (m_str_cmp.png, m_vap_new.png, m_vap_576.png, m_vor_cmp.png, vor_new_576_p0.png, dbg/*).

Gates (all three): `wgsl_precommit_gate.py` ✅ naga OK / bindgroup compatible / 0 extraBuffer violations / 0 pasted headers; `npm run audit:extrabuffer` AUDIT PASS; `npm run audit:dead-sliders -- --files …` 0 new dead sliders (and grep: each of zoom_params.x/y/z/w consumed once in each file); NaN 0 in every render (192 + 576, idle + held cursor, audio 0 + 0.4/0.3/0.2, several T0).

Formula rows used (budget in COMMON): data-stream-spectral = Schmitt-trigger lock + Dropout bursts (§12.2B); vaporwave = Energy-conserving bloom (§12.2F); audio-voronoi-gabor = none (tactic-derived). Cauchy (offered to stream) NOT used.

---------------------------------------------------------------------

## data-stream-spectral  (`public/shaders/data-stream-spectral.wgsl`, 224 lines; JSON advanced-hybrid)

**Kept verbatim:** 4 params + roles (speed→flow, density→strip count, turbulence→cursor/click x-shear, glow→digital tint/bright cells/alpha); fp128 flow phase; strip hash/rand; the four band kernels + tints; head packet; bright-cell flash; click wake; band-3 `color − blur·0.5` (clamped before ACES); ACES; semantic alpha; C.rgb packet trail.
**A packing:** A.rgb = ACES display RGB (unchanged); **A.a = per-strip lock latch** (HEAD wrote the display alpha there; C.a was never read, so nothing else consumed it). writeTexture alpha unchanged.

**Rescues**
- R1 (line 84) dead spring removed; cursor is the raw cursor. HEAD already behaved exactly like this every frame (`extraBuffer[138]>0.5` never true), so it is bit-identical to HEAD's real behaviour. Header no longer claims "spring mouse [133..138]".
- R2 (line 95) `fftStrip = plasmaBuffer[1..8]` was always 0 → replaced by a live 3-band tilt across strip index (bass left → mids centre → treble right). At audio 0 identical to HEAD (fftStrip was 0).

**Ideas in the diff**
1. Schmitt-trigger stall lock (§12.2B), line 102: drive = `vnoise1(stripIdx·13.1 + 0.45 t) + 0.15·bass`; latch ON > 0.74, OFF < 0.52; previous state read from exact `textureLoad(dataTextureC).a`; written to A.a. Locked strips run the scroll/packet clock at `floor(t·6)/6` (stutter-step) and hold ≥0.9 digital tint (`glowEff`, also drives bright cells + alpha mix).
2. Dropout bursts (§12.2B), line 187: per strip+epoch (1.25 s, staggered by `rand`) hash fires with p = 0.07 + 0.35·treble; in the strip's image-space coordinate the data is dimmed ×(1−0.92·tail) behind a white leading edge, tail `exp(−12 d)`, edge `exp(−140 d)`; smooth epoch in/out so nothing pops. Scrolls with the content.

**Default-look change:** audio 0 + idle cursor: meanL/stdL/meanA HEAD 0.307/0.132/0.269 → 0.280/0.126/0.288 (T0=2); T0=20 held+audio 0.306/0.132/0.280 → 0.281/0.126/0.325. Visible: ~20 % of strips are green-locked at any time (scratch debug of the latch: 0.208 of pixels at silence; 0.45 at bass 0.8/mids 0.3/treb 0.2 after lowering the bass kick from 0.25 to 0.15), ~5 strips carry a burst tail. Debug view of (tail, edge, lock) confirmed geometry: tails run above the edge (content moves down).
**Cost:** frameMs HEAD→new 56→22 / 22→11 (interleaved, load-noisy; new ≈ HEAD within noise, ~+1 `textureLoad` already existed).
**Open items:** stale `C.a` from the previously-active shader can start strips locked until their drive drops below 0.52 (self-heals within ~1–2 s); lock fraction at loud sustained bass is high (45 %) — tune on a real GPU with real music; bursts and locks are only subtly visible at 192 px (strips ~3 px wide) — view at ≥576.

---------------------------------------------------------------------

## vaporwave-horizon-prismatic  (`public/shaders/vaporwave-horizon-prismatic.wgsl`, 279 lines; JSON advanced-hybrid)

**Kept verbatim:** sky gradient, striped sun + glow, perspective grid math (zDepth, gridU/gridV, curve, line-width law), 4-band Cauchy reflection loop (no new Cauchy), neon cyan/magenta colours, **near-floor fog law (see open item)**, ripple offset/glow, 0.06 history persistence, scanline, ACES, alpha model, 4 params + roles, horizon-from-cursor-Y / curve-from-cursor-X.
**A packing:** ACES display RGBA (unchanged) + **state texels** A(0,0) = (fract scrollPhase, heldSmooth, 0, 1), A(1,0) = (fract lastTime, 0, 0, 0.7371 sentinel). `historyAt` masks those two texels; their *output* pixels are normal (writeTexture is separate). B unused.

**Rescue**
- R1 (line 117) held scroll jump. HEAD: `gridV += time·gridSpeed·heldBoost` ⇒ pressing shifts the phase by 0.5·t·gridSpeed (≈72 units at t=100) and the sun popped 1→1.5× radius in a frame. Now the phase is integrated (`fract(phase + dt·gridSpeed·(1+0.5·heldSmooth))`, `heldSmooth` eases in 0.15 s, same dt for every thread from C texels). **Verified numerically** (debug copy outputting the state): idle phase after 10 s from T0=2 = 0.400 for both 60 and 120 frames = HEAD's `fract(12·1.45)`; held ramps heldSmooth→1.0 with no teleport (0.53/0.59 at 6/12 fps differ only by rectangle-rule error of the 0.15 s ease). Bonus: dragging the Grid Speed slider no longer teleports the grid.

**Ideas in the diff**
1. Perspective-filtered grid, `lineCov`/`gridAt` (lines 52–86): analytic footprint (∂V/∂y=−K/dy², ∂U/∂x=K/dy, ∂U/∂y=−2cK−x_rK/dy²); line widened by fw and amplitude `clamp(lw/fw, lw, 1)`; intersection tint falls back to the mean distance. Foreground (fw ≪ lw) is HEAD. The cyan speckle band at the horizon (aliasing, visible in HEAD 192 and 576) becomes a faint teal haze.
2. Sun reflection on the mirror floor (line 228): striped half-disc re-evaluated at the mirrored point (sky gradient/stripe law reused), horizontal glitter rows (`sin(260 dy − 2.2 t)` shift), narrow glitter path with row hash, bass/ripple lift. Added into `floorBase` so the existing fog law still applies.
3. Energy-conserving phosphor bloom (§12.2F), line 193: grid colour `mix(src, blur8, 0.4)` — 8 analytic taps on two rings (0.007/0.016 of frame height, weights sum to 1), so the halo is paid for by the line core. No history needed. Attribution render (sun off / bloom off) confirmed the halo is smooth and the glitter streaks come only from the path.

**Default-look change:** yes, by design. 192 px idle T2: meanL/stdL/meanA 0.489/0.215/0.897 → 0.536/0.163/0.896; held T2 0.485/0.224/0.894 → 0.565/0.165/0.897 (sun reflection + haze add light; the aliasing speckle contributed most of HEAD's stdL). 576 idle+audio: 0.492/0.215 → 0.545/0.165. Floor reflection (Cauchy), sky and sun are unchanged.
**Cost:** frameMs HEAD→new 8→11, 11→14 (nine analytic grid evaluations per floor pixel; cheap).
**Open items:** (a) fog law `mix(fog, floor, 1−fogDensity·0.85)` is transmittance-shaped, i.e. foggy near the camera and clear at the horizon — looks inverted vs real fog, but it is the HEAD identity (magenta foreground) so I did not change it; maintainers may want it flipped. (b) A f16: phase stored as `fract` (resolution 2⁻¹¹ ≈ 0.0005 vs per-frame step ≥ 0.0033), not verified on rgba16float (minirender is f32). (c) State texels (0,0)/(1,0) are the top-left corner pixels; their phosphor read is zero for neighbours that sample them via the ripple offset — invisible.

---------------------------------------------------------------------

## audio-voronoi-gabor  (`public/shaders/audio-voronoi-gabor.wgsl`, 277 lines; JSON advanced-hybrid)

**Kept verbatim:** 4 params + roles (cell_count; audio_reactivity = gain on wander/colour/alpha; displacement; gabor_influence); Gabor bank (freq 0.15, σ 2.5, radius 4, four orientations) and HEAD's `dominantAngle`/`textureStrength` definitions; Voronoi F1/F2 over 3×3 with audio wander + Gabor seed rotation; displacement law (hash angle + orientation·influence); cursor gravity/click pulse; Gabor colour map; per-cell frequency colours; depth modulation; alpha model. HEAD's displacement uses *raw* bass (not ×audioReact) — kept.
**A packing:** display RGBA (ACES) + semantic alpha; HEAD never wrote A, now writes it; C not read.

**Rescues** (R-numbers as in BRIEFS; numbering of the last one is R6)
- R1 audio: `plasmaBuffer[0].xyz` replaces `extraBuffer[idx*4]` + always-on `sin(8t)` beat. At silence there is no strobing and no white cells.
- R2 idle life: slow breathing floor only for cell wander (`IDLE_WANDER = (0.5, 0.4, 0)`) and per-cell displacement (`IDLE_DISP·breath`, breath phase = cell hash); never in colour/sparkle terms; real audio wins via `max`. At silence you get a breathing faceted mosaic with lit walls and Gabor tint.
- R3 bounded Gabor strength (HEAD unnormalised): seed shift ≤ 0.35 cell (`SEED_SHIFT_CAP`), colour-mix factor clamped to [0,1] (HEAD extrapolated past 1), displacement multiplier uses a capped seed strength (`STRENGTH_CAP` 3). Measured on the synthetic photo: textureStrength p50 2.08 / p90 3.57 / p99 4.12 (gabor_influence 1), 19 % of pixels > 3 ⇒ **the shift cap binds on most pixels of this image** (HEAD's `0.3·gStr` ≈ 0.6 cell at the median); the per-pixel shift still warps the diagram lookup (a HEAD design property) but can no longer leave the 3×3 window.
- R4 display: `aces(max(color,0))` (HEAD only clamped to 0..2); A written.
- R5 perf: shared tap grid, one 9×9 luma load + tables (`GaborTables`: cx[9], cd[17], ge[5]); the Gaussian is rotation-invariant and separable. **Verified against HEAD's `gaborResponse` ×4 with a scratch comparison shader: max |Σ response difference| ≈ 5·10⁻⁶ on responses of magnitude ≈ 3.6** (float rounding; HEAD used 0.785398 not π/4).
- R6 stable per-cell hash: HEAD's `cellHash = hash12(cellId.x, seedHashVal.x)` hashed the pixel-shifted, time-wandering seed ⇒ per-cell tints flickered per pixel and per frame; now `hash12(cellId)`. Treble sparkle: HEAD hashed `cellId.x + 0.1·t` only (whole columns of cells flashed together); now per cell, stepped 6 Hz clock.

**Ideas in the diff**
1. Grain-lit cell membranes (line 238): ridge `1 − smoothstep(0, 0.18, F2−F1)`, slope along `normalize((p2−p1)·res)` (aspect-correct), `lit = dot(slopeDir, grain(seedAngle))`; colour × `(1 + 0.45·lit·slope·gate)` plus a crest glint where the wall runs parallel to the grain (`1−|lit|`); gate follows the seed's Gabor strength (0.25 floor). Embosses each wall: one face brightens, the other darkens, with the light direction taken from the photo's own texture orientation.
2. Rigid cell translation (line 200): displacement direction uses a second bank evaluation at the cell's unshifted seed (`Vor.anchor`, stable per cell) instead of the per-pixel `dominantAngle`, so each cell slides as one plate and tears only at its wall.

**Default-look change:** yes (rescue + ideas). 192 px, audio 0, idle cursor: HEAD at two times 0.425/0.279/0.875 and 0.354/0.180/0.924 (strobing) → new 0.379/0.138/0.821 and 0.378/0.138/0.821 (stable). Held cursor + audio: HEAD 0.425/0.263/0.875 → 0.455/0.138/0.949; audio only (0.5,0.4,0.3) → 0.465/0.167/0.971. 576 px: 0.429/0.282 → 0.380/0.137. No NaN. 576 crop shows crisp walls with no pixel mosaic (no per-block hash noise).
**Cost:** interleaved 192 px, 2 rounds: HEAD 86/87 ms, new 86/98 ms (load avg 11) ⇒ ≈1.0–1.1× HEAD on SwiftShader (ALU-bound); texture loads per pixel drop from 324 to 162 even with the second bank, which should help on a real GPU. Within the 1.25× bound.
**Open items:** per-pixel seed shift still warps the diagram (HEAD design; the cap bounds it, a per-seed orientation would need 9 banks); the cap binds often on textured photos — consider `STRENGTH_CAP`/`SEED_SHIFT_CAP` tuning on real photos on a GPU; silence look is quieter than HEAD's strobe by design (documented); `audio-driven` and `randomization-safe` JSON features kept as they were.

---------------------------------------------------------------------

## JSON (params byte-exact in all three)
- data-stream-spectral: features += audio-reactive, click-reactive, upgraded-rgba; description replaced ("Catalog entry…" placeholder).
- vaporwave-horizon-prismatic: features += upgraded-rgba; description + `feedbackPacking` updated (state texels).
- audio-voronoi-gabor: features += upgraded-rgba; `x-meta.chunks_used` entry "Audio band simulation" corrected.
No idea-named tags added.

## Not done / not mine
- No git operations, no list regeneration, no ledger, no build/Vitest (coordinator).
- Fork C's edit in `shader_definitions/advanced-hybrid/cyber-ripples-coupled.json` appeared in `git diff --stat` (not touched by me).
