# Generative Eight — Implementation Notes

**Agent:** claude · **Date:** 2026-09-21 · Cards: [`BRIEFS.md`](BRIEFS.md) · +278 / −49 across eight WGSL files.
No saved `params` / `updatedParams` changed (asserted by script). JSON: `upgraded-rgba` added to `features` only,
plus truthful `mouse-driven` / `audio-reactive` / `temporal-feedback` / `semantic-alpha` where they were missing.

### `gen-cosmic-velvet-hypnosis` (+45 / −4)
- **Kept:** every spiral/ring/runner/moiré/weave term, drag torque, click halos, radial history pull, params.
- **Idea 1 — crushed-velvet pile:** `phaseGrad` (analytic gradient of `spiralPhase`) → `armTangent`; `nap` =
  ±1 value-noise patches; `sheen` vs a light turning at 0.21 rad/s → `pileLight` multiplies the velvet term, and
  `pileGlint` adds the highlights.
- **Idea 2 — nested octave wells:** `octave = log2(r)·k + t·rate` → `seam` darkens and `seamLip` rims each log
  octave. Hue steps by `floor(octave)·0.07` under the seam, and depth dips there.

### `gen-prismatic-serpent-river` (+33 / −5)
- **Kept:** lane/slither kernel, scales, fins, wake, current, drag, shed skins, params.
- **Idea 1 — finite serpents:** `bodyU` / `girth` / `presence`. The taper is folded into `bodyK`. The old periodic
  eyes drop to 0.4× and are gated by `presence`, and `headEye` sits at the head.
- **Idea 2 — prismatic dispersion:** `bodyRGB` puts R and B at `slither·(1±dispersion)`, with
  `dispersion = 0.04 + iridescence·0.14`. The base palette term now multiplies `bodyRGB`.

### `gen-cyber-terminal` (+39 / −6)
- **Kept:** curvature, column speeds, trail window (0.34), scanlines, 0.8 input mix, HDR history, params.
- **Idea 1 — segment glyph font:** `segmentGlyph()` draws 9 strokes (7-seg frame + stem + diagonal) chosen from
  `bits`. Glyph Sharpness still sets the half-width (`strokeWidth·0.5`).
- **Idea 2 — white-hot leader:** `leader` ≈ 1.6 cells at the head; `leaderBit` re-rolls at 30 Hz; near-white add.
- **Behaviour change, stated:** `trail = fract(dropPos − uv.y)` (was `uv.y − dropPos`). HEAD's bright end sat
  *behind* the falling drop. Without flipping it the leader would have been at the dim end.

### `gen-chromatic-oracle-jelly` (+29 / −7)
- **Kept:** grid/seed, every shape term, drag push, click prophecies, params.
- **Idea 1 — pulse-swim:** `swimPhase` / `contraction`. The bell narrows 38% and lengthens, `local.y` gets a
  thrust−coast surge, and the tentacles lengthen and straighten during the stroke.
- **Idea 2 — watching eye:** `gaze` from each eye centre (in p-space) toward `mouseP`, clamped at 0.045 cell units.
  The `lid` blink squashes the eye and hides the pupil, on a seeded schedule of about 0.25 s every 4.3 s.

### `gen-emergent-calligraphic-weave` (+34 / −4)
- **Kept:** curve/derivative/nib kernel, hairlines, hueMoment, held warp, click ink, history weight, params.
- **Idea 1 — over/under weave:** the stroke loop now stores `strokeVal` / `hairVal` / `weaveZ`. A second loop
  occludes each stroke by the strongest higher-`weaveZ` stroke (`cover = 1 − 0.85·occluder`). 10×10 worst case.
- **Idea 2 — dry-brush starvation:** `load` ramps along x and re-dips. `starve` raises a threshold on `bristle`
  noise, which is stretched along the stroke and runs at 1.6 cycles per nib across it.

### `gen-hyperbolic-tree` (+45 / −13)
- **Floor fix (not an idea):** fork choice `hash12(mobius·100 + i) > 0.5` → half-plane test `cross(dir, q − next) > 0`.
  HEAD's choice was white noise per pixel, so the tree was speckle. The C read changed from filtered
  `textureSampleLevel` to exact `textureLoad`. `hash12` is now unused and left in place.
- **Idea 1 — terminal leaves:** `hyperbolicTree` returns `(branchD, leafD)`; `tipLeaf` is coloured by `hue2rgb(blendedHue)`.
- **Idea 2 — geodesics:** `idealPolygonDist()` draws 7-gon and 14-gon ideal polygons, counter-rotating, with lines
  thinned by `(1 − r²)` and hidden under branches.

### `gen-protocell-division` (+28 / −7)
- **Floor fixes (not ideas):** (a) `fresnel = pow(1 − |d|·6, 3)` had a negative base for |d| > 1/6, which covers the
  whole background, and that is undefined in WGSL (typically NaN). The base is now clamped at 0. (b) C was
  sampled with a filtering sampler at *centred* coordinates, so it read the wrong pixels. It is now `textureLoad(coord)`.
- **Idea 1 — cleavage furrow:** `4·div·(1−div)` × a Gaussian across `x = cx`, returned as `.z` and lit inside the cell.
- **Idea 2 — mitotic nuclei:** `divN = smoothstep(0.12, 0.5, dp)` runs ahead of the membrane's `(0.3, 0.7)`.
  The two nuclei are smin-merged at rest and returned as `.w`, drawn with a dark fill and an iridescent rim.
  Alpha gets `+nucleusFill·0.35` because cell interiors were nearly transparent.
- `cellSDF` now returns `vec4` (it was `vec2`). Gradient taps still read `.x` only.

### `gen-ferrofluid-monolith` (+25 / −3)
- **Kept:** twist, box, shell, core, orbit camera, chrome, glow march, click field, params.
- **Idea 1 — Rosensweig lattice:** `field = helix · (0.3 + 0.7·crossHelix²)`. Average spike volume drops at the
  same Spike Strength, and the peaks keep their full height.
- **Idea 2 — core reflection:** closest approach of `reflect(rd, n)` to the y-axis, masked to `|y| > height`.
  The core cylinder sits *inside* the obelisk box and is only visible as the beam past the caps, so only that part
  reflects.

## Follow-ups found, not widened into this batch
- `grep -rn "pow(1.0 - abs(" public/shaders` → 20 more call sites. Some may have the same negative-base NaN as
  protocell. Needs a per-file read.
  - **Resolved 2026-09-26:** all 20 remaining sites (across 19 files; `gen-verlet-cloth-wind.wgsl` has 2) were
    read and traced back to their source, plus `digital-crease.wgsl` which was already independently clamped.
    Every site is provably safe — the base cannot go negative — by one of two patterns: (a) the inner term is a
    `dot()` of two vectors each run through `normalize()`/`safeNormalize()` (or a hardcoded unit vector) at the
    exact use site, so the dot product is bounded to [-1,1]; or (b) the inner term is `sin()`/`cos()` directly, or
    a `fract()`-derived triangle wave (`2·fract(x)-1` or `(fract(x)-0.5)·2`), both bounded to [-1,1] by
    construction. None matched the protocell shape (an unbounded scalar scaled past 1 before `abs()`). No shader
    files needed edits; `digital-crease.wgsl:177` was already `pow(max(1.0 - abs(animatedFold) / max(foldDepth,
    1e-4), 0.0), 5.0)` from an earlier pass. No `params`/`updatedParams` changed.
- Audio: `plasmaBuffer` is still never written (`audioDepth.ts:5`). Every audio term in these 8 files is silent
  in the app. No idea depends on audio.

## Gates
- `wgsl_precommit_gate.py --files` 8/8 (naga OK, bindgroup compatible, 0 extraBuffer violations)
- `audit:extrabuffer` PASS · `audit:dead-sliders` PASS (6 scanned; hyperbolic-tree + protocell have
  updatedParams only, so I grepped them by hand: all four `zoom_params` are live in both)
- `generate_shader_lists.js` + `check_duplicates.js`: 1383 unique
- Jest: 5 suites / 6 tests fail, **identical on clean `main` (stash-verified)**; 716 pass
- `SKIP_WASM_BUILD=1 npm run build`: compiled successfully
- Real-GPU visual QA: **external, not done**. The Cloud VM has no adapter.
