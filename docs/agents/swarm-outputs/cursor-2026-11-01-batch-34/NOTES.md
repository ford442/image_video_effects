# Notes — cursor/batch-34 slit-scan and time-delay (2026-11-01)

Second pass on the files that already named ideas. Two (time-slit-scan: three) additions inside the existing path. Saved `params` stay byte-exact. No new spring. Seven pasted headers were migrated with `migrate_to_prelude.py` before the idea edit; that swap is not the upgrade.

`hyper-chromatic-delay` had been failing naga on the reserved name `target`. Renamed that local and removed the id from `src/contracts/wgsl_validation.json` (`ratchet` 21 → 20).

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| chrono-slit-scan | golden-ratio slit phases, smin field, count / width / speed / feather, LOD warp, held drag, heads, cross-runners, click fronts, early-exit decay | linear history RGBA in A. ACES on writeTexture only | jaw lip; transport weave |
| cyber-slit-scan | right-edge injection, bit crush, hue shift, scan speed, diagonal tear, held bend, click kick, conveyor, second head, treble crush | linear scroll RGBA in A. ACES on writeTexture only | crush contour; field interlace (§12.2B) |
| spectral-slit-scan | slit count, trail decay, chroma shift, curve amplitude, three curves, mouse parallax, wavelength stagger, luma-hold | ACES display RGBA (unchanged) | Cauchy bend (§12.2F); second diffraction order |
| temporal-slit-paint | four shapes, size / softness / diffusion, velocity stretch, slit stamp, frame-lines, state texel (0,0) | raw canvas RGBA; (0,0) stays cursor state. ACES on writeTexture | Gaussian slit exposure; stroke integration |
| temporal-slit-scan | axis, spread, reverse, original blend, tent pivot, click tears, spectral jitter, ring wrap, sub-frame mix, 1-2-1 shutter | ACES display RGBA. Binding 13 unchanged. C unread | highlight reciprocity; spatial slit width |
| time-slit-scan | count 1–3, shape modes, three SDFs, per-shape drift, drift speed and width | linear slit RGBA in A (exact C load). ACES on writeTexture | width-scaled jaws; exposure streak; along-slit age |
| time-lag-map | five mapping modes, delay length, pattern, motion gate, luma key, mouse and ripple bumps, chroma split | history RGB in A (unchanged). ACES on writeTexture | lag iso-lines; lag-gradient flow. Feedback Mix now sets the history write rate |
| phantom-lag-history | echo decay, lag offsets, hue cycle, luma in A.a, luma-weighted persist, age-tint, glow, mouse and ripple charge | ACES display RGB + luminance in A.a (unchanged) | neighbor glow; attack flash |
| temporal-distortion-field | freeze, warp, ghost count, depth weight, fbm cap, stasis bubble, ghost taps, past/present/future, horizon lens | ACES display RGBA, history via acesInverse (unchanged) | depth-scaled ghost step; bubble absorption (§12.2F Beer–Lambert) |
| temporal-phosphor-burn-motion-adaptive | motion sensitivity, decay ends, warm tint, ring ages, mouse lens, click stamps, band drift, hysteresis, colour aging | linear burn RGBA in A (hysteresis reads it). ACES on writeTexture | phosphor grain; neighbor bleed |
| hyper-chromatic-delay | RGB split, trail decay, shift speed, mouse influence, 7-tap spectral sum, per-channel lens, echo taps, existing spring | ACES display RGBA (unchanged) | Cauchy tap spacing (§12.2F); chroma delay line (§12.2B) |
| rgb-delay-brush | persistence, time split, brush size, absorption scale, per-channel catch-up, wavelength absorption, bristle, wet mix, click stamps, existing spring | delayed RGB in A (unchanged). ACES on writeTexture | semi-Lagrangian channel lag (§12.2C); wet-edge absorption (§12.2C) |

Formula use: Cauchy (§12.2F) on `spectral-slit-scan` and `hyper-chromatic-delay` only. Beer–Lambert (§12.2F) on `temporal-distortion-field` only. Chroma delay (§12.2B) on `hyper-chromatic-delay` only. Field interlace (§12.2B) on `cyber-slit-scan` only. Semi-Lagrangian and wet-edge (§12.2C) on `rgb-delay-brush` only.

Floor: `#include "_prelude.wgsl"` on all twelve. 16×16. Exact C where history is read (`time-slit-scan` no longer samples C through the filtering sampler). Saved params exact. `time-slit-scan` and `hyper-chromatic-delay` gained `upgraded-rgba` (and hyper `audio-reactive`) because the WGSL now does those things.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new on these twelve, catalogs regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Real-GPU visual QA is external.
