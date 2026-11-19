# BRIEFS fork B — conv-fractal-kernel, data-moshing (both second pass)

Written BEFORE any WGSL edit. HEAD = origin/main 8c537fe6.

---

## SHADER: conv-fractal-kernel

IDENTITY (one sentence): a 15×15-tap blur whose per-tap weight comes from Mandelbrot-set membership (boundary taps weigh most, distance-estimator glint on the boundary), mouse warping the Mandelbrot centre, ripples injecting a Julia offset, alpha = fractal depth.

KEEP VERBATIM: 4 params and roles (kernel_radius → footprint/window size, fractal_zoom, iterations → maxIter, mouse_influence → centre warp); the 7-step (15×15) tap grid; `weight = pow(v,2)*0.45 + boundary*0.7 + 0.05`; boundary-vs-interior weighting and the glint (`pow(boundary,6)*0.35*(0.5+treble)`); ripple Julia perturbation; palette tint by depth; ACES on display; bass/mids/treble reads; A = display RGBA (written, C never read); depth passthrough. The escaped-point smooth-iteration formula is kept verbatim.

HEAD measurements (SwiftShader + CPU replica, scratchpad `forkB/`):
- At defaults, and across most of the slider space, **all 225 taps fall inside the main cardioid** (centre −0.375,0 ± 0.085): membership is a constant → the "fractal-shaped" kernel is a flat box. Mouse/zoom only reach the boundary at the extremes.
- `smoothIter = iter + 1 − log2(log2(dot(z,z)))` is also evaluated for non-escaped (interior) points, where `dot(z,z) < 1` → `log2` of a negative = **NaN on hardware** (SwiftShader happens to return log2|x| ≈ finite, so HEAD "works" only on this VM). `clamp(NaN,0,1)` is implementation-defined → interior weights/colour are undefined on a real GPU.
- `fractalDepth = Σv / Σw` (unweighted membership over *weight* sum) — measured meanA = 1.48 (alpha > 1, theoretical max 2.0), not the documented 0..1 depth.

MECHANISM INTERROGATION (§12.1):
- Tactic 1 (deepen the kernel): the weight uses only the *escape time* of each orbit. The same iteration also produces the orbit's geometry — what the real Mandelbrot literature calls an orbit trap — which exists for **interior** points where escape time is constant. Next-better approximation of "kernel shaped by the fractal": use that orbit geometry so the interior (the part of the set a default window lives in) has structure.
- Tactic 2 (physics one step further): the kernel plays the role of an aperture (bokeh) shape. A real lens' aperture image grows with defocus (circle of confusion ∝ |depth − focus|); the shape stays the same, its footprint scales.
- Tactic 3 (promote an intermediate): `x2 + y2` is already computed at the top of every Mandelbrot iteration for the escape test and thrown away — the circle trap reuses it. `depth` is already sampled for the passthrough write — it becomes the CoC signal (plus one sample at the pointer for the focal plane).
- Tactic 6 (history): file does not read C; no history idea is added (a persistence/feedback layer would be a costume).

ADD (2 native ideas):
1. **Circle orbit trap** (§12.2E "Orbit trap") — inside the existing escape loop, `trap = min(trap, |x2+y2 − r0²|)` (r0 = 0.35). The per-tap kernel weight is multiplied by `0.55 + 0.9·exp(−12·trap)` (Pickover-style ring/filament weighting). Interior taps get concentric-ring structure (a ringed, catadioptric-looking aperture); boundary taps get filaments. Energy is conserved because the modulated weight goes into `accumWeight`. Where HEAD's window was a flat box it is now an aperture with structure. *Why on this effect:* it is the missing information in the loop the effect already runs.
2. **Defocus-scaled aperture (circle of confusion)** — second-order of `kernel_radius`: the tap *pixel footprint* (not the fractal window) is scaled by `1 + 1.0·smoothstep(0.05, 0.6, |depth − depth@pointer|)` (up to 2×). The in-focus plane (depth under the pointer) keeps the HEAD blur; everything else blurs with the same fractal aperture, larger. With flat depth (no map) `|Δ|=0` → identical to HEAD. *Why on this effect:* a blur whose kernel is an aperture shape; bokeh scale follows defocus.

FORMULA ADMISSION (§12.4): (1) Orbit trap — row is in the generative/fractal table; consumes `x2+y2` the loop already computes; delete the idea → exactly the HEAD kernel; delete the Mandelbrot weighting and keep only the trap → no longer a Mandelbrot-membership kernel → additive, not replacing. (2) CoC is tactic 4 (not a §12.2 row): consumes the depth the file already samples; deletion test passes both ways; expert test: a lens designer recognises "aperture shape fixed, size ∝ defocus".

FORBID on this file: springs / extraBuffer state (not pointer-led beyond what it has), IQ palette changes (the existing depth palette stays as-is), new params, a feedback/persistence layer, Julia/Newton swaps, per-sample accumulators (SwiftShader cost).

RESCUES (HEAD defects, not ideas — no `Upgraded:` credit on their own):
- R1 interior smooth-iteration NaN: smooth value only for escaped points; interior taps get 1.0 exactly (documented fixed value, no NaN on hardware). Escaped-point formula unchanged.
- R2 alpha out of range: `fractalDepth` (alpha) = mean membership 0..1 (Σv/225); the palette tint factor uses the same value (was Σv/Σw ≈ 1.5).

A PACKING: ACES display RGBA (unchanged); alpha = mean fractal membership 0..1.

---

## SHADER: data-moshing

IDENTITY (one sentence): a per-pixel motion-vector field (raw sim in A: offset.xy, confidence, age) smeared along image flow, collapsed to one axis per macroblock, hit by bass/click corruption, rendered as the displaced source with block-edge ringing, R/B split, quantization and a residual spark where the vector changed.

KEEP VERBATIM: 4 saved params and roles (smear / block size / corruption / quantize); flow smear into `offset`; pointer scrub + the spring block (**kept as-is; see below**); capped click fronts; `corruptionEvent` + block hash; `macroblockMV` (0.72 mix); `residualSpark`; depth modulation of decay; clamp ±0.4; displaced sample + edge ring; R/B ±blockSize/2 split; HEAD's global floor quantize; treble band noise; ACES; semantic alpha; **A = raw sim `(offset.xy, confidence, age)`** exactly.

HEAD observations:
- Renders correctly on SwiftShader (no NaN, no blanks; quiet = soft mosaic, loud = heavy blockiness).
- **Not rescued, flagged:** `extraBuffer[133..138]` spring state is zeroed by the app's per-frame full-array `writeExtraBuffer` upload (`audioDepth.ts:49`, `frame.ts:281`), so `initialized` is never true and `springVel` is always 0 → `offset += springVel*scrubMask` is dead (the pointer still raises `confidence`). A proper fix needs somewhere to persist pointer velocity (not available without a new packing); out of scope for an in-place upgrade. New ideas deliberately do not depend on it.
- `age` is written to A but never read by anything.
- Alpha is constant 1 on opaque sources (`sample.a + (1−sample.a)·energy`); pre-existing design, not changed.

MECHANISM INTERROGATION (§12.1):
- Tactic 2 (physics one step further): real macroblock codecs (a) subsample chroma 4:2:0 — when a block's residual is lost the colour planes bleed block-shaped while the luma stays crisp; (b) run periodic intra refresh — a column of intra-coded macroblocks sweeps the frame every GOP and wipes accumulated prediction error. HEAD has neither; both are first-order consequences of "macroblock mosh".
- Tactic 3 (promote an intermediate): `blockId`/`blockSize` grid is already computed (reuse for the block-centre chroma tap and the refresh column); `age` is written but never used → the refresh resets it to 0 ("frames since last intra"); `confidence` is the natural "this block is corrupt" weight.
- Tactic 6 (history the shader owns): C is read exactly as raw state; the refresh acts on `offset/confidence/age` before the A write — no packing change.
- Tactic 1 (deepen the kernel): HEAD's MV is a per-pixel offset projected on the block's axis; making it block-rigid would *replace* the existing idea, so it is deliberately not done.

ADD (2 native ideas):
1. **4:2:0 chroma block bleed** (§12.2B "Chroma delay line (4:2:0)") — luma stays the pixel's own displaced luma; chroma (RGB−Y) is blended toward one tap at the macroblock-centre of the displaced position (`(floor(distortedUv/blockSize)+0.5)·blockSize`), weight `smoothstep(0.2,0.8,confidence)·corruption`. Corrupted blocks go block-coloured under crisp luma. Calm state (confidence≈0) and `corruption=0` reproduce HEAD exactly. One extra `textureSampleLevel`.
2. **Intra-refresh sweep** (codec artifact, §12.1 tactic 5) — a 2-macroblock-wide column band sweeps left→right on a 9 s GOP; inside it the stored vector field is wiped (`offset=0, confidence=0, age=0`) before the A write. The wipe is block-quantized (`floor(uv.x/blockSize)`) so it is made of macroblocks, scales with the existing Block Size slider, and regrows through the existing smear. The abrupt vector change at the band edge lights the **existing** residual spark — no new marker.

FORMULA ADMISSION (§12.4): (1) row is in the distortion/glitch table; consumes taps/`distortedUv`/`confidence` the file already has; deletion test OK both ways (delete the mosh → a chroma blocker with no motion is not data-moshing). (2) tactic-5 codec artifact with the same nouns (macroblock, GOP, intra, vector); acts only on state the file owns; deletion test OK.

FORBID on this file: IQ palette, ripple shockwaves beyond HEAD's, holographic scanlines, a second tear system, thin-film, any new param, any new A packing, a new spring/extraBuffer state.

A PACKING: raw sim `(offset.xy, confidence, age)` — unchanged; display ACES RGBA on `writeTexture`.

---

## Cross-batch dedupe note (§12.4)
Fork B uses §12.2B "Chroma delay line (4:2:0)" on data-moshing and §12.2E "Orbit trap" on conv-fractal-kernel. If fork C (crt/rgb-glitch-trail) also picks the 4:2:0 chroma row, that is the allowed 2-files-per-batch maximum.
