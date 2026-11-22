# BRIEFS — fork D (audio-reactive-pyramid, audio-reactive-rgb-dispersion)

Written BEFORE any WGSL edit. HEAD = bytes in `.../scratchpad/coord/head/` (copied to `.../scratchpad/d/<id>_head.wgsl`).
HEAD measurements (mr_hist, 256², 30 fr, JSON defaults, mouse centre): nan 0 everywhere; `FFT=off` is **bit-identical to silence** for both files (0 px differ) → the 128 bins `extraBuffer[5..132]` are the *only* audio source; the `[0..2]` scalars and `plasmaBuffer` are never read by either file (so the pasted "never reads plasmaBuffer" is true but there is no band scalar to move — no change made, no rescue claimed). Audio is visibly alive: pyramid loud-vs-silence 66 % of px differ >1/255 (12.5 % >4/255, max 0.061); dispersion 25–31 % of px differ (max 0.43–0.53 on hard edges). `audio-reactive` tag is TRUE for both. Silence: no NaN, no uniform picture (pyramid = gentle floor enhancer, dispersion = exact pass-through through its `totalPower < 0.001` fallback and `energy = 0`).

## SHADER: audio-reactive-pyramid

IDENTITY: three-level Difference-of-Gaussians detail pyramid (fine/mid/coarse ← treble/mid/bass FFT bands) that boosts a photo's detail in time with the music; a passthrough photo enhancer with source alpha.

KEEP VERBATIM: 4 params and roles (Bass/Mid/Treble Gain, Overall Blend); bin ranges 0–12 / 13–50 / 51–127 averaged; blur steps 1 / 2 / 4 px (HEAD values stay the neutral value); telescoping reconstruction (zero gain = exact original); silence floor (slider × 0.5); depth-routed bands; per-band chroma split; anisotropic fine gate; anti-halo envelope; A = display RGBA (source alpha), C not read; no ACES (P-ACES: passthrough class, header already says so; JSON has no `upgraded-rgba` — correct).

MECHANISM INTERROGATION
- Tactic 1 (deepen kernel): `gaussBlur` averages a horizontal and a vertical 5-tap response. The isotropic fine level is `orig − ½(col+row) = ½(h+v)`; on a pure axis-aligned edge one of `h,v` is ≈ 0, so the fine band reacts at **half** the strength it has on a blob or diagonal. Next-better approximation of the same operator: keep the two responses apart where the image is oriented.
- Tactic 2 (physics one step further): the effect is a frequency-coupled visualiser, but the audio→spatial-frequency coupling stops at the gains; the three spatial scales never move. Higher pitch inside a band ↔ finer scale is the one coupling the mechanism implies and does not yet do.
- Tactic 3 (promote an intermediate): (a) `col` and `row` are computed, averaged, and only `|H−V|` survives (as the gate); their separate DoG responses are thrown away. (b) `avgBins` already walks every bin of a band; `Σ bin·position` costs one multiply-add in the same loop and is thrown away.
- Tactic 6 (history): not applicable — C is not read back and A is display RGBA; no state is added (and none is possible in `extraBuffer[0..132]`; `[133..255]` is zeroed every frame).

ADD (2):
1. **Across-edge fine band (oriented DoG, tactic 7).** `BlurTap` also returns the H and V responses. Where the *existing* anisotropy gate (`edgeGate`) says the 5×5 neighbourhood is oriented, the fine level uses the dominant directional DoG (`orig − col` or `orig − row`, whichever has the larger |luma|) instead of the H/V average: axis-aligned edges get the full-strength fine boost (HEAD gave ½) and the along-edge component (jaggies, noise) is not boosted. Blob/diagonal pixels (h≈v) and flat pixels (gate 0) are unchanged. Reuses the gate; no new gate, no new slider. The chroma split's `addFine` follows the same level so the tint stays consistent.
2. **Pitch-slid pyramid scales (tactic 4).** The bin loop also yields each band's intra-band spectral centroid `c ∈ [0,1]` (low bins of the band → 0). The band's blur step is scaled by `1 − 0.6·(c − 0.5)` (∈ [0.7, 1.3]): treble centred high → the fine DoG gets finer; a bass line sliding up → the coarse DoG tightens. Fine blur ← treble, mid ← mid, coarse ← bass. **Neutral at silence (fallback c = 0.5) and for any spectrum symmetric about the band centre (flat → c = 0.5 exactly) → HEAD's 1/2/4 steps bit-for-bit**; the telescoping reconstruction means zero gain is still the exact original whatever the steps.

FORBID: ACES; new params; reading `[0..2]`/plasmaBuffer to "satisfy" the paste; springs / state / C feedback; a coring or second noise gate (duplicates the aniso gate); Wallis / structure tensor (spatio-temporal-3d-conv owns those rows — mine is the H/V pick of the taps the kernel already has); changing the 4 saved params.

FORMULA ADMISSION: no §12.2 row used (both are domain-native, §12.1 tactics 7/3 and 4/3). Deletion test (both directions): delete #1 → exactly the HEAD pyramid; keep only #1 and delete the DoG pyramid → just an oriented unsharp, not this effect. Same for #2.

A PACKING: display RGBA (unchanged), source alpha.

## SHADER: audio-reactive-rgb-dispersion

IDENTITY: chromatic (RGB) dispersion: R and B pushed in opposite directions along an axis that rotates with the spectral centroid, magnitude ∝ loudness; passthrough photo effect with source alpha.

KEEP VERBATIM: 4 params and roles (Scale, Angle Offset, Edge Falloff, Orig Blend); one-pass spectrum analysis (centroid / energy / spread / balance, silence fallback); 5-tap wavelength smear with per-channel normalised weights (bandwidth rainbow); lateral vs transverse mix by band balance; Cauchy tap spacing; edge-weighted falloff; G anchored at the undisplaced UV; source alpha; A = display RGBA (the mixed output); no ACES (P-ACES: no emitted light, nothing to tone-map; JSON has no `upgraded-rgba` — correct).

MECHANISM INTERROGATION
- Tactic 1 (deepen kernel): the smear uses ONE response width for all three channels (`respW`). In a real lens the channels are not equally sharp: the blue (and red) focal planes differ from green's.
- Tactic 2 (physics one step further): (a) a lens/prism with lateral CA also has **longitudinal** CA: the out-of-focus channel leaks a halo around bright, hard edges (purple/violet fringing — the visible signature photographers name). (b) first-order lateral CA is linear in field radius, but real lens CA carries a third-order term (Brown–Conrady `k₁r²` per channel): corners fringe far more than the centre. HEAD's radial branch is purely linear.
- Tactic 3 (promote an intermediate): the 5 fetched taps' luma is discarded; the brightest tap inside the dispersion reach says whether a highlight is in reach. `anchor` luma says which side of the edge we are on.
- Tactic 6: not applicable (no C read, no state).

ADD (2):
1. **Highlight-gated blue defocus — purple fringing (longitudinal CA).** A second, wide blue accumulator rides the same 5 taps (`respW`-independent width ≈ 0.6). Blue is mixed toward it by `gate = smoothstep(0.6,0.9, brightestTapLuma) · smoothstep(0.35,0.75, brightestTapLuma − anchorLuma)` — only on the *dark side of a clipped highlight*; elsewhere identical to HEAD. Its reach is the existing tap span, so it is audio-coupled for free (`dispersion = 0` → taps coincide → no fringe; silence still exact pass-through).
2. **r³ lateral CA profile (Brown–Conrady k₁, §12.2B — I own the row).** The radial axis magnitude becomes `r·(0.35 + 0.65·r²)` (with `r = radialDist`): equal to HEAD at r = 1 (edge midpoints), ≈ ½ at r = 0.5, ≈ 1.65× at the corners (r ≈ 1.41). Bass-dominant hits bloom from the corners, the centre stays clean, like a real lens. Only the radial (bass) branch changes; the linear (treble) branch is untouched.

RESCUE (aspect isotropy; says so loudly): the linear axis and the edge-probe footprint are offsets in **uv units**, so on a non-square canvas the fringe is anisotropic (16:9: a vertical fringe is 0.5625× the px size of a horizontal one) and the "angle" the centroid/slider rotates through is not the on-screen angle. Fix: scale the uv-space y component of the linear axis and of the probe by `res.x/res.y` so the px offset is `dispersion·W` in every direction (= HEAD's horizontal case; documented "≈3 % of width"). Square canvases: **0 px diff vs HEAD** (checked). On 16:9 the default look changes for non-horizontal angles (vertical-ish fringes grow 1.78×). The radial branch is a uv scaling about the centre (isotropic) — untouched.

FORBID: ACES; new params; blur on the whole image; thin-film / rainbow overlays; Cauchy / smear changes (shipped); state/C; reading `[0..2]`/plasmaBuffer to satisfy the paste.

FORMULA ADMISSION: Brown–Conrady row (§12.2B, owned by this file): one sentence on family — lateral CA *is* a per-channel radial distortion, so this lens-CA shader is the lens-distortion family; it consumes `axisRadial`/`radialDist`, which already exist; deletion test: delete it → HEAD's linear radial CA (still this effect); keep only it → no dispersion smear/centroid/rotation. Idea #1 is not a §12.2 row (tactic 2/3, longitudinal CA).

A PACKING: display RGBA = the mixed output (unchanged).
