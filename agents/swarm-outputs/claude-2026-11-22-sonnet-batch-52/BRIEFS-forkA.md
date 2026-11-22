# BRIEFS — fork A (sonnet/batch-52): temporal-frequency-decomposition, spatio-temporal-3d-conv

Written BEFORE any WGSL edit. HEAD = `/tmp/claude-0/.../scratchpad/a/<id>_head.wgsl` (identical to coordinator head/). Harness: `agents/mr_hist.mjs` (8-layer ring of outputs, FFT bins, [133..255] zeroed).

## HEAD findings (measured)

1. **temporal-frequency-decomposition — static DC leakage (rescue).** Header says "static pixels cancel to zero". At the default 0.25 → 0.1625 cycles/frame the Hann (N=8) mainlobe is ±2 bins = ±0.25 c/f wide, so DC sits 1.3 bins away *inside* the mainlobe and ~40 % of any bright still pixel leaks into the response. Seen in the HEAD render: a red/orange blob that follows the lens over a perfectly static textured background (`scratchpad/a/cmp_lens.png`: lens at corner → blob at corner, lens at centre → blob at centre; STATIC=1, OSC=0 reproduces it). Also: the whole frame carries a faint yellow tint of its own DC.
   (Note for method: glow-only (blend 0) static renders look clean only because the ring holds OUTPUTS, i.e. no signal left to leak — blend 0.8 is the honest test.)
2. **temporal-frequency-decomposition — dead per-region FFT voices (rescue).** `voice = plasmaBuffer[band+1].x*0.4`: the engine writes `plasmaBuffer[0]` only (`audioDepth.ts:62-72`; buffer is plasma-ball storage, nothing writes [1..8]) → voice ≡ 0 and the "8 vertical bands ride their own bin" claim is false. Real per-bin data is `extraBuffer[5..132]` (128 bins).
3. **temporal-frequency-decomposition — dead spring.** Lens spring state lives in `extraBuffer[133..137]`, zeroed every frame by `writeExtraBuffer`, so every frame is a cold start: lens = raw cursor 1:1 (it never lags). Behaviour is fine; the header claim "sprung / critically-damped" is not true. Not rescued (no new state allowed; code left, header corrected). Header note "extraBuffer[0..2] are NOT bass/mid/treble" is also wrong per `audioDepth.ts:48` — corrected.
4. **temporal-frequency-decomposition — unearned `upgraded-rgba` / HDR glow.** No ACES; the glow term can reach `4 × glowBright(≤2.4)` and is clipped. P-ACES (b): tone-map the emitted glow only.
5. **spatio-temporal-3d-conv — clean.** Three modes verified by reading: NR (bilateral-in-time + variance-driven strength), MOTION BLUR (0.85^age trail), TEMPORAL SHARPEN (current + 2·strength·(current − mean), clamped). `histDepth` handled. No ACES, pure passthrough → P-ACES (a)/(c): no ACES, drop the unearned `upgraded-rgba` tag (header + JSON). `bass` scales strength, `treble` NR decay → `audio-reactive` is true. `mode > 0.67` clamps all four channels incl. alpha (source alpha is 1) — fine. Spatial sigma convolves the *current* frame too, so the whole picture is a 3×3 Gaussian at every mode (the effect's "3×3×T" kernel) — kept.

---

## SHADER: temporal-frequency-decomposition

IDENTITY: single-frequency temporal Fourier analysis over the 8-frame history ring; pixels oscillating near the target frequency glow, hue = DFT phase, overlaid on the live frame, with a cursor lens and click pings.

KEEP VERBATIM: 4 params (target freq → 0.05..0.5 c/f, glow brightness, glow hue, base blend) and their roles; Hann window (Idea 1); phase→hue (Idea 2); `textureNumLayers` ring depth; cursor lens (sharpen/widen); click tuning-fork pings; 8-band voices (rescued to real data); alpha formula; A = display RGBA (= writeTexture).

MECHANISM INTERROGATION:
- tactic 1 (deepen the kernel): the operator is a windowed DFT at one frequency. A real spectral estimate removes the mean first (detrend) because with N=8 the DC lobe covers half the spectrum — windowing alone cannot fix leakage that is inside the mainlobe.
- tactic 2 (physics one step further): a spectrum analyser / lock-in amplifier shows not only the amplitude at the tone but how much of the signal is *that tone*: coherence / purity. A pixel with sensor flicker has energy at every frequency; a pixel with a true oscillator has it at one.
- tactic 3 (promote an intermediate): the tap loop already fetches every sample but throws away Σw·x (the mean) and Σw·x² (the windowed energy) — both free.
- tactic 6 (history already owned): the ring is the only memory; both ideas use only the same 8 samples, no new state.

ADD (2):
1. **DC-detrended DFT** — subtract the window-weighted mean before projecting: `X' = Σw x e^{-iωt} − μ·Σw e^{-iωt}`, `μ = Σw x / Σw` (one pass, scalars `Σw cos`, `Σw sin` shared across channels). Static pixels now give exactly 0 at every frequency; a pure tone loses only its own small DC-projection. Fixes HEAD finding 1 (visible: lens blob and global tint disappear; glow lives only on oscillators).
2. **Spectral purity → glow saturation** — `purity = clamp(2·mean(|X'|²/Σw²) / (mean(Var)+ε), 0, 1)` where `Var = Σw x²/Σw − μ²` (windowed AC variance; a pure tone at the selected bin gives ≈ 1, broadband flicker/noise ≈ 0.2 for an 8-tap Hann). Glow saturation = `mix(0.25, 1, smoothstep(0.25, 0.75, purity))`: true oscillators glow in the chosen/phase hue, noisy flicker glows pale/white.

Rescues (not ideas): R-voices (FFT bins from `extraBuffer[5..132]`, 4 taps per band); R-ACES (P-ACES b: aces on the glow term only, clamped); header truth (spring, audio note, A packing line).

FORMULA ADMISSION: neither is a §12.2 row (no ownership issue); both consume the taps already fetched; delete #1 → HEAD leakage; delete #2 → HEAD single-saturation glow; deleting the DFT leaves nothing → additive, not replacing.
FORBID: new params, new springs, a second frequency/harmonic bank (that would be a different analyser), IQ palette, ACES on the photo path.
A PACKING: display RGBA, unchanged (A = writeTexture); ring holds outputs, so analysis includes the glow — documented, kept.

---

## SHADER: spatio-temporal-3d-conv

IDENTITY: 3×3 Gaussian spatial kernel × T history frames, three modes by `mode` slider: temporal noise reduction, motion blur trail, temporal sharpening.

KEEP VERBATIM: 4 params and roles (spatial sigma, temporal depth 2..7, mode 0/0.5/1 with thresholds 0.33/0.67, strength); NR bilateral-in-time weights (Idea 1) and variance-driven strength (Idea 2); `tw` profiles; bass → strength, treble → NR decay; ring depth guard; A = display RGBA.

MECHANISM INTERROGATION:
- tactic 2 (physics one step further): (a) a shutter integrates *photons* — linear light — so a bright light trail stays bright; averaging gamma-encoded values dims every highlight streak. (b) A temporal unsharp mask amplifies whatever the temporal mean cancels, and sensor noise is exactly that — real temporal sharpeners "core" the residual below the noise floor.
- tactic 3 (promote an intermediate): `noiseSigma` (similarity-weighted luma stddev, idea 2) is computed every frame in every mode and consumed only by NR.
- tactic 6 (history already owned): ring of outputs; no new state.
- tactic 1: the kernel (3×3 Gaussian × temporal weight) is already the right operator; deepening it (non-local patches, motion compensation) would be a new filter.

ADD (2):
1. **Linear-light shutter integration (motion-blur mode only)** — accumulate `max(rgb,0)²` (γ≈2 stand-in for sRGB→linear) with the existing 0.85^age weights and mix with the current frame in that space, back with `sqrt`; strength/weights/trail length unchanged. Bright streaks (headlights, blinkers, specular edges) read brighter and thinner dark objects stay crisp, as in a camera. NR and sharpen paths untouched.
2. **Noise-gated temporal coring (sharpen mode only)** — gate the residual by its own noise floor: `c = 1.5·noiseSigma + 0.004`, `gate = smoothstep(c, 3c, rms(residual))`, `result = current + residual·gate·strength·2`. Clean video: c≈0.004 so the look is HEAD's; noisy video: static noise stops being amplified while real transients (whose similar-frame set is small → noiseSigma≈0) still pop. Reuses idea 2's estimator, no new taps.

Tag/metadata: remove unearned `upgraded-rgba` (no ACES, passthrough; P-ACES a/c). Keep `audio-reactive`, `temporal`, `history-ring`.
FORMULA ADMISSION: neither is a §12.2 row (the sharpen anti-halo row belongs to audio-reactive-pyramid; coring is a separate mechanism, not an envelope clamp). Both operate on quantities already computed (`accumColor`, `noiseSigma`, `current`). Deletion tests pass both ways.
FORBID: ACES/tonemap on the passthrough, springs/ripples/pointer, new params, a fourth mode, motion compensation / flow.
A PACKING: display RGBA, unchanged.

---

## AMENDMENT after implementation (briefs above were written before any edit and are left as written)

- **temporal-frequency-decomposition Idea 2 (spectral purity → glow saturation) was BUILT, MEASURED and DROPPED.** Measured purity (`2·mean(|X'|²)/mean(AC var)`, scratch debug output): pure-noise static scene median 0.68–0.74 (p10 0.27–0.55, p90 0.82); 4-frame blinker 0.63–0.74; 8-frame blinker 0.37–0.50. An 8-tap Hann window has ~6 AC degrees of freedom, so a single-bin purity cannot separate tone from noise (my brief's "≈0.2 for noise" had the Parseval normalisation wrong; white noise is ≈0.46 on average with an exponential spread). Chroma in noise regions dropped only 12–15 % with the idea on. Fails the expert test, code removed. The file ships **one** idea (DC-detrended DFT) + rescues. No honest second idea found: peak-over-neighbour-bin subtraction is just another window (no resolution gain); harmonics alias at the default frequency.
- **temporal-frequency-decomposition new rescue found in verification:** the lens `pow(e, 1 − 0.25·lens)` (unbounded small-signal gain) + ring-of-outputs feedback = self-sustaining glow ghost after a disc crossed the lens (visible in NEW once the tint was gone; HEAD has it too, masked by the red haze). Replaced by a dead-zone sharpen ≤ the stable ×1.8 gain.
- **spatio-temporal-3d-conv new rescue found in verification:** HEAD motion-blur diverges (meanL −3.59, meanA −11.2 at p4=1.0, bass 2) because `mix(current, trail, strength·0.8)` extrapolates (live weight < 0) and the ring feeds it back. Trail weight now capped at 0.95 (not 1 — weight 1 lets no live frame in and an empty ring stays black: found by this very test).
- **Idea 4 coring tuned by sweep** (floor k × noiseSigma, knee): k=1.5/3 → 73 % boost kept, −63 % noise; **k=1.0/2 → 88 % kept, −51 % noise (shipped)**; k=0.7/2 → 91 %, −38 %; k=0.5/2 → 93 %, −29 %. Noise = static scene, uniform ±0.1 per-frame luma noise, HEAD noisy-vs-clean output error 0.0373 → 0.0183.
