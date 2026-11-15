# NOTES — fork B (viscous-drag, luma-velocity-melt) — batch-39, 2026-11-15

Worktree `/root/iv-sonnet-batch-39`. No git write operations. Edited only: `public/shaders/viscous-drag.wgsl`, `public/shaders/luma-velocity-melt.wgsl`,
`shader_definitions/liquid-effects/viscous-drag.json`, `shader_definitions/liquid-effects/luma-velocity-melt.json`.
Evidence: SwiftShader WebGPU through a scratch COPY of `agents/mr.mjs` (adds ripple injection and min-of-drained-frame timing), synthetic `SRC=img` photo,
saved-default sliders passed explicitly (viscous-drag 0.6,0.5,0.95,0.5; luma-velocity-melt 0.005,2,0.95,0.5 RAW), 60 frames over 4 s (melt: 90 frames over 5 s at 192,
60 frames at 576), scenarios `idle` (cursor up at 0.5,0.5), `held` (cursor down, path (0.3,0.4)→(0.7,0.6)), `click` (two injected ripples, ages 0–2 s), `audio`
(held path + bass/mid/treb 0.8/0.5/0.9). `pct` = % of pixels with max-channel |Δ| > 0.02 between the new file and the **same file with that idea's constant zeroed**
(`MENISCUS_GAIN=MENISCUS_SHADE=0`, `SMEAR_LEN=0`, `MARANGONI_GAIN=0`, `MEANDER_AMP=MEANDER_FOLLOW=0`). **No real-GPU claim of any kind.**
The scenarios drive a synthetic image (smooth blobs + a 40/33-cycle texture), so edge-driven ideas (smear, Marangoni) will read stronger on a real photo.

---------------------------------------------------------------------------------------------------------------------------------

## 1. viscous-drag

**KEEP VERBATIM held.** The whole state update (integer-pixel jet advect via `baseCoord`, 4-neighbour mix by viscosity, shear-thinning, bass jet surge, mouse / vortex /
click forces, recovery, thickness, dragEnergy), the raw A packing (RG offset, thickness, drag energy — no ACES on A), the 4 saved params and their roles, ACES on
`writeTexture` only, the alpha formula and the depth pass-through are byte-identical to HEAD. Only the display tail changed. **A packing: raw, unchanged.**
JSON `params` byte-exact (checked programmatically); `x-meta.upgrade.params` was already aligned; description +70 chars.

### HEAD finding behind Idea 1 (confirmed by probe)
HEAD's specular used `normal = normalize(vec3(newOffset, 0.02))` — a nearly horizontal normal — against `L = normalize(0.5, 0.5, 1)`. `dot(n, L)` is at most 0.577 once
|offset| > 0.02, so `pow(dot, 20) ≤ 1.7e-5`; where |offset| is tiny the normal tilts up and it only reaches `0.816^20 = 0.017`. A spec-only probe of HEAD
(held + audio, 256 px, specular ×50 before ACES) gave a p99 of ≈ 0.018. So the card's "illuminated viscous ridges" were effectively unlit at HEAD.

### Idea 1 — thickness-gradient meniscus lighting (native; tactic 3, promote an intermediate)
`viscous-drag.wgsl` L114–131 (constants L14–17). The normal now comes from ∇thickness (`rightState.z−leftState.z`, `downState.z−upState.z`, scaled by `0.5·res.y` so it is
resolution independent), `normal = normalize(vec3(−∇t·0.05, 1))`. HEAD's light direction and exponent (20) are kept. A thickness-weighted (`wet`) Blinn-style highlight
plus a matching diffuse relief on the photo (`color · (1 + 0.45·(n·L − 0.8165)·wet)`; zero on a flat film). Neighbours are the ones already loaded for the advection →
no new loads. The gradient is the previous frame's thickness at the advected position (one frame of lag; thickness changes slowly because of `recovery`).
Visibility, % of pixels with max-channel |Δ| > 0.02 (new vs idea-1-off):

| size | idle | held | click | audio |
|---|---|---|---|---|
| 192 | 6.1 | 12.0 | 12.2 | 18.3 |
| 576 | 5.8 | 5.1 | 9.2 | 10.6 |

(whole frame; the pointer disc / trail / click rings are 10–25 % of it. At 576 the trail is the same uv size but the pointer path covers a smaller share of the frame in the
synthetic scene — the idle number is the pointer-disc pressure bump plus the vortex packets.) Looked at the PNGs: the held trail now reads as a thick liquid ridge with a
bright meniscus rim and a shaded flank; HEAD showed a flat blue-grey veil.

### Idea 2 — strain-directed smear (native; tactic 7, direction not just magnitude)
`viscous-drag.wgsl` L96–112 (constant L17). One extra 4-tap comet tail upstream of the HEAD tap along `normalize(newOffset)`, length `min(dragEnergy,1.2)·0.05 uv`, weight
`smoothstep(0.03, 0.55, dragEnergy)·0.85`. `dragEnergy ≈ 0` returns the HEAD tap exactly (the loop is skipped by `smearAmount > 0.004`). First version (0.02 uv) measured
only 1–2 %; strengthened to 0.05 uv. Visibility (new vs idea-2-off):

| size | idle | held | click | audio |
|---|---|---|---|---|
| 192 | 0.0 | 5.9 | 2.6 | 4.5 |
| 576 | 0.0 | 4.5 | 2.2 | 3.6 |

It is **flow-local by design**: dragEnergy is ≈ 0.05–0.12 at idle (HEAD probe, 192 px), so idle shows nothing; under a held pointer 17 % of pixels have dragEnergy > 0.3.

### R1 (integer-pixel advection) — see "Open items" for the result.

## 2. luma-velocity-melt

**KEEP VERBATIM held.** `hot` threshold ramp, `flow` construction, exact C history advect `uv − flow`, chroma R/B split, `historyWeight` / `pileHold`, drip pinch-off (Idea 1),
depth-ledge pooling (Idea 2), HDR RGB + semantic alpha packing (B unwritten), 4 saved params with RAW ranges, mouse stir, click rings, ACES on `writeTexture` only.
**A packing: untonemapped HDR RGB + semantic alpha, unchanged.** JSON `params` byte-exact; `x-meta.upgrade.params` added (additive); description +56 chars.
Numbering: the file already used "Idea 1/2" for the 2026-09-21 pass, so the 2026-11-15 ideas are **Idea 3 (Marangoni)** and **Idea 4 (meander)** in the WGSL.

### Idea 3 — Marangoni thermocapillary spread (native; tactic 3)
`luma-velocity-melt.wgsl` L91–106, `hotRamp` L27–30, constants L22–25. Four taps of the same luma ramp (`smoothstep(threshold ± 0.12)`) at ±0.02 uv (same pixel distance on both axes) give ∇hot; the flow gets
`−∇hot · (1, 0.4) · meltSpeed · 0.9 · (1 + heat·0.1)` — material moves from hot toward cold, so the bright region spreads sideways at its rim (the y component is damped to
0.4 so the melt does not climb). `meltSpeed = 0` still means no motion. Visibility (new vs idea-3-off), 192 px, 90 frames: idle 5.9 %, held 7.2 %, click 6.0 %, audio 8.4 %;
576 px, 60 frames: idle 5.7 %, audio 8.4 %. (The first version used a ±4 px stencil: 6–9 % at 192 but only 1.5–2.2 % at 576 because the same luma ramp spans more pixels; the stencil is now in uv.) At a faster melt (0.015) the bright blobs visibly broaden with a soft lip instead of a hard edge (crop reviewed).

### Idea 4 — rivulet meander (native; tactic 5, artifact of the real process)
`luma-velocity-melt.wgsl` L57–76 (column centre line) and L106–108 (stream follows it). The column coordinate is `uv.x − sway(y, x-group)`, where `sway` is two slow sines
(50 and 118 rad/uv) whose phase is a smooth noise of `uv.x/(5 columns)` — neighbouring columns wander together, no seam. The stream then follows its own centre line:
`flow.x += slope · flow.y · pinch`. Amplitude `0.016 uv · min(0.6 + 60·meltSpeed, 1.5)` (resolution independent; slope ≤ ≈ 1). First amplitude (0.009) measured 1–2.5 %; raised
to 0.016. Visibility (new vs idea-4-off), 192 px: idle 3.3 %, held 3.8 %, click 3.3 %, audio 6.3 %; 576 px: idle 4.6 %, audio 8.7 %. The 3× crops at melt 0.015 show wavy rivulet runs where HEAD
shows ruler-straight streaks with hard step seams.

Context: HEAD's own melt changes 33 % of the frame (>0.02) versus melt = 0 at the saved defaults, so these four-to-eight-percent numbers are a sizeable share of what the effect does.

## §12.2 rows
Neither file uses a §12.2 row (all four ideas are native); Row budget untouched. No spring, ripple, IQ palette or Cauchy fringe was added.

## Default-look change (meanL / stdL, 256 px unless stated, HEAD → new)
Default look is a quiet change by design (no slider changes the saved-default magnitude of anything; Melt Speed = 0 still means no motion).

| scenario (192 px) | viscous-drag meanL / stdL HEAD → new | luma-velocity-melt meanL / stdL HEAD → new |
|---|---|---|
| idle | 0.509 / 0.174 → 0.510 / 0.175 | 0.513 / 0.182 → 0.515 / 0.183 |
| held | 0.520 / 0.167 → 0.522 / 0.167 | 0.515 / 0.182 → 0.517 / 0.183 |
| click | 0.517 / 0.168 → 0.515 / 0.171 | 0.514 / 0.182 → 0.515 / 0.183 |
| audio | 0.528 / 0.173 → 0.539 / 0.175 | 0.517 / 0.184 → 0.519 / 0.186 |

`new vs HEAD` pixel difference (>0.02): viscous-drag 5.5 % idle / 15.5 % held / 13.2 % click / 19.6 % audio (192), 5.9 / 9.7 / 11.1 / 12.9 % (576); luma-velocity-melt 7.9 / 9.4 / 8.1 / 12.1 % (192), 9.2 % idle / 14.3 % audio (576). `nan` = 0 in every render (192 and 576). `A16=1` (real rgba16float state) runs of both files match their rgba32float runs (max |Δ| 0.009 viscous-drag, 0.001 melt).
Per-slider sweep (min→max, 192 px, held cursor + one ripple + audio 0.6/0.4/0.5, % of pixels > 0.02): viscous-drag 37.7 / 72.3 / 53.3 / 13.5; luma-velocity-melt 88.4 / 52.0 / 19.0 / 100 — all eight sliders change the picture.

## Cost (min-of-drained-frames, interleaved, 6 rounds, median of per-round ratios, 256 px; machine load average 30–45 from sibling forks — read ±0.2)
| file / scenario | per-round ratios | median | note |
|---|---|---|---|
| viscous-drag, held + audio (smear + meniscus active) | 1.89, 1.15, 1.24, 1.28, 2.27, 0.59 | **1.26** | load average 43–65 |
| viscous-drag, idle (meniscus only; smear skipped) | 1.01, 1.20, 2.02, 1.35, 0.98, 0.54 | **1.10** | |
| luma-velocity-melt, audio (4 extra luma taps always on) | 1.08, 1.21, 1.58, 0.52, 0.68, 1.24 | **1.15** (min-of-mins 1.07) | |

The spread per round is ±50 % because the host load average was 30–65 (sibling forks); the medians are below the 1.3× cap but **not trustworthy to better than ±0.2 — the coordinator re-times alone.** Expected cost drivers: viscous-drag = 4 `textureSampleLevel` when the smear branch runs; luma-velocity-melt = 4 `textureSampleLevel` per pixel (all lanes). If the coordinator's idle re-time shows melt > 1.3×, the cheap trim is two forward taps (x+d, y+d) against the pixel's own `hot` ramp (one-sided gradient, no new state) — `hotRamp` is already isolated in one function.

## Hygiene fix (not an idea)
`luma-velocity-melt.wgsl` click ring: `exp(-pow((dist − age·0.2)·42, 2.0))` took `pow` of a NEGATIVE base inside the front (undefined in WGSL, NaN on some GPUs) → replaced with `ringArg·ringArg`. Identical output on SwiftShader (Δ = 0.0000 with two live ripples, 192 px); the benefit is for other drivers and is not verifiable here.

## Gates
- `python3 scripts/wgsl_precommit_gate.py --files …` both pass; `node scripts/verify-naga-wasm.mjs --files …` both valid (0 known, 0 new).
- `npm run audit:dead-sliders -- --files viscous-drag luma-velocity-melt` — 0 new. `npm run audit:extrabuffer` — 0 new (neither file touches `extraBuffer`).
- No `pow` with a possibly negative base (the one new `pow` is `pow(max(facing, 0), 20)`); no `fwidth`; all `normalize`/divisions guarded (`flowDir` uses `max(length, 1e-5)`).

## Open items / honest limits
1. **R1 (sub-pixel advection on viscous-drag) — measured, real, not shipped.** The quantisation is real: at the saved defaults `round(jetDirection · 2.32)` takes 16 distinct integer vectors, with a heading error up to 14° (mean 6°) and a speed error of 0.86–1.22× (analytic, 0–120 s sweep). But a scratch variant with bilinear fetches (20 `textureLoad`s instead of 5) differs from the shipped file by only 0.24 % of pixels at idle (5.1 % under a held cursor + audio, where it mostly adds numerical diffusion — a softer trail, i.e. a different look, not a clean fix). The card said "only if real *and visible*"; it is real but not visible at idle and costs 4× the history loads, so it was left out. If a reviewer wants it, the variant is `…/scratchpad/forkB/vd/r1.wgsl`.
2. **Smear is flow-local.** At idle (`dragEnergy` ≈ 0.05–0.12) it is 0.0 %; it only shows under a held pointer / click / audio surge (2–6 % of the frame). On a synthetic photo with smooth gradients; a photo with sharp edges will show more.
3. **Meniscus lighting uses the previous frame's thickness gradient** (one frame of lag, taken from the neighbours the advection already loads). The held trail therefore shows thin contour arcs where successive pointer positions stacked thickness (visible in `vd/new_audio_576.png`); they read as layered ridges, but they are a stamping artefact of the pointer trail, not a designed feature.
4. **Melt ideas are strongest at higher Melt Speed.** At the saved default (0.005) the whole melt is subtle (HEAD itself changes 33 % of the frame vs Melt Speed = 0, only 6 % above 0.05). At 0.015 the 3× crops show broadened lips (Marangoni) and wavy runs (meander) against HEAD's ruler-straight streaks with hard step seams.
5. **Meander is a function of x-group phase**, so groups of ≈ 5 columns sway together; if a reviewer sees a visible vertical seam between groups of columns on a real photo, lower `MEANDER_AMP` or widen the group (`dripW · 5.0`).
6. Not verified: any real-GPU look; `viscous-drag.json` still lists `fast-motion` (HEAD's; not touched); `luma-velocity-melt.json` features unchanged (no new pointer / audio claim).
