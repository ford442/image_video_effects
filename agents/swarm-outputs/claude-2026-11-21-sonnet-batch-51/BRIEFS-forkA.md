# BRIEFS — fork A (rain, prismatic-3d-compositor; both 1st pass) — written BEFORE any WGSL edit

HEAD = worktree file after the coordinator's prelude migration (copies at scratchpad `a/<id>_head.wgsl`).
Both files compile and run (nan 0). Neither has any idea text; `rain` has only the swarm banner, the compositor only a Batch-22 hygiene note.

Correction to COMMON.md Finding 3: `prismatic-3d-compositor`'s Pass 1 **does** exist — `volumetric-rainbow-clouds.wgsl` (its header says `Next Pass: prismatic-3d-compositor.wgsl`) and it already applies ACES to its output. So the compositor's input is display-referred; a second global ACES would double-tone-map (0.5 → 0.62 mid-grey lift). I use an identity-below-knee highlight roll-off instead (decision on the card, flagged as an open call).

---

# 1. rain

## What HEAD does (read in full, rendered, measured)

Grid-cell rain: `rainUV = (uv.x·D·aspect + wind·t·3, uv.y·D + t·fall)`, one potential streak per cell (`step(0.65, hash(cell))`), centred at `local.x = 0.5`, slanted by `wind·local.y·0.3`; width `0.005 + dropSeed·0.012`; tail taper `smoothstep(1.0, 0.15, local.y)`; splash arcs at `local.y > 0.92`. One refracted tap of the photo (`displacedUV`), one light tap (`uv + 0.002`) → `bloom = pow(L,3)·2.5·dropletAlpha`, rain tint, a hash-cell mist layer, ACES, semantic alpha, depth out, A = `(dropletAlpha, motionBlurStrength, mistLayer, finalAlpha)` diagnostics that nothing reads (C is never read).

HEAD defects measured at 384², SRC=img, saved defaults (0.45, 0.45, 0.5, 0.45):
- **R1 — the rain falls UP.** `rainUV.y = uv.y·D + t·fall` makes a cell's screen position `uv.y = (c − t·fall)/D`, i.e. decreasing → toward the top of the picture (y = 0 is the top). Measured: alpha pattern cross-correlation between t = 1.0 and 1.1 s is a **−2 row roll (UP)**, expected 2.2 rows (0.1·2.06/35.7·384). The tail profile (bright at `local.y < 0.15`, fading downward) is the "head leads at the top" shape of a rising streak, while the splash arcs sit at `local.y > 0.92` (the bottom of the cell) — the author's intent was falling rain with the splash where the head lands.
- **R2 — the droplet lens offset grows with time.** `dropCenter.y = cell.y / D` omits the `t·fall/D` scroll that `dropCenter.x` has for wind, so `dropWorld.y` grows linearly with time and so does the refraction `dropWorld·(lensR−lensG, lensB−lensR)·40`. Measured mean |HEAD − HEAD-without-lens| = 5e-5 at t = 1 s, **2.4e-3 at t = 300 s (48× growth)**; at that point every streak pixel samples the clamped frame border.
- **R3 — the rain is a perfect comb.** Every streak is centred at `local.x = 0.5`, so drops sit on equally spaced vertical lines (visible in the HEAD render as evenly spaced dashed columns).
- **R4 — dead / flickering terms.** `streakY` (the "gravity" curve) is computed and never used; `dropSeed2 = hash13(cell, t·0.1)` re-rolls every frame, so the G-lens ratio is white noise; the mist re-rolls every 0.5 s (`floor(time·2)`) as hard cell flips (frame-hash strobing), and it scrolls UP like the rain.
- Not a defect, noted: `readDepthTexture` is read (the `depth-aware` tag is true); A is diagnostic-only (nobody reads C).

## Idea Card

```
SHADER: rain
IDENTITY: the photo seen through falling rain — thin gravity streaks (head + motion-blurred tail),
  a small water lens in each streak, light bloom through the drops, a faint mist layer, splash arcs
  where heads land.
KEEP VERBATIM: the 4 sliders and roles (x rain_density → grid density 6..72; y fall_speed 0.3..4.2;
  z wind −0.12..0.12 plus mouse.x·0.08; w wetness 0.06..0.55 → mist strength); the grid-cell streak
  kernel (rainUV/cell/local, `step(0.65, dropSeed)` presence, `step(0.75, …)` splash gate, streak
  width family, slant `wind·local.y·0.3`); splash arcs at local.y > 0.92; bloom (pow(L,3)·2.5 from
  the uv+0.002 light tap); rain tint + per-channel chroma mix; the mist blend formula
  `hdr·0.72 + tint·0.28` weighted by `mistLayer`; the 0.9+bass·0.15 exposure; ACES; the alpha
  structure and 0.04..0.96 clamp; depth out; A diagnostic packing.
ADD (3 native ideas):
  1. Per-lane terminal velocity + shutter-length streaks (§12.1 tactics 2/3 — promotes the dead
     `gravity`/`streakY`). Each drop column ("lane") draws a size seed; bigger drops fall faster
     (0.7×..1.3× of the fall slider), are slightly wider and leave a longer tail (tail length
     0.45..1.0 of the cell = speed × exposure), with brightness renormalised so a long fast streak
     is not simply brighter (constant exposure). Heads now lead at the bottom, tails trail above.
     Also jitters each streak's x inside its cell (breaks the comb, R3).
     Why here: rain drops have terminal velocities set by their size and a streak is
     velocity × shutter time — the file already has gravity/width/taper pieces that never agree.
  2. Snell refraction through the water streak (§12.2F Snell vector refraction). Each streak is a
     water cylinder whose cross-section normal comes from the streak's own x-profile; the view ray
     is refracted with `refract()` (η = 1/1.333) and the photo is sampled at the lateral exit
     offset → the thin inverted-image sliver a real streak shows. Replaces the fake
     `dropWorld·(lensR−lensG…)·40` lens (R2). `depthScale` still scales near drops stronger.
     Why here: HEAD claims "chromatic droplet lensing" but only offsets one sample by a quantity
     that grows with time; a water streak IS a lens.
  3. Beer–Lambert mist on real scene depth (§12.2F). `mistLayer = 1 − exp(−τ)` with τ ∝ smooth
     advected noise × wetness × path, path growing with distance (1 − depth) — far scenery washes
     into rain haze (aerial perspective) instead of HEAD's "nearer = more mist" and its hard
     0.5 s cell flips; the haze drifts with the rain and wind. Same blend formula, same slider.
     Why here: atmospheric rain is visibility loss with distance; `wetness` keeps its role.
RESCUES (reported separately, not counted as ideas): R1 rain direction (falls down), R2 lens offset
  growth (subsumed by idea 2), R3 comb lattice (jitter), R4 dead `streakY` / per-frame `dropSeed2` /
  hash-cell mist strobe + upward mist drift.
FORBID on this file: springs / extraBuffer state, click shockwaves, IQ palette, new params,
  Cauchy dispersion (claimed by the compositor), HG, history feedback, changing saved defaults.
A PACKING: unchanged — diagnostic `(dropletAlpha, motionBlurStrength, mistLayer, finalAlpha)`;
  nothing reads C. Display RGBA on writeTexture only (ACES there, unchanged).
```

## §12.1 mechanism interrogation

- **Tactic 1 — deepen the kernel.** The streak kernel approximates ∫ of a falling drop's image over the shutter: a tapered 1-D line. Next-better approximation of the *same* operator: line length = v·exposure with v from drop size, brightness conserved, head at the leading end.
- **Tactic 2 — physics one step further.** Rain's first-order optical consequences: a drop is a water lens (refraction by Snell's law, inverted image); distance → extinction (Koschmieder / Beer–Lambert); big drops fall faster (terminal velocity).
- **Tactic 3 — promote an intermediate.** `gravity`, `streakY`, `streakWidth`, `local.x` (the cross-streak coordinate) are computed and thrown away or used only for brightness; `depth` is read but only scales lens/alpha.
- **Tactic 6 — history.** C is never read in HEAD (A is write-only diagnostics). One piece of continuity that keeps that: none needed — all three ideas are per-pixel analytic; no history is introduced (rain streaks are stateless by construction).

## §12.4 formula admission

- Snell vector refraction: row in F (lighting/optical) — rain is an atmospheric/optical effect whose identity is water refraction (sentence: "a water streak is a lens"); consumes `streakX/streakWidth/local` already computed; deleting it leaves the rain, deleting rain keeps only a lens → additive.
- Beer–Lambert: row in F; consumes `depth` and `mistLayer`/`wetness` already there; deletion test OK (HEAD mist remains rain-mist).
- Terminal velocity / exposure length: not a table row — tactic 3/2 on the shader's own `gravity`, `streakWidth`, taper; operates on what exists, no new state.
- Row claims per COMMON: Snell, Beer–Lambert (rain only); HG, Cauchy, energy bloom, 9-pt Laplacian, etc. not used.

---

# 2. prismatic-3d-compositor

## What HEAD does (read in full, rendered)

Pass 2 of a chain (Pass 1 = `volumetric-rainbow-clouds`, display-referred, ACES'd). `readTexture` = cloud colour, `readDepthTexture.r` = cloud depth (depth 1 = near; the pass reads `exp(−depth)` as a far-weight and scales parallax / aberration with depth, so 0 = far / no map).
1. Parallax: a depth-weighted cursor offset `(mouse − 0.5)·parallax·depth·(1+bass·0.4)·(1+down·0.5)·0.05`, one tap at `uv + offset`, edge-masked; the result is a **ghost** mixed over the aberrated base by `depth·(0.4 + bass·0.5)`.
2. Glow: 5×5 taps at `glowRadius·0.01`, weight `exp(−depth_tap)·max(|c| − 0.2, 0)`, normalised by `max(Σw, 1)`, prism-tinted by depth hue (0.35 mix).
3. Aberration: R at `+abDir·δ`, G at 0, B at `−abDir·δ`, `δ = slider·depth·(1+mids·0.5)·(1 + flare·3) + flare·0.02`; `abDir` = radial from frame centre mixed with the click-flare direction.
4. Click flares from `u.ripples` (envelope `exp(−2·age)`, 1.2 s).
5. Composite `mix(cloud, lit, 0.5)`, `lit = layered + glow·I·(1+bass·0.6) + tint·flare·0.25`. **No tone/limiter on the output** — values can exceed 1 (HEAD A/display carry HDR).
6. "Temporal feedback": `feedback = mix(finalColor, prev, 0.85 − mids·0.25)` → A.

HEAD defects:
- **C1 — the temporal feedback is invisible.** `feedback` is written to A and read back as `prev`, but `writeTexture` gets `finalColor`, never `feedback`. The 0.85-retention trail (mids shorten it "so busy passages stay crisp") never reaches the picture. (Rescue: make it live where the author meant it — on the glow, see Idea 2.)
- **C2 — non-exact feedback load.** `textureSampleLevel(dataTextureC, non_filtering_sampler, uv)` at `uv = gid/dims` (texel *corner*, no +0.5) can round to the neighbouring texel. Replace with an exact `textureLoad`.
- **C3 — the glow double-exposes.** `lit = layered + glow·…` adds the glow (a weighted average of bright neighbours, including the pixel itself) on top of the full source, so bright cores gain light they just radiated (energy is invented, not moved).
- **C4 — parallax uses the depth of the wrong pixel.** The offset is scaled by the depth at the *destination* pixel and then fetches the colour at `uv + offset`, whose own depth (and so its own parallax) differs: at depth edges a near object's shift is applied to the far pixel next to it (smeared halo / doubled edge).
- **C5 — pre-existing over-claims.** JSON/`features` carry `upgraded-rgba` (no ACES in this file, none added — see the Pass-1 note), a stale comment claims `videoBlend`/threshold live in `extraBuffer[0..2]` (the code uses constants). Report only.
- Floor check: audio from `plasmaBuffer[0].xyz` ✓ (three bands live), all four sliders live ✓, depth passthrough ✓, no `extraBuffer` use ✓.

## Idea Card

```
SHADER: prismatic-3d-compositor
IDENTITY: the depth-aware prism composite of a rendered scene — a cursor-driven parallax ghost,
  a volumetric prism-tinted glow around bright parts, radial chromatic fringing scaled by depth,
  click prism flares, blended 50 % over the source.
KEEP VERBATIM: the 4 sliders and roles (x glowRadius·0.01 tap spacing; y glowIntensity; z
  parallaxAmount; w aberration max split) and defaults; PARALLAX_SCALE and the
  depth·(1+bass·0.4)·(1+down·0.5) driver; in-bounds fade; the 5×5 depth-weighted glow gather,
  threshold 0.2 and normalisation; prismTint (depth hue, 0.35 mix); abDir (radial mix 0.65 + flare
  direction); the flare envelope constants and the `+flare·0.02`/`·3` boosts; the ghost mix
  `depth·(0.4 + bass·0.5)`; `videoBlend = 0.5`; treble→glow, bass→glow, mids→aberration/trail; alpha
  `|c|·0.7 + depth·0.3`; depth passthrough.
ADD (3 native ideas):
  1. Cauchy dispersion on the aberration split (§12.2F Cauchy dispersion). The R/B shifts follow
     n(λ) = A + B/λ² at 650 / 450 nm referenced to the existing green tap: R +0.73·δ, B −1.27·δ
     (total R–B separation stays 2δ, so the slider keeps its meaning). Blue bends more than red.
     Why here: the whole point of the aberration term is a prism's dispersion; HEAD's symmetric
     ±δ is an unphysical placeholder.
  2. Energy-conserving bloom (§12.2F). The above-threshold part of the pixel is the light that is
     radiated into the glow, so it is *subtracted* from the core (`src −= emit·k; out = src + spread`)
     instead of the glow being added on top of the full source. Cores stop blowing out, the halo is
     the same light moved outward. The glow also persists through the HEAD's own `0.85 − mids·0.25`
     retention (rescue C1 — the dead feedback wired to the glow; see A packing).
     Why here: "volumetric glow" in a compositor is light scattering; HEAD invents energy.
  3. Depth-consistent parallax by fixed-point iteration (tactic 1 "deepen the kernel").
     The fetch offset is iterated 3× so it uses the depth of the point actually fetched
     (`o ← M·depth(uv + o)`), and the ghost blend fades where the iteration does not converge
     (depth edges / disocclusions) instead of smearing foreground shift onto background.
     Why here: the parallax ghost is the compositor's main depth cue; this keeps the same driver,
     slider and ghost blend and only fixes which pixel the shift belongs to.
RESCUES: C1 dead feedback → live glow afterglow; C2 exact `textureLoad` of C; C3 subsumed by idea 2;
  C4 subsumed by idea 3. HDR overflow: an identity-below-knee roll-off (x ≤ 0.8 unchanged,
  soft shoulder to 1.0) replaces "no limiter"; NO global ACES because Pass 1 already ACES'd its
  output (double tone-map would lift every mid-grey). Open call for the coordinator.
FORBID on this file: new springs / extraBuffer state, ripple shockwaves beyond the existing flare,
  IQ palette beyond the existing prismTint, new params, Fresnel / thin film, Snell / Beer–Lambert (rain),
  soft inverse-square.
A PACKING: CHANGED and declared — HEAD A.rgb = colour trail (`mix(finalColor, prev, …)`) that was never
  displayed; now A.rgb = the persisted **glow** (`glowLive`), A.a = semantic alpha, read back exactly as
  `textureLoad(dataTextureC)`. Display RGBA only on writeTexture. dataTextureB / extraBuffer untouched.
```

## §12.1 mechanism interrogation

- **Tactic 1 — deepen the kernel.** The parallax op is a backward warp by `M·depth(P)`; the better approximation of the same operator evaluates the depth at the fetched point (fixed-point / steep-parallax). The glow op is a gather bloom; the better one is energy-conserving. The aberration op is a three-tap lateral split; the physical one weights the split by Cauchy.
- **Tactic 2 — physics one step further.** A prism's first-order side effect is wavelength-dependent index (Cauchy: blue bends more). A glow's first-order law: energy leaving the source is radiated elsewhere, not created.
- **Tactic 3 — promote an intermediate.** `feedback` and `prev` are computed and unused; `count` (Σ glow weights) and `brightness` per tap are computed but only used for averaging; `depth` taps along the shift are never compared.
- **Tactic 6 — history.** C is read as *colour history* in HEAD and never shown. One piece of continuity that keeps the "temporal feedback with mids shortening it" intent: persist the glow (the part that should linger like phosphor / scattering) with the existing 0.85 − mids·0.25 retention.

## §12.4 formula admission

- Cauchy dispersion, energy-conserving bloom: both in the F table and claimed for this file by COMMON; both consume taps (`abDir`, `aberration`, `glow`, `layered`) already computed; deletion test passes (compositor remains a prism composite).
- Iterated parallax: not a table row — tactic 1 on the file's own `parallaxOffset`/depth loads; no new state or binding.
- No row used on any other fork's file by this fork.

---

# AMENDMENT (after the code was first written) — coordinator's salvage check

The coordinator asked for `git log -S'Ideas'` / `--follow` on both files before committing to ideas.

- **rain:** no `Ideas` anywhere in its history (`-S'Ideas'` empty; 7 commits, all "push fix"/initial). Nothing lost. Cards above stand.
- **prismatic-3d-compositor:** `9acc4b18` (sonnet/batch-28, 2026-11-09) shipped an upgraded version (197 lines, `Ideas:` afterglow + cursor light shafts) that `9b5cd56e` (jules-bot "Fix rotate and float errors") reverted to the Batch-22 text, deleting that batch's notes. Pulled from git: `9acc4b18:public/shaders/prismatic-3d-compositor.wgsl` (== `9b5cd56e^:`; copy at scratchpad `a/compositor_salvage.wgsl`) and its brief `9b5cd56e^:agents/swarm-outputs/claude-2026-11-09-sonnet-batch-28/BRIEFS.md` §8.

**Audit of the lost version** (read in full): clean on fork B's list — no `pow` with a negative base, no ACES/hue path, no state texels (it uses the plain trail in A read back as colour), C is read with an exact `textureLoad` at a clamped coord. Findings:
1. **Afterglow** (`max(prev − final, 0)·(0.45 + 0.4·(1 − depth))`, shown on top of the live frame, A = `mix(final, prev, 0.85 − mids·0.25)`): correct and it is exactly what HEAD's dead feedback was written to do (its own comment: "mids shorten the trail so busy passages stay crisp"). It keeps HEAD's A packing, which the contract prefers over my glow-only persistence (A.rgb = glow), so **adopted**, replacing my "R1 glow persistence". Fixes applied: `prev` clamped to [0, 8] (guards a NaN/inf trail from re-entering), shown value is the sum of unclamped HDR (see 3).
2. **Cursor light shafts** (4 taps toward the pointer): **not adopted.** The pointer on this file is a plain parallax driver (the lost card's own FORBID says so); making it a light is a costume, its look depends on the default pointer position, and it *adds* light that the energy-conserving glow (idea 2, mine) is built to account for — the two cannot both stand. With afterglow + my three ideas it would also exceed the 3-idea cap. Coordinator may overrule; the lost file is the recipe.
3. **No tone map / no limiter** (the lost header): "HEAD's over-range highlights are part of the look (a tone-map or hue-preserving clip dulled the clouds in renders)". This contradicts my first draft's `shoulder()` roll-off, which is **removed**. Pass 1 already ACES'd, so no ACES either (same conclusion as mine).
4. Not addressed by the lost version, still mine: Cauchy dispersion, non-conserving glow (C3), parallax of the wrong pixel (C4).

**Amended compositor card** (replaces the ADD / RESCUES / A PACKING lines above):
```
ADD (3): 1. Cauchy dispersion  2. energy-conserving glow (GLOW_EMIT = 0.75 of the radiated excess is taken from the core;
         0 = HEAD's additive, 1 = fully conserving; by eye, because the lost version records the blown-out cores as part of
         the look)  3. depth-consistent parallax (3-step fixed point + disocclusion fade).
RESCUES: afterglow (salvaged from 9acc4b18, audited), exact textureLoad of C. No shoulder. No ACES.
A PACKING: HEAD's, unchanged — A.rgb = trail colour mix(final, prev, 0.85 − mids·0.25) (HDR, read back as colour), A.a = alpha.
```
