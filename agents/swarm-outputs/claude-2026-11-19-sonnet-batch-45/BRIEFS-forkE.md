# BRIEFS fork E — snow, luminance-wind (both second pass)

Written BEFORE any WGSL edit. HEAD = origin/main 8c537fe6 (coordinator's prelude migration is header-only).

## HEAD measurements (SwiftShader mini-renderer, `agents/mr.mjs`, synthetic image + depth)

**snow**
- Fall direction: flat source, density 1, frames at t=1.00 / 1.01, cross-correlated → best shift dy = **−4 rows** (rows down = +), dx = 0 → **flakes RISE**. Cause: `uv.y*… + time*layer_speed` (pattern coordinate grows with time ⇒ features move to smaller uv.y = up on screen).
- Wind direction: `skewed.x = … + wind_drift` with `wind_drift = +time·speed·wind` ⇒ positive wind moves flakes toward −x; the same `wind` is fed by `(mouse.x−0.5)*1.4` (pointer right ⇒ "wind +") so pointer-right pushes flakes left.
- Accumulation slider: acc 0.0 vs 1.0, 40 frames, density 0, smooth depth → max |diff| = **0.0** (dead). Cause: the settle test reads `smoothstep(0.3,0.7, normal.y)` where `normal` is built from per-texel depth differences (O(0.003)) → `normal.y` ≈ 0 on any real depth map; and the sign is wrong — library depth is 1 = near, so a floor (near at the bottom, y-down) has `normal.y < 0`; HEAD selects down-facing surfaces.

**luminance-wind**
- Flat source 0.3, 120 frames, defaults (0.5,0.8,0.1,0.2): output mean 0.838 vs ACES(0.3)=0.438 → steady-state **1.91×** (washed-out defaults, see lw_head.png). Cause: `injection = clamp(0.07+lumaGate*0.15+…, 0.05, 0.34)` is independent of `trailDecay`; steady-state gain = injection/(1−decay) = 0.07/0.056 … 0.22/0.056 = **1.25–3.9×** at the default decay; 14× at decay→0.985.
- Other checks clean: audio via plasmaBuffer[0].xyz, exact C loads, depth read, ripples via `config.y` count, A packing consistent (raw HDR in A, ACES on writeTexture only).

## Rescues (listed up-front so the cards can stay about ideas)
- snow R1: flakes fall (flip `+ time*layer_speed` → `−`). R2: wind sign flipped so pointer-right / slider>0.5 blows flakes toward +x (same magnitude). R3: Accumulation slider live — depth slope per uv unit with a fixed relief gain and the sign corrected to up-facing; HEAD `normal` (lighting) value unchanged.
- luminance-wind R1: injection scaled by the trail's own leak `(1−trailDecay)` so a static scene settles at ~1.0–1.6× instead of 1.25–3.9×; floor 0.03 keeps high-decay responsive.

---

## SHADER: snow
IDENTITY: depth-aware blizzard — three parallax layers of tumbling hexagonal flakes over the photo, wind-skewed, with a snow bank in C that melts and that landing flakes fade into.
KEEP VERBATIM: `snow_layer` / `snowflake` / `hexagon_dist`; Idea-1 tumble; Idea-2 land fade (`snow_acc *= 1 − prev_snow·0.85`); 4 param roles (speed, density, wind, accumulation); `melt_rate`; mouse.x → wind; A packing (A.r = bank raw, A.g = flake coverage); ACES on display only; lighting uses the same `normal`/`light_dir`; audio (bass → speed, treble → density + sparkle).
MECHANISM INTERROGATION:
- tactic 3 (promote an intermediate): `depth` is sampled once per pixel and only used for the bank — but the title is "Depth-Aware" and the flakes ignore it. The layer index is already a per-layer parallax plane (speed, cell size, fade).
- tactic 6 (history it already owns): C.r is read as a scalar bank; the one extra thing a bank affords is *moving*: wind carries it. No packing change.
- tactic 2 (physics one step further): blowing snow = saltation — wind lifts settled snow off exposed lips and drops it downwind.
ADD (2 native ideas):
1. **Depth-occluded flake layers** — each layer gets a virtual depth plane (far 0.40, mid 0.65, near 0.90 in the library's 1 = near convention); scene pixels clearly nearer than a plane hide that layer's flakes (smoothstep(plane+0.04, plane+0.22), max 85 % hidden). Far flakes fall behind the subject, near flakes in front. Flat / absent depth → identical to HEAD.
2. **Wind-carried bank (saltation)** — the settled bank blends with its upwind neighbour (one exact `textureLoad` of C.r, 1 px along sign(wind)) at a rate ∝ |wind| (≤ 12 %/frame). Snow slides off lips downwind in plumes instead of sitting frozen; at wind = 0 (default sliders, pointer centred) it is exactly HEAD.
FORMULA ADMISSION: not from the §12.2 tables (snow is a particle overlay + a bank field). (1) family match by tactic 3 / the file's own "Depth-Aware" identity; consumes `depth` the file already samples; deletion test: remove it → still HEAD blizzard; keep only it → not a blizzard (no flakes). (2) = first-order upwind advection of an existing field (row D "MacCormack advection" family, but the simple upwind form: same samples, one load); consumes C.r the file already loads.
FORBID on this file: spring, click ripples, IQ palette, any new param, a new flake motif, extraBuffer state, `dataTextureB`.
A PACKING: unchanged — A.r = raw bank, A.g = flake coverage; display ACES.

## SHADER: luminance-wind
IDENTITY: luminance-gated raw-HDR history advected downwind by layered curl gusts (held joystick direction, click fronts, depth parallax, chromatic drift); bright regions streak, dark regions stay.
KEEP VERBATIM: curl noise stack, 4 param roles (wind speed, trail decay, luma threshold, turbulence), lumaGate, depthLayer speed parallax, held-pointer jet / click gust fronts, chroma split taps, raw HDR in A / ACES on writeTexture, semantic alpha; Idea 1 lee-side shelter; Idea 2 cat's-paw gust bands.
MECHANISM INTERROGATION:
- tactic 3: `shelter` (0..1, wake mask from the two upwind depth taps) is computed and only used to slow speed — its *boundary* (shelter·(1−shelter)) is the shear layer of the wake and is never used.
- tactic 7 (direction, not just magnitude): `depthLayer` scales wind *speed* by depth; the wind *direction* is depth-independent. Real wind veers with height (Ekman spiral).
- tactic 2: air leaving a wake edge rolls up into eddies (shear-layer instability).
ADD (2 native ideas):
3. **Wake-edge eddies** — rotate the advection direction by `shear·sin(phase)·amp`, where `shear = 4·shelter·(1−shelter)` is 0 in free stream and deep shelter and 1 on the wake boundary; phase runs along-wind (`dot(uv·aspect, wind)·34 − 3t`) with an across-wind skew. Amp rides the existing Turbulence slider (`0.35 + 0.9·turbulence`, second-order param). The lee pockets of Idea 1 now have curling edges instead of hard cut-outs. Zero extra taps.
4. **Depth-veered wind** — wind direction rotates by `(depth − 0.5)·0.55 rad` (± 16°), applied before the shelter look-ups so shelter follows the veered air. Near and far layers now shear past each other in direction as well as speed. Zero extra taps.
FORMULA ADMISSION: both consume quantities already computed (`shelter`, `depth`, `wind`); no new state/binding/spring; same-noun test: "wake", "shear layer", "veer" are wind vocabulary; deletion test: delete either → still exactly luminance-wind; delete the original advection and keep only the idea → nothing moves, so not a reimagining.
FORBID on this file: new IQ palette, springs, a second curl stack, extra history taps, new params, extraBuffer state.
A PACKING: unchanged — A/C = raw HDR RGB + semantic alpha, ACES on writeTexture only.

## Batch-level note (fork E)
Two files, four distinct ideas, no shared formula; rescues are listed per shader and kept apart from ideas.

---

## Amendments after measuring (cards above were written first; these are what the diff actually does)
- **Numbering:** in the WGSL the existing ideas are 1–2, so snow's cards 1/2 are `// ── Idea 3` (depth-occluded flake layers) and `// ── Idea 4` (wind-carried bank); luminance-wind's 3/4 are unchanged (`Idea 3` wake-edge eddies, `Idea 4` depth-veered wind).
- **luminance-wind Idea 3 was reworked.** First form (rotate the advection direction by `shear·sin`) measured **0.00 % px** different from eddy-off on both synthetic scenes: the rotation acts on `localSpeed`, which the shelter has already damped ×0.15, and a hard depth edge gives a zero-width `4·s·(1−s)` band. Final form: (a) `shear = max(4·s·(1−s), shelter·(1−shelterNear))` — the second term is the wake's trailing fringe from the two upwind taps HEAD already fetches (far tap sheltered, near tap not), so it exists on hard silhouettes too; (b) the swing is an across-wind displacement of the history lookup, `shear·sin(phase)·(0.35+0.9·turbulence)·windSpeed·lumaGate·depthLayer·0.9`, i.e. on the free-stream speed. Still zero new taps. Measured now: 0.6 % px >12/255 (7 % >4/255) on the hard-box scene, 3.8 % >12/255 on the soft scene — localised to wakes by design.
- **luminance-wind rescue gain** trimmed from +55 % to +35 % bright-gate gain after the first read (1.35× → 1.25× ACES(src) at defaults).
- Idea 4 (veer) measured: 16 % px >12/255 (box), 14 % (soft).
