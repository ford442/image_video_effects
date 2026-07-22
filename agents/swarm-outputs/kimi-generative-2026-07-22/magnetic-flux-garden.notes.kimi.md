# magnetic-flux-garden — Optimizer Notes (Kimi, 2026-07-22)

**Role:** Optimizer

## Key changes

- **Curl-noise line weave:** added canonical `valueNoise` + new `curlNoise` (perpendicular
  finite-difference gradient of value noise, divergence-free). Injected as a small-amplitude
  offset (`curlAmp = zoom_params.z * 0.45`) into the flux-line march step so lines weave
  organically instead of lying perfectly smooth. Original harmonic `organicWarp` kept
  (amplitude unchanged at `organic * 0.15`, renamed `warpAmp`).
- **IQ cosine palette on bloom layer:** new `iqCosPalette(t)` blended into the curl/bloom
  color at `paletteMix = 0.3 * sat(zoom_params.w * 1.4)` — param-scaled, magenta/teal field
  coloring stays dominant.
- **Feedback clamp:** temporal accumulation now clamps `prev.rgb` at 1.2 pre-tint
  (`min(prev.rgb, vec3(1.2))` before the `* 0.9` decay mix) so bloom trails cannot blow out
  over time (luma-echo-warp lesson).
- **Slider rewiring (all 4 sliders drive shader-specific constants):**
  - `fieldLines` (x) → number of dipole field lines traced (4→24), now guarded with
    `max(fieldLines, 1.0)` before `u32()` cast to avoid degenerate loop.
  - `fieldStrength` (y) → split into `dipoleGain` (0.4→2.2, scales inverse-square dipole
    field vector in the march) and `lineGain` (0.3→1.8, flux-line brightness).
  - `organic` (z) → curl-noise amplitude (0→0.45) + original harmonic warp amplitude.
  - `bloom` (w) → `bloomGain` (0.2→1.5) glow gain + palette mix amount.
- **Polish:** updated hash21 to canonical constant `43758.5453123`; expanded header comment;
  preserved canonical 13-binding layout, `@workgroup_size(16,16,1)`, all three mandatory
  writes (`writeTexture`, `writeDepthTexture`, `dataTextureA`), ACES tone map, semantic
  alpha/depth. No binding 13 (shader doesn't use a history ring).

## Line count delta

- Before: 128 lines
- After: 197 lines (**+69**, within the +50 to +90 target; inside 178–218 range)

## Gate result

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/magnetic-flux-garden.wgsl`
  → exit 0, naga OK, bindgroup compatible, 0 warnings.

## QA flags / verify on real GPU

- **No GPU in this VM** — WebGPU adapter unavailable, so all visual QA is deferred to a
  real-GPU pass.
- Eyeballed constants to sanity-check visually:
  - `curlAmp` max 0.45 with noise domain `pos * 3.0` — verify the weave reads as organic
    wobble, not line breakup (break condition `dist < 0.02` unchanged).
  - `curlTime = time * 0.25 + bass * 0.4` and per-line phase `fi * 0.37` — check curl drift
    speed/pulse feel against audio.
  - IQ palette `a/b/c/d` vectors (0.45,0.38,0.55 / 0.35,0.30,0.35 / 1,1,1 / 0.55,0.20,0.75)
    chosen to stay in a cool magenta/teal family — confirm blend at ~0.3 doesn't fight the
    original magenta.
  - Feedback clamp at 1.2 with `* 0.9` tint and mix `0.025 + bass * 0.01` — confirm trails
    still accumulate visibly but no runaway white-out.
  - `dipoleGain` up to 2.2 lengthens the march step implicitly (`* 0.02` step scale
    unchanged) — check lines still terminate between poles at max Field Strength.
- Cost note: 24 lines × 40 steps × (4 value-noise taps for curl) worst case — watch fps on
  lower-end GPUs; slider defaults (fieldLines 0.44 → ~13 lines) keep the default frame cheap.
