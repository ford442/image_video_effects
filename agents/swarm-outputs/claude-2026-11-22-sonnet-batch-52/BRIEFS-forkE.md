# BRIEFS — fork E (temporal-rgb-ghost, chrono-luma-slit-scan)

HEAD copies: `/tmp/claude-0/-root-image-video-effects/547473e0-56ec-49ad-94b1-b40db5a7c127/scratchpad/e/h/<id>.wgsl`. Harness: `agents/mr_hist.mjs` (engine-faithful ring: the ring holds the shader's own presented OUTPUT — `docs/BINDING_CONTRACT.md:141` "copy presented color into historyTexture[head]").

## HEAD findings (measured, before any edit)

### temporal-rgb-ghost — HEAD destroys a static photo (RESCUE; JSON promises "Static areas appear normal")
Static photo (`STATIC=1 OSC=0`, defaults 0.17,0.67,0.8,0.25, silence): meanL 0.105 vs source ≈0.31; picture = black with a saturated cyan blob at the frame CENTRE (not at any object), blob grows with time (120 frames: brighter, bigger). Not "alpha ≈ 0": alpha is ≈1 (meanA 0.98); the coordinator's near-black came from dark RGB. Cause, attributed by scratch variants (static, 60 frames):

| variant | meanL | reading |
|---|---|---|
| HEAD | 0.105 | black + central cyan blob |
| no vignette, boost kept | 0.913 | WHITE-OUT: G/B feedback gain `blend 0.8 × lumaBoost 1.25 = 1.0` through the ring |
| vignette kept, no boost | 0.066 | BLACK: `applyVignette` multiplies the whole output, which is re-read from the ring every frame, so it compounds |
| neither | 0.313 | photo restored (= source) |

The two feedback errors cancel only where the vignette is 1 (radius < 0.09 → the cyan centre). Three further defects: (a) `applyVignette` uses `smoothstep(0.5, 0.5 - s, d)` with edge0 > edge1 (indeterminate in WGSL for runtime values; header says it darkens "ghost trails", code darkens the whole picture); (b) `disagree = |histG.g − histB.b|` compares two DIFFERENT colour channels, so on any static coloured photo it reads the photo's g−b chroma and desaturates the whole frame by up to 45% (Idea "disagreement fringe" is mis-built); (c) nothing leaks a ghost back toward the live frame, so blend → 1 latches an old frame forever.

### chrono-luma-slit-scan — healthy at HEAD
Static / moving / 120-frame renders keep the photo (meanL 0.21–0.29, stdL 0.05–0.06, nan 0), isochrones and runner windows visible. No picture-level defect. Tags: `click-reactive` TRUE (`u.ripples` warp loop, `u.config.y` count, `elapsed = time - ripple.z`); `fast-motion` UNEARNED (added by bulk commit 07a46977 "push fix" 2026-08-14, no fast-motion brief for this file anywhere in docs; the runners move 0.3–0.4 uv/s) → remove; `upgraded-rgba` UNEARNED (no ACES, output is a passthrough composite; isochrone ink is not emission) → remove (P-ACES c); `mouse-driven` MISSING though a held pointer visibly narrows the spread near the cursor (`held`, `mouse`) → add. alpha base 0.6 (photo at α≈0.6): catalog convention, left, flagged.

---

## Idea Card 1

```
SHADER: temporal-rgb-ghost
IDENTITY (one sentence): a three-tube colour camera with lagging tubes — R live, G and B trailing from the history ring — that leaves rainbow comets behind moving things and a clean photo where nothing moves.
KEEP VERBATIM: 4 params + roles (g_delay→G age, b_delay→B age, blend→ghost mix, displace→noise displacement + luma boost); R live + leading red; FBM displacement gated by motion; fractional G delay; B comet-tail integration; disagreement fringe (intent, see rescue); vignette on the trails; display-RGBA A; ring wrap at textureNumLayers.
RESCUES (default look changes — photo comes back):
  R1. vignette scoped to the ghost deviation only (picture untouched), spec-clean edges, corner-weighted so trails fade toward the corners.
  R2. luma boost moved off the channel gain: bounded lift only on moving pixels, soft-ceiling (1-x), so loop gain stays < 1 at default.
  R3. tube-lag discharge: hist is leaked 10%/loop toward the live pixel (phosphor/charge decay), so no ghost can latch (blend=1 still means "ghost only", but decaying).
  R4. disagreement fringe compares luma of the two delayed frames (not g vs b channels).
  R5. `mouse-driven` made true (idea 2) — else the tag would go.
ADD (2 native ideas):
  1. Highlight-weighted comet (tube comet-tailing) — each tap of the B tail is weighted by 1 + 3·L² of that tap's own luma, so bright highlights leave long comets and dark objects leave faint ones, as on a real tube camera (charge lag is signal-dependent). Operates on the loop and taps already there; no new taps.
  2. Held-pointer time focus — while the button is held, the G/B ages collapse toward 1 (and displacement fades) inside a round lens around the cursor: the operator pulls a subject into register while the rest keeps its rainbow lag. Native = a spatially varying version of the existing delay params (tactic 4); gated by `held` so the idle default is unchanged.
FORBID on this file: springs, ripples, IQ palettes, new params, any change to the ghost channel assignment (R live, G/B delayed), Schmitt latch (alpha is semantic and C is unread: no honest latch channel).
A PACKING: display RGBA (unchanged: A = finalOut).
```

Mechanism interrogation (§12.1). **T1 deepen kernel:** the B comet is a uniform-ish mean over ring ages (oldest ×2); next-better approximation of a lagging tube = signal-weighted integration. **T2 physics one step further:** a tube camera's lag is highlight-dependent (comet tailing) and decays exponentially (R3 is the same discharge law). **T3 promote an intermediate:** `motion` and per-tap `frame` colours are already in hand; luma of each tap is free. **T6 history it owns:** ring is read as colour; the leak keeps that reading (no new state, no C).
Formula admission: neither idea is a §12.2 row (domain-native). Deletion test: delete idea 1 → still the RGB ghost; delete the lag mechanism and keep only the luma weighting → not recognizable as the effect ✓. Expert test: a broadcast engineer would recognize "highlights lag longer" and "operator pulls focus" ✓.

## Idea Card 2

```
SHADER: chrono-luma-slit-scan
IDENTITY (one sentence): a luminance-keyed slit scan — bright pixels read the present, dark pixels read deeper into the history ring — with sweeping scan runners and topographic isochrones.
KEEP VERBATIM: 4 params + roles (temporal_spread→ring reach, warp_strength→ripple/depth warp, luma_gamma→key curve, original_blend); luma→age map; H/V runners (rates, pow 14/12); runner windows onto the oldest frame; raised-cosine shutter; slit-travel smear; isochrones; held-pointer spread narrowing; capped ripple warp; alpha formula; A = display RGBA.
RESCUES: none at picture level. JSON tags: drop `fast-motion` and `upgraded-rgba` (unearned), add `mouse-driven` (true).
ADD (2 native ideas):
  1. Runner wake (scan-beam persistence) — each runner leaves a sawtooth tail behind it: a sharp leading edge on the side it has just passed and an exponential decay of the oldest-frame window back toward the luma age (direction-aware: H runners trail toward -y, V runners toward -x, matching the sign of the existing phase). Extends the existing window gate asymmetrically; same noun (a scan).
  2. Long-exposure integration — a slit exposes longer where the scene is darker, so where the chosen age is deep (≥2 frames) the colour is the mean of the frame at that age and two shallower ones (≈2/3 and ≈1/3 of it), weighted by how deep the age is: dark regions show temporal blur of what happened over the span instead of a single frozen frame.
FORBID on this file: tri-linear per-channel time offsets (that is temporal-rgb-ghost's identity), springs, IQ palettes, Schmitt/field-interlace rows (not honestly native: A.a is semantic, C is unread), new params, changes to the luma→age map.
A PACKING: display RGBA (unchanged).
```

Mechanism interrogation. **T1:** the shutter crossfades two adjacent ages — the next-better slit model integrates the interval (idea 2). **T2:** a scanning beam keeps a decaying trace behind it (idea 1); a longer exposure integrates more motion (idea 2). **T3:** `ageFlt`/`ageLuma` is computed and reused only to pick two taps — promoted to the integration span; `windowGate` is promoted from a symmetric blip to an asymmetric gate. **T6:** ring read as colour; no new state.
Formula admission: neither is a §12.2 row. Deletion test: delete either → still this slit scan; keep only the idea without the luma→age map → not a slit scan ✓. Expert test: a slit-scan photographer says "a long exposure blurs" and "the scan leaves a trail" ✓.

Row use: no §12.2 rows used by either file (Schmitt row deliberately unused by both — no honest latch channel).
