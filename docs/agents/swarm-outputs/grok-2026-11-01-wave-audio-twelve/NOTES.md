# Notes — wave / audio twelve (2026-11-01)

Per shader: what stayed, packing, and where the new ideas sit. Real-GPU visual QA was not run (no hardware adapter on this VM).

## sine-wave
- Kept: amplitude / speed / scale / chroma detail; both carriers; packets; standing nodes; Stokes drift; click fronts.
- Ideas in the diff: `cRatio` on `phase2` only (deep-water dispersion, §12.2D); `groupShade` from `packetX`/`packetY` before ACES.
- A packing: telemetry `(offset.xy, crest, alpha)`. ACES on `writeTexture` only.
- Header migrated to `#include "_prelude.wgsl"`.

## spectral-waves
- Kept: frequency / speed / amplitude / aberration; spring `[133..138]`; wave + echo; click trains; caustic palette; C history mix.
- Ideas: `split = aberration * (0.3 + 0.7 * |cos|)`; `contrastGain` from a one-texel luma difference multiplies the existing displacement.
- A packing: premultiplied ACES display RGBA. C is that history.
- `i++` in the ripple loop replaced with `i = i + 1u` so the file validates.

## digital-waves
- Kept: intensity / speed / scale / detail as the shader already mapped them; three-sine pattern; standing nodes; crest scanlines; glitch blocks; spring; diagnostic A.
- Ideas: posterize `steps` fall toward `|wavePattern| == 0`; pixel snap sheared by `wavePattern * pixelSize`.
- Regional tint now reads `extraBuffer[5 + band]` instead of `plasmaBuffer[band + 1]`.
- A packing: raw diagnostic `(wave, depth, ripple, alpha)`. ACES on `writeTexture` only.

## sonic-distortion
- Kept: frequency / speed / amplitude / radius; superellipse; four Lissajous sources; 3-harmonic sum; rose; FBM warp; echo mix.
- Ideas: `chaosWave` returns `|first × second|` and that beat tints inside the mask; `petal = |cos(3.5·angle)|` darkens the rose gaps.
- Bass swells the existing amplitude. C is an exact `textureLoad`. A is pre-ACES linear; ACES is on `writeTexture` only.
- Sampled UVs clamped.

## audio-reactive-rgb-dispersion
- Kept: scale / angle / falloff / original blend; centroid, energy, spread, balance; 5-tap smear; lateral vs transverse mix. No ACES.
- Ideas: `cauchyLambda` warps interior tap positions (§12.2F); endpoints still hit the existing red/blue offsets. Falloff mixes radius with contrast along `dir`. The blend anchor is the undisplaced UV, because the middle tap is no longer zero-offset.
- A packing: display RGBA passthrough.

## audio-reactive-pyramid
- Kept: bass / mid / treble gain and blend; DoG levels; silence floor; depth routing; warm/cool added detail. No ACES.
- Ideas: `gaussBlur` keeps `|horizontal − vertical|` luma and the fine gain drops on isotropic pixels; reconstructed RGB is clamped to `min/max(original, coarse blur)` plus a small blend radius (§12.2A).
- A packing: display RGBA. C is not read.

## audio-voronoi-displacement
- Kept: cell count, audio reactivity, displacement, color intensity; 3×3 nearest and second site; hash slide; mouse gravity and click pulse.
- Ideas: bulge along the vector to the nearest site, with a silence floor on the displacement slider; the `(dist2 − dist1)` wall darkens even when mids are quiet.
- Removed the fake `sin(time)` audio and the `extraBuffer[0..]` read. Bands are `plasmaBuffer[0].xyz`.
- A packing: ACES display RGBA. A was not written before. C is not read.

## moire-interference
- Kept: frequency / distortion / aberration / complexity; spring; `w1 + w2 + w3`; click emitters; per-emitter FFT gains.
- Ideas: `beat = |cos(½(d1−d2)·freq)|` scales the existing displacement and darkens the nulls.
- Sample UVs clamped. ACES on display.
- A packing: ACES display RGBA. C is not read.

## waveform-glitch
- Kept: wave / VHS / block-glitch / shadow-mask; aliasing; Lissajous; waveform trace; beam-dwell; block shift; phosphor trail.
- Ideas: R/B mix toward a sample further `+x` by the VHS slider (§12.2B); persistence rises with `lissPattern` and is clamped.
- A packing: pre-ACES linear display in A. ACES on `writeTexture` only.

## signal-modulation
- Kept: base frequency / distortion / scroll speed / color split; carrier; band mask; click rings; spring `[133..138]`.
- Ideas: carrier amplitude `* (1 + bandFFT)`; vertical ticks where `sin(phase)` is near zero and `uv.y` is near 0.5.
- Band energy reads `extraBuffer[5..12]`, not `plasmaBuffer[1..8]`. Duplicate `depth` binding removed so naga accepts the file. Removed from `wgsl_validation.json` knownFailures (ratchet 23 → 22).
- A packing: ACES display RGBA. C is not read.

## vertical-slice-wave
- Kept: strip count / speed / RGB split / jitter; layered sines; seam runner; click fronts; raw state in A.
- Ideas: strip edge blends toward the next strip's layered wave; `vel_new` adds a small Y offset.
- ACES on `writeTexture` only. A stays `(env, spring.xy, vel)`.

## wave-halftone
- Kept: dot size / density / wave amp; hex cell; elliptical stretch; 15° rosette; crest chromatic; ACES display.
- Ideas: radius `* (1 + 0.32·sqrt(L·(1−L)))`; `localDensity` rises with `|interference|`.
- `zoom_params.w` is named Wave Speed. `speedScale` is 1 at the saved default 0.2. Chromatic amount stays on that same slider.

## Formula use (no row on more than two files)
- §12.2D deep-water dispersion: sine-wave only
- §12.2F Cauchy: audio-reactive-rgb-dispersion only
- §12.2A anti-halo: audio-reactive-pyramid only
- §12.2B chroma delay: waveform-glitch only
- Beat envelope: moire-interference only (not the sonic harmonic product)
