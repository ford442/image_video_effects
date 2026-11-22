# NOTES — fork D (audio-reactive-pyramid, audio-reactive-rgb-dispersion)

Cards: `BRIEFS-forkD.md` (written before any WGSL edit). Harness: `agents/mr_hist.mjs` (engine-faithful ring + extraBuffer[0..4] + FFT bins); a scratch copy `.../scratchpad/d/mr_hist_d.mjs` adds `ASPECT`, `FFT=lo|hi` (intra-band tilt) and `WHITE=1` (white-highlight test card). Scratch: `/tmp/claude-0/-root-image-video-effects/547473e0-56ec-49ad-94b1-b40db5a7c127/scratchpad/d/`.

## Findings that apply to both files (verified, not assumed)

- **Audio source**: `FFT=off` (bins zero, `extraBuffer[0..2]` and `plasmaBuffer` set to 0.8/0.6/0.5) is **bit-identical to silence** for both files (0.00 % px). Both read only the 128 bins at `extraBuffer[5..132]`; neither reads `[0..2]` or `plasmaBuffer`. There is no band scalar to move, so **no `plasmaBuffer` read was added** (adding one would be a fake rescue). `audio-reactive` / `fft-bins` tags are true: with bins driven, pyramid loud-vs-silence moves 66 % of px (max 0.061), dispersion 25–31 % (max 0.43–0.53 on hard edges).
- **Silence**: no NaN, never uniform. Pyramid = gentle floor enhancer (stdL 0.112); dispersion = exact pass-through (`totalPower < 0.001` fallback + `energy = 0`; its divides are guarded: `max(totalPower…)` is behind the early return, `bassMean/max(…,1e-4)`, `acc/max(wsum,1e-4)`).
- **extraBuffer / C**: neither writes extraBuffer, neither reads C. Nothing to fix; nothing added.
- **ACES / tags**: P-ACES applied — both are passthrough photo composites, no emitted light; no ACES added. JSON `features` already lack `upgraded-rgba` (correct); **no tag changes** in WGSL `Features:` or JSON `features`.
- **Hygiene I did NOT do**: the per-pixel 128-bin walk (pyramid 3 loops = 128 loads/pixel; dispersion one 128-iteration loop) dominates SwiftShader cost. A workgroup-shared reduction would need a barrier after the `global_id >= res` early return (uniformity rule) — left alone.

## audio-reactive-pyramid — 2 new ideas, no rescue

ADD (header `Ideas:` appended, `Upgraded:` += 2026-11-22):
1. **Across-edge fine band (oriented DoG)** — `BlurTap` keeps its H and V 5-tap responses; where the existing `edgeGate` fires, `levelFine = mix(orig − blur0, fineDom, edgeGate)` with `fineDom = (fineH·lumH² + fineV·lumV²)/(lumH² + lumV²)`. Isotropic fine level `½(h+v)` gave axis-aligned edges half the boost; continuous (equals the isotropic level at |h|=|v|; no `pow` of a signed value — squared by multiplication). `edgeGate` hoisted above the level; chroma split's `addFine` follows the oriented level. Comment `// ── Idea 2026-11-22 A`.
2. **Pitch-slid pyramid scales** — `avgBins` → `bandStats` (same sum/order → mean bit-identical, plus Σbin·pos centroid in the same loop, silence/guard → 0.5); blur steps `1·, 2·, 4· pitchScale(c)`, `pitchScale = 1 − 0.6(c − 0.5)` ∈ [0.7,1.3]; fine ← treble centroid, mid ← mid, coarse ← bass. Telescoping reconstruction ⇒ zero gain is still exactly the original. Comment `// ── Idea 2026-11-22 B`.

KEEP VERBATIM held: 4 params; bin ranges; silence floor; depth routing; chroma split; aniso gate (same thresholds); anti-halo envelope; A = display RGBA, source alpha, no ACES.
A PACKING: display RGBA (unchanged).

Isolation (256², 30 fr, JSON defaults `0.4,0.5,0.6,0.7`, mouse centre): **B alone vs HEAD: 0.00 % px at silence and at `FFT=flat`** (neutral by construction); with `FFT=lo` / `FFT=hi` (intra-band tilt) 5.5 % / 4.6 % px differ (max 0.058). A alone vs HEAD: silence 2.01 % px (1.54 % > 4/255, max 0.062), loud 1.25 % (max 0.102). **Final (A+B) vs HEAD: silence 2.01 %, flat 1.12 %, loud 1.33 % of px differ >1/255 (0.46–0.56 % >4/255); max 0.108.** Clamp bites on 5.8 % of px at loud (HEAD), so the anti-halo still bounds the result. Visible only on oriented edges (faint across-edge outline on the axis-aligned square/rim in the 4× crop); the synthetic scene is soft, so a photo with hard architecture will show more.
Timing (interleaved `mr_ab_hist`, 192², load 15–27 so noisy): paired-median **1.08 / 0.94 / 1.17×** HEAD over 3 rounds (min-ratio 0.79–1.54 — load noise); coordinator should re-time on a quiet box. The extra cost is 2 vec4 fields in a struct and one multiply-add per bin; no new loads.
Gates: precommit 1/1, naga-wasm valid (0 new), dead sliders 0, extrabuffer pass. Sweep (all-0 / all-1 sliders, audio 1,1,1 flat, silence, FFT off, 16:9, 9:16, white card): nan 0, never uniform.

## audio-reactive-rgb-dispersion — 2 new ideas + 1 rescue

RESCUE (aspect isotropy — changes the default look on non-square canvases): the linear axis (`dir · radialScale`) and the edge probe (`dir · 1.5/min(res)`) were uv-space offsets, so px size depended on direction. Proof on a 16:9 frame (320×180, red-tap pixel offset at the centre, flat audio, scale 1): **HEAD vertical 1.316 px vs horizontal 2.340 px (ratio 0.5625); NEW 2.340 px both.** Fix: `aspect = (1, W/H)` on the linear axis, probe = `1.5 px / res` per axis. **Square canvases: rescue-only variant is 0.00 % px vs HEAD at silence, flat and loud (bit-exact).** On 16:9 a vertical-ish fringe grows 1.78×; a horizontal one is unchanged. The radial branch is a uv scaling about the centre (isotropic already) — untouched.

ADD (header `Ideas:` appended, `Upgraded:` += 2026-11-22):
1. **Highlight-gated blue defocus — purple fringing (longitudinal CA).** `// ── Idea 2026-11-22 A`. The first cut (wide blue weights over the 5 existing taps) moved 0.07 % of px by ≤ 0.022 — **dead, because the taps only span 1–3 px** — so it was redesigned: 4 blue-only taps symmetric about blue's displaced position at ±0.8 / ±1.8 × the tap span (weights 0.7/0.3), gate = `smoothstep(0.6,0.9, brightest tap) · smoothstep(0.35,0.75, brightest − anchor luma)` (dark side of a clipped highlight only). Silence: span 0 → **exact pass-through (0.00 % px)**. White-card test: 1.8 % px change, max blue +0.27, a violet band on the dark side of the edge above the orange lateral fringe. Cost: +4 texture loads.
2. **r³ lateral CA profile (Brown–Conrady k₁, §12.2B, row owned by this file).** `// ── Idea 2026-11-22 B`. `axisRadial = radialVec·(0.35 + 0.65·|radialVec|²)`. Probe (bass-dominant audio, radialMix 0.6, along the midline, blended with the linear branch): ratio to HEAD **0.91 @ r 0.09, 0.82 @ 0.25, 0.78 @ 0.50, 0.84 @ 0.75, 1.00 @ 1.00 (edge midpoint), 1.36 @ corner**; the radial branch itself is ×0.51 at r = 0.5 and ×1.65 at the corner. Real music (per-bin bass ≫ treble) gives radialMix 0.3–0.6, so it is active in normal use, not only in the test.

KEEP VERBATIM held: 4 params; one-pass spectrum analysis; bandwidth-rainbow 5-tap smear with normalised weights; lateral/transverse mix; Cauchy tap spacing; edge-weighted falloff; G anchored; source alpha; A = mixed output (display RGBA); no ACES.
A PACKING: display RGBA (unchanged).

Final vs HEAD (square, JSON defaults `0.5,0,0.5,0.1`): silence **0.00 %**, flat 0.21 % (max 0.036), loud 0.16 % (max 0.032), bass-dominant 0.51 % (max 0.023) of px differ >1/255. Small because the harness scene has few highlights/corners with edges and the default scale/loudness keep the span at 1–2 px; the idea is dormant until there is a highlight AND a dispersion span. Timing (3 rounds, load 15–27): paired-median **1.03 / 0.98 / 1.05×**.
Gates: precommit 1/1, naga-wasm valid (0 new), dead sliders 0, extrabuffer pass. Sweep (all-0 / all-1, audio 1,1,1, silence, FFT off, 16:9, 9:16, white card): nan 0, never uniform.

## JSON
`description` appended for both (visible behaviour changed). `params`, `features`, `x-meta` untouched (features already truthful, no `upgraded-rgba` claimed).

## Not verified / open
- No real-GPU look; SwiftShader only. Both ideas are gated on image content (oriented edges / bright highlights), so a photo will show more than the synthetic scene.
- Timing is load-noisy (box at 15–27 during runs).
- The gates regenerated `reports/*` (audit timestamps) — expected; coordinator discards file by file.
