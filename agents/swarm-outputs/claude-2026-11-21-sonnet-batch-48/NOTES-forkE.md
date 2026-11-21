# NOTES — fork E (sonnet/batch-48): hyb-kaleidoscope-pulse, rgb-topology

Cards + mechanism interrogation + formula admission: `BRIEFS-forkE.md` (written before any WGSL edit). Nothing committed. Baselines = worktree files at fork start (`<scratch>/e/<id>_head.wgsl` + `_prelude.wgsl`). Both files were already `#include "_prelude.wgsl"` at origin/main, so the WGSL diff below is only my change.

VM = SwiftShader; structural + picture checks only. **No real-GPU visual QA claimed.** Renders use the harness's synthetic `SRC=img` source (smooth sinusoid + 40/33-cycle ripple + two discs), square 512².

---------------------------------------------------------------------------
## hyb-kaleidoscope-pulse  (first pass)

**ADD (formula rows are §12.2E, both owned by this fork)**
1. **Mirror-bounce material — fold-count as material.** New `kaleidoFold()` (same fold as `kaleido()`, which is kept verbatim for the inner ring) returns the folded point, the reflection depth `k = min(m, 2N−m)` (m = half-wedge index; every crease of the `|.|` fold is a mirror) and the true distance to the nearest mirror line. `outRGB *= tint^k`, tint = `mix(1, (0.99,0.982,0.965), effect_mix)` per channel (energy loss + warm drift per bounce), and a ~1.5 px hairline groove at the mirror joints (depth 0.20·effect_mix, faded in with radius so the centre does not clump). The CA taps (`r`, `b`) get the same gain so the 0.35 chromatic mix does not undo it. Findable: `// ── Idea 1` in `main()` + `kaleidoFold()`.
2. **Object-cell twist — additive domain twist.** After the fold, the folded point is rotated by `effect_mix·0.35·sin(t·pulse_speed·0.35)·4r²` before the lookup. Rotating the *folded* point keeps exact mirror symmetry and straight mirrors; centre stays crisp. `sampleUV` feeds the CA taps, so they twist consistently. Findable: `// ── Idea 2`.

**RESCUE (changes the default look — flag loudly):** `segments = mix(3,16,x)` was fractional (default 9.5): `kaleido()`/`sdfStar()` wrap at atan2 = ±π where 2π is not a multiple of the wedge angle, leaving a visible angular seam on the left axis (HEAD render, y≈0.5, x<0.5). Now `floor(x+0.5)` → integer count, default 9.5 → **10**. Slider endpoints still 3 and 16; the slider now steps through whole wedge counts. The sdf-star `rays` benefit too (also seamless now).

**KEEP VERBATIM (all intact):** 4 params + roles; `fbmWarp`; `kaleido()` + `kPhase` drift; inner ring (×1.7, `segments*2`, −phase, 0.25·mix); `rdPulse`/`sdfStar`/`smin`/`attractorOrbit` pulse composite + colour mix; ACES; radial CA; semantic alpha; IGN dither; depth pass-through.

**A packing:** none — HEAD never writes A/B and never reads C; unchanged. Display RGBA in `writeTexture`, depth pass-through.

**Not changed, noted:** `centered = uv − 0.5` has no aspect correction (non-square canvases stretch wedges / pulse rings into ellipses). Left as is: a design quirk, not an unambiguous defect, and fixing it rewrites the 16:9 look. Harness is square-only so I could not check it anyway.

**Diff vs HEAD (512², color panel, >2/255 / mean |Δ|):**
- effect_mix = 0 and an integer wedge count (x = 0.3077): **0.0 % / 0.01** — ideas are exactly off at mix 0 (HEAD identical), so everything else is rescue-only.
- Default (incl. rescue 9.5→10): 95.7 % / 24.0. Integer-segments only (ideas only), t=3, final constants: both ideas 95.6 % / 24.8; **tint+seam alone 83.3 % / 8.5 (mean luma 0.380 vs HEAD 0.400, −5 %)**; **twist alone 82.4 % / 22.2 (mean luma 0.369, −8 %)**. A swirl displaces every sample, so a high changed-pixel % is inherent; identity check was visual (still an FBM-warped kaleidoscope with pulse/star, straight mirrors, plus joint hairlines and a warm falloff). Mean luma at default 0.349 vs HEAD 0.396 (−12 % combined).
- **Timing** (`agents/mr_ab.mjs`, 512², 40 cycles interleaved, 4 rounds): paired-median ratios 1.08 / 1.09 / 0.97 / 1.04 → ≈ **1.06×** HEAD (cap 1.3×).
- NaN 0 at: defaults; params 0,0,0,0 / 1,1,1,1 / 0,1,0,1 / 1,0,1,0.5 at t=7; black source.

**Gates:** precommit 2/2 (shared run with rgb-topology), naga-wasm 2/2, dead sliders 0 (all 4 sliders live: x→segments, y→pulse speed + twist breathing, z→pulse width, w→effect_mix), extrabuffer audit PASS (file does not touch extraBuffer).

**JSON:** `description` appended (visible behaviour changed). `params` untouched; `features` unchanged (no new audio/pointer claim, `kaleidoscope` already there); no `x-meta.upgrade.params` (file's x-meta has only `chunks_used`; not required).

**Header:** `Upgraded: 2026-11-21`, `Ideas:` (names both §12.2E rows), `Rescue:`, `A packing:` lines added.

**Decisions for the coordinator / user:** (a) integer wedge count changes the default (9.5→10) — only visible as the removed left-axis seam + slightly different wedge angle; (b) twist amplitude 0.35·mix is a taste call (0.7 looked like a different, petal-like effect at high mix, so it was halved twice); (c) hairline depth 0.20.

---------------------------------------------------------------------------
## rgb-topology  (creative first pass; HEAD had `Upgraded: 2026-08-21` hygiene, no `Ideas:`)

**ADD (all consume the height field the file already builds; none of the other forks' claimed rows)**
1. **Hillshade from the field's own gradient.** Forward differences of the same height the contours use (mean(photo)·0.8 + depth·0.2, ·elevExag, *without* the mouse tilt ramps) → Lambert `n·L`, `shadeN` normalised to 1.0 on flat ground and clamped to [0.4, 1.8]. The sun starts top-left and rotates with the file's existing `rotAngle` (pointer-owned; no new overlay). Lines are modulated 50 %, the photo that Source Blend lets through 75 %. Cost: +2 src taps, +2 depth loads, −1 duplicate tap (`sampG` was the same sample as `src` — now `src.g`, pixel-identical). Findable: `// ── Idea 1`.
2. **Supplementary dashed half-interval contours in gentle terrain.** `|cos x|` (zero set exactly midway between the main `|sin x|` lines, same per-channel phase `x`), width 0.8·line_thickness, dashes of 0.016·height px along the contour tangent (perp of image gradient + tilt-ramp gradient), visibility `1 − smoothstep(0.6, 3.0, |relief|)` so steep ground stays clean. Drawn in the existing per-channel colour × hypso like the main lines. Not stored in A. Alpha picks it up at half weight (`max(contourMask, suppMask·0.5)`). Findable: `// ── Idea 2`.
3. **Elevation-proportional parallax.** `tilt *= 0.55 + 0.9·mean(topo)` — high ground leans further from the pointer-centre (relief displacement / stereo disparity); ≈1× at mid elevation so Channel Separation keeps its amplitude. Findable: `// ── Idea 3`.

**KEEP VERBATIM:** 4 params + roles; `topoR/G/B`; golden-ratio intervals; main/hachure/index/ridge/runner/helix; `hypsoTint`; click fronts (bounded, `ripples[i].xy/.z` only); `crossMix`; spec; ACES; pointer (centre, rotation, held) and audio (`plasmaBuffer[0].xyz`) use; `outDepth` still from `contourMask` (not supp). 

**A packing (unchanged):** `dataTextureA = [mix(lineR,prev.r·0.82,0.22), …G, …B, finalAlpha]` — raw line masks, not display colour, never ACES; C is read with exact `textureLoad` and only feeds that persistence. Supplementary lines are *not* in A.

**RESCUES:** none needed (4 sliders live; audio from `plasmaBuffer[0].xyz`; `config.y` is the ripple count; no ACES negatives pre-grain, no illegal stores). Observation, not changed: `prev` (C) persistence reaches only A, never the picture; `uv` has no +0.5 (half-texel offset, harmless).

**Diff vs HEAD (512², color panel):** default (source_blend 0.4): 65.4 % >2/255 / mean 5.45 — driven by the relief-lit photo; **source_blend = 0: 16.1 % / 1.29** (contour map nearly identical: line shading, supplementary lines, parallax). Supplementary lines only show where the image slope is low (the synthetic source is slope-rich, so I verified them on `SRCFLAT=0.5`, crop-zoomed: dashed red/green stubs visible at the expected half-interval positions; they are faint/sparse on a flat grey source because the lines are multiplied by source colour like the main ones).
**Timing:** 4 interleaved rounds: paired medians 1.11 / 1.26 / 1.21 / 1.22 → ≈ **1.21×** (cap 1.3×; extra loads 3 net, ALU dominated).
**NaN 0** at: defaults; exercised (0.7,0.15,0.6,0.2, mouse 0.3,0.6 held, audio .6/.4/.3, click ripple); white source with all sliders 1 + held; black source with all sliders 0.
**Gates:** precommit 2/2, naga-wasm 2/2, dead sliders 0 (grepped by hand too: zoom_params.x/y/z/w all read), extrabuffer PASS.
**JSON:** `description` appended; `params` and `x-meta.upgrade.params` untouched; `features` unchanged (`mouse-driven`/`audio-reactive`/`depth-aware` already truthful).
**Header:** `Upgraded: 2026-08-21, 2026-11-21`, `Ideas:`, `A packing:` added.

**Unverified (needs a real GPU / a real photo):** how the hillshade strength reads on actual photographs (harness only has the synthetic source); dash legibility on real sky/low-gradient areas; the 16:9 look of the kaleidoscope.
