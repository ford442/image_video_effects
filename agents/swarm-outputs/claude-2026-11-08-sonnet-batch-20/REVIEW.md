# sonnet/batch-20 independent review

Reviewer renders and ablation copies: `/tmp/claude-0/-root-image-video-effects/a7fd97bc-7abc-4984-b5e3-cda67245fb07/scratchpad/review/`.
No repo files were edited. All 10 shaders compile under Tint (`verr: null`) and render with `nan: 0`
at defaults, silence, loud audio, pressed mouse, a click ripple, first frame and slider extremes.
Ablation copies (scratch only) confirmed every card idea changes the picture at JSON defaults. Doppler is the faintest (see finding 8).

## Verdicts

| file | verdict |
|---|---|
| topological-acoustic-knots | PASS-WITH-NITS (one real look bug, finding 1) |
| acoustic-string-theory | PASS-WITH-NITS (finding 2) |
| gen-string-theory | PASS-WITH-NITS (findings 2, 4, 9) |
| gen-audio-spirograph | PASS-WITH-NITS (finding 2, nits) |
| gen_grokcf_interference | PASS |
| gen-void-harmonic-cymatic-resonator | PASS |
| gen-stellar-acoustic-resonance-manifold | PASS-WITH-NITS (finding 8) |
| gen-quantum-superposition | PASS |
| gen-quantum-resonance-lattice | PASS-WITH-NITS (finding 10, pre-existing) |
| gen-acid-lissajous | PASS-WITH-NITS (finding 3, perf) |

## Findings, most severe first

### 1. MEDIUM-HIGH (look): topological-acoustic-knots.wgsl:153 quench noise is a block lattice, not correlated noise
`qPix = hash12(floor(gid / Bq) ...)` with `Bq = round(res.y/36)` (5 px at 192, 16 px at 576, 20 px at 720, ~28 px at the 1024 default working size).
The block grid is fixed, so the angle noise accumulated during the quench is a mosaic of axis-aligned squares.
The relaxation stencil is 1 px, so it cannot round the squares off in a realistic time.
Two consequences, both visible:
- At 576 and 720 px the black extinction brushes are rectilinear stair-steps.
- The "defects" (hundreds of grey 2x2 dots) are mostly block-corner artifacts. The number scales with the block grid, not with physics.

Failure scenario: default sliders, default audio, any working size at or above ~512 px gives a pixel-mosaic film.
At 192 px (the authors' test size) it passes for an organic look because the blocks are 5 px.
Evidence: `k_720_p0.png`, `k_block_vs_smooth.png`.

Minimal fix, tested in a scratch copy at 576 px / 100 frames. The film becomes organic and the defect count drops roughly 10x:
```wgsl
let qPix = vnoise(uv * 36.0 + vec2<f32>(fract(time * 1.37) * 91.7, 13.0)) - 0.5;
```
`Bq` can then be deleted. The Idea 3 header text ("smooth value noise, ~1/23 screen cells") describes this smooth noise, which `qCorr` only partly supplies at weight 0.6.

### 2. MEDIUM (platform): the state-texel `lastTime` is an absolute time stored in A, which is rgba16float on balanced/battery/auto tiers
Affected: acoustic-string-theory.wgsl:103 and 252, gen-string-theory.wgsl:144 and 238, gen-audio-spirograph.wgsl:104 and 287.
`docs/FORMAT_TIERS.md` says A/B/C are rgba16float on the balanced and battery tiers and on auto for integrated GPUs, with the host rewriting the storage format at compile time.
A half float has a 0.0625 step at t of 64-128 s, 0.25 at 256-512 s and 1.0 above 1024 s.
`dt = clamp(t - lastStored, 0.001, 0.05)` then becomes noise.
Simulated at 60 fps:

| t (s) | dt clamped low | dt clamped high | mean dt | true dt |
|---|---|---|---|---|
| 100 | 27% | - | 0.0186 | 0.0167 |
| 300 | 47% | 40% | 0.0238 | 0.0167 |
| 1100 | 48% | 48% | 0.0255 | 0.0167 |

Failure scenario: after about 2 minutes on an integrated GPU the sprung cursor, well or lens moves in jerks and about 1.5x too fast.
It stays bounded because dt is clamped, but it is visibly jittery. Minrender (rgba32float) cannot show this.
The sentinel survives: 0.7371 rounds to 0.7373 and the tolerance is 0.001. Positions and velocities are fine in half float.
Fix: store `fract(time)` in `(1,0).x` and use `dt = clamp(fract(time - st1.x), 0.001, 0.05)`. Simulated: dt mean error 0, std 1e-4 at t = 5, 300 and 4000 s.

### 3. MEDIUM (perf): gen-acid-lissajous.wgsl:181-215 costs 2.4x HEAD
On SwiftShader at 288 px / 30 frames, HEAD vs new: 91 ms vs 221 ms at default, 147 ms vs 388 ms with loud audio and 9 strands.
The 95-chord loop has a divide plus selects per chord, and the 12-chord refinement is only about 12% of it.
The NOTES identify this risk. A cheap mitigation is `SAMPLES = 64` (the refinement covers the coarser chord).

### 4. LOW-MEDIUM: gen-string-theory.wgsl:59 and 70 `cos(w * t * tFac)` multiplies absolute time by a pointer-dependent factor
While the button is held and the pointer drags, `tFac` changes continuously, so the phase changes by `w * t * dtFac`.
The re-phase grows with session time. A 1% pointer move changes the frame by 15.6/255 mean at t ~ 2 s and 33.9/255 at t = 300 s (`g_fret_diff.png`).
Failure scenario: dragging a held finger flickers all partials after minutes.
Fix: drop `* tFac` and keep the spatial remap, since the shorter segment already has higher spatial pitch.
Alternatively quantise `xf` for the `tFac` computation only.

### 5. LOW: gen-void-harmonic-cymatic-resonator.wgsl:152 plus lines 198, 207 and 225 change the default look beyond the two ideas
The 180-degree flip is correct: I derived `cu = (-1,0,0)`, `cv = (0,1,0)` and that the mouse warp is mirrored at HEAD. The fix is right.
Three exposure constants also changed (seam 0.045 to 0.018, nodal 0.075 to 0.105, shell x0.65), and the mean brightness at default audio drops from 0.59 to 0.54. These are disclosed in NOTES.
Both ideas read clearly: ablation diff 19 and 20 of 255 with default audio; breathing needs bass to be strong. No bug.

### 6. LOW: acoustic-string-theory.wgsl:182 new `exp(-pow(neg, 2.0))` site
Base `(p.x - pluckX) * 0.45` is negative on half the screen. HEAD already has the same pattern at lines 60-62, 146 and 170.
It works where the driver folds `pow(x, 2.0)` to `x*x`; the WGSL spec leaves it undefined, and it would be NaN on a strict implementation.
Fix: `let dx = (p.x - pluckX) * 0.45; exp(-dx * dx)`, and the same for the other five sites.

### 7. LOW (claim wrong, harmless): gen-audio-spirograph.wgsl:8 says the state texels sit "outside the vignette"
At the top-left corner `vignette = 1 - 0.8 * |uv|` is 0.43 on a square canvas and about 0.18 at 16:9, so it is not zero.
The two texels only lose their trail, which is invisible.
Separately, the Idea 6 stator teeth reach `nStator` ~ 165 and alias to a dither pattern at 384 px (see `s_cmp.png`). They are clean at 1080 p.

### 8. LOW: gen-stellar-acoustic-resonance-manifold.wgsl:216-218 Idea 6 (Dopplergram) is nearly invisible
At defaults the ablation diff is 0.96/255 mean with max 26. On the one big near star it reads as "cream to white", because `em_col * 1.5 * limb` saturates through ACES.
Limb darkening (Idea 5) is also subtle: 1.6/255 mean diff. The stochastic envelope (Idea 7) is clearly visible: 14/255.
Failure scenario: a user cannot tell the Dopplergram exists. Optional fix: scale the Doppler tint (0.55/1.1 to about 0.9/1.8) or apply it before the 1.5 gain.

### 9. LOW: gen-string-theory.json `params` added
This is new, not a changed saved param.
The app used to feed 0.5 for all four sliders (`WebGPURenderer.ts` and `frame.ts` default to 0.5). It now feeds the x-meta defaults 0.5, 0.6, 0.85, 0.5.
That gives 6 partials instead of 5 and damping 0.96 instead of 0.895: a slightly richer default.
NOTES says this is by design (restores the intended defaults).

### 10. PRE-EXISTING, unfixed: gen-quantum-resonance-lattice.wgsl:153 `ro` on the z-axis node column
The camera is inside a node at some times. At silence and default sliders, t = 2.1 s is a flat teal slab in both HEAD and new, and t = 6.3 s is a full-screen bright slab (about 1 in 18 sampled times).
Fix: offset `ro.xy` by (0.37, 0.29).
Related, also pre-existing and untouched: gen-acid-lissajous.wgsl:123-131 still keeps its spring in extraBuffer[133..138], so the mouse is raw.

## Verified OK

State-texel scheme (acoustic-string-theory, gen-string-theory, gen-audio-spirograph), checked from the code:
- Only same-pixel trail reads exist, and the two state texels are zeroed.
- `(2,0).r` (acoustic) is an ordinary pixel.
- No neighbour, blur or census reads.
- Every thread integrates the same step from the same C texels, so all agree.
- A first-frame render shows no NaN. Moving the pointer moves the well.
- acoustic-string-theory pluck: `pluckEnv` decays to about 0 within ~1 s, so a click render at t_end - 0.2 s is the right sample.

ACES negatives: none reach `aces()` in any of the ten.
- gen-string-theory clamps through `max(col, prev * 0.4)`.
- The quantum files and spirograph clamp before aces().
- grokcf, resonator and stellar use `max(...)`, or terms that are non-negative by construction.

Other checks:
- Audio is read only from `plasmaBuffer[0]` in every file.
- grokcf reads real FFT bins at `extraBuffer[5+...]`; the maximum index used is 45.
- No dead sliders: all four are live in every file.
- Role extensions, both disclosed, neither a dead or duplicate param: acid's Feedback Decay slider also sets the comet tail length; grokcf's Node Sharpness also sets the sand band width.
- grokcf aspect fix verified on 688x384: the drum is a circle.
- All card ideas are present in the WGSL: topological 230-232, 238-241 and 151-156; acoustic 151, 176-184 and 206-214; gen-string 53-60 and 107-111; spirograph 167, 170-173 and 196-203; and so on.

NOTES claims contradicted by my renders: none outright.
- "defects look like physics" (topological) is contradicted by finding 1 at larger sizes.
- Fork A's "each idea individually visible" is only partly true for Doppler and limb darkening (finding 8).
