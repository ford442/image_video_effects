# Notes — glass-flora ten (2026-11-15)

Per shader: what stayed, the packing, and where each idea sits in the diff. Cloud VM has no GPU. These notes are structural. They are not visual QA.

## hybrid-voronoi-glass

- Kept: F1/F2 loop, Cauchy at 0.700/0.546/0.436 µm, Snell, Schlick, TIR, Beer absorption, pointer pressure, ripple fracture, exact-C smear. Params unchanged.
- Idea 1 in the facet-tilt line: tilt is `mix(0.22, 1.0, boundary)`.
- Idea 2 after the history add: `caustic` from `stableBoundaryDistance`, body darkened with `mix(0.82, 1.0, caustic)`, ridge lit from the transmitted sample.
- A packing: ACES display RGBA, same as before.
- Formula: neither idea is a new §12.2 row. Fresnel and Cauchy were already in the file.

## gen-harmonic-ferrofluid-kinetics

- Kept: domain warp, 3D Voronoi, inverse smoothstep, held-only mound, Blinn spec, view iridescence, subsurface, fog. Params unchanged. No audio (the definition does not claim it).
- Idea 1 in `map`: `pow(spikeField, 1.75)`.
- Idea 2 in the hit shade: `crest` from `p.y` and `n.y`, scaled by Glossiness.
- Idea 3: `aoTap` at 0.08 / 0.22 / 0.5 replaces the old single `map(p + n * 0.5)`.
- A packing: ACES display RGBA. This file wrote no A before. C is not read.
- Formula: three-tap step-count AO (§12.2E). Only file in the batch.

## bio-touch

- Kept: influence disk, Voronoi, color-shift tints, distance pulse, held curl, click fronts, three-band audio, existing spectral mix. Params unchanged.
- Prelude migration is infrastructure.
- Idea 1: `body`, `nucleus`, `cellWall` from `v`, summed into the existing `glow`.
- Idea 2: `prevGlow` from exact `C.a`, decay from Pulse Speed, `after = max(finalGlow, prevGlow * decay)`. `writeTexture` alpha is coverage. `dataTextureA.a` is `storedGlow`.
- A packing: ACES display RGB, raw glow in A.a. Do not tone-map A.a.
- Floor: ACES on the display. The May header had `upgraded-rgba` and no ACES.

## gen-liquid-metal-chrono-flora

- Kept: smin of the six-fold torus and the core sphere, time wave, bass/mid, crevice energy, spec. The mouse pull is the same math, now `floraPull`, so the vein uses the same space as the SDF. Params unchanged.
- Idea 1: Schlick on the existing chrome, `metallicShine` sets `f0`.
- Idea 2: `pow(1 - abs(sin(petalA * 6)), 10)` along the existing fold, gated by Fresnel.
- A packing: ACES display RGBA. The previous `dataTextureA` store was zeros and C is not read.
- Formula: Fresnel–Schlick (§12.2F). One of two files (the other is `quantum-prism`).

## mouse-kaleidoscope-tunnel

- Kept: log-z `depthLayer`, kaleidoscope segments, spiral, wavelength split, three-layer sample, ring glow, click UV kicks. Params unchanged.
- Prelude migration is infrastructure.
- Idea 1 after the fog: `axisCos ^ 4`, adjacent side is Tunnel Depth.
- Idea 2 after ACES: exact C, three pixels along `-centered`, mix `0.04 + 0.10 * Tunnel Speed`.
- A packing: ACES display RGBA, unchanged.
- Formula: cos⁴ (§12.2A), only file in the batch. The flight streak is this tunnel's own history read, not the psychedelic fold smear.

## gen-aetherial-chromatic-tesseract

- Kept: four abs-and-rotate folds (now `foldPoint`, same loop), box SDF, bass scale, march glow, diffuse and spec. Params unchanged.
- Gravity Strength used `(mouse_uv - 0.5 * resolution) / resolution.y` with a 0–1 pointer, so the well was numerically dead. The warp direction is unchanged; the pointer is converted into the ray's centered uv. That is a restoration, not an idea.
- Idea 1: `folded.w / 4` mixes spec power 32→12 and a cool tint.
- Idea 2: `thinFilm` replaces the cosine. Iridescence Shift is thickness. A slow sine keeps it moving.
- Idea 3: `boxEdge` where two axes of `q` are near zero.
- A packing: ACES display RGBA. This file wrote no A before. C is not read. Gamma `pow` replaced by ACES (floor).
- Formula: fold-count material (§12.2E), thin-film (§12.2F), box-edge form of SDF curvature (§12.2E). Only file for each.

## quantum-prism

- Kept: hex pick, rotation, zoom, grout, bevel, spectral bands, oil-slick runners and packets, click fronts, history mix. Params unchanged.
- Prelude migration is infrastructure.
- Idea 1: `cauchyRatio` scales the existing RGB wheel. Green stays 1. Red and blue follow `n(λ)/n(green)`.
- Idea 2: `fres` from `hexDistance`, transmission reduced, cool rim added, grout excluded.
- A packing: display RGBA, exact C still the previous display.
- Floor: ACES on the display write. The tag was already `upgraded-rgba` and the shader had no ACES.
- Formula: Cauchy (§12.2F), only new use in the batch. Fresnel–Schlick (§12.2F), second file beside the flora.

## gen-psychedelic-time-warp-kaleidoscope

- Kept: mirror fold, curl offset, bass mirror count, exact-C smear along the fold, three-band glow, `applyGenerativePrimaryControls` (x intensity, y speed, z detail, w mouse). No `params` array in the definition; none added.
- Prelude migration is infrastructure.
- Idea 1: second sine on `angle`, `+ time`, 0.42 of `wobble`.
- Idea 2: `seam` from `fromMirror` before the intensity multiply, then `color *= (1 - seam * 0.62)`.
- A packing: ACES display RGBA, unchanged.
- Formula: neither idea is a §12.2 row. No bore falloff, no wavelength split.

## rain-lens-wipe

- Kept: stable drop cells, advected mask in A.r, decay, mouse wipe, click rings, meniscus, beads, streak motion. Params unchanged.
- Prelude migration is infrastructure.
- Idea 1 in `rainDistortion`: `lens = drop * (0.55 + 0.9 * drop)` replaces `return offset * drop`.
- Idea 2: `phaseDelta` head `* 22` and tail `* 5.5`, replacing `pow` of a signed ratio.
- A packing: wipe mask in A.r. Meniscus and bead still in A.g and A.b. ACES on the display write only. A.r was not touched.
- Formula: neither idea is a §12.2 row.

## gen-audio-reactive-quantum-pollen

- Kept: 3×3 gather, bass/treble envelopes, log-spiral, orbit, treble burst, mouse attract, fbm haze, ACES, dither, premultiply. Params unchanged.
- Idea 1: rest position is `(cid + 0.5) / cells + restDir * radius`, `theta = (cid.x + cid.y * 14) * 2.39996323`. The log-spiral variable stays named `arm`.
- Idea 2: `lobes` on the existing gaussian radius, 5–7 spines from `rnd.y`.
- A packing: raw `(bassEnv, trebEnv, dens, alpha)`. Display write is still premultiplied ACES. A was not retargeted.
- Formula: golden-angle layout (§12.2E). Only file in the batch.

## Floor

Bindings via `#include "_prelude.wgsl"` (five files migrated, five already included). Workgroup 16×16. Exact `textureLoad` of C where C is read. Saved `params` not renamed or re-defaulted. `x-meta.upgrade.params` added for the ferrofluid, the tesseract, and the pollen, matching the saved params. No new springs. No new `extraBuffer` writes.
