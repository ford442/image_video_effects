# BRIEFS — fork C (multi-fractal-compositor, volumetric-rainbow-clouds)

Written BEFORE any WGSL edit. HEAD = worktree file at start (copies in the fork scratch dir `.../scratchpad/c2/*_head.wgsl`).

**Correction to COMMON.md.** `multi-fractal-compositor` is NOT the clouds' pass-2 partner. `volumetric-rainbow-clouds` says `Next Pass: prismatic-3d-compositor.wgsl` and `prismatic-3d-compositor` is `PASS 2 of 2` (that is the batch-51 finding COMMON conflated). The multi-fractal-compositor is a stand-alone layered zoom tunnel of the *input photo* (its own header says so). The two files share nothing; no cross-file coupling to preserve. Clouds' outputs (RGBA display colour, depth.x = depth, depth.y = optical depth, depth.w = alpha) stay as they are because prismatic-3d-compositor reads them.

## Checklist results on HEAD (COMMON "failure checklist")

| # | multi-fractal-compositor | volumetric-rainbow-clouds |
|---|---|---|
| 1 ACES | present, on display RGB, clamped input | present, input clamped `max(fogged,0)` |
| 2 audio | `plasmaBuffer[0].x` → chroma (already rescued 2026-11-01); `extraBuffer[10]` (FFT bin 5, read-only, legal) → vortex, misnamed `clickIntensity` | none claimed (features carry no `audio-reactive`) |
| 3 C/A | writes no A, reads no C — consistent | same |
| 4 extraBuffer writes | none | none |
| 5 other | `mousePos` and `baseColor` are computed and unused (dead, harmless, left); alpha = `calculateVolumetricAlpha` (semantic) | **`viewDir = normalize(-viewPos)` with `viewPos.z = 0` → view vector has no z → `specular` is exactly 0 everywhere** (verified, see below); `normalize(0)` at the exact centre pixel when cameraZ=0 |

**Verified HEAD defect (clouds, rescue R1):** rendered HEAD at Light Intensity 4, mouse (0.2,0.3), 256², 20 frames, t=2: replacing `specular` with `0.0` gives a **bit-identical picture (0.0 % px changed, mean abs 0.0)** — the specular term is dead, so the saved "Light Intensity" slider only reaches the HG/corona terms. With `viewDir = normalize(vec3(-viewPos.xy, 1.0))` (the camera sits in front of the slab; HG's `cosT = lightDir.z` already assumes a +z view) **11.4 % of px change (mean abs 0.75/255)**: glints are alive, subtle. It also removes the undefined `normalize(vec3(0))` at the centre pixel of even-sized frames. Default picture changes by that glint only.

**Not changed, flagged for the user (clouds):** `cameraZ = u.zoom_config.w` is the mouse-down flag (0/1), so a click instantly doubles the perspective divisor (a pop, no easing — easing needs state). Density is `abs(fbm)` (ridged), which is where the black marble veins come from; swapping it for billow coverage would change the whole picture, so it is left.

## Idea Cards

```
SHADER: multi-fractal-compositor
IDENTITY (one sentence): five staggered octave layers of the input photo zooming about the cursor, composited with R/B zoom-lens dispersion, a bass chroma split, depth edge glow and fog.
KEEP VERBATIM: the five staggered exp2 layers, sin^2 birth/death windows, the zoom dispersion taps (x0.982/x1.018), flow-noise warp scaled by Domain Warp, the FFT vortex, bass chroma split, edge glow, fog (Fractal Blend = fog density), alpha, depth out, all four param roles (Zoom Level / Iteration Count = layer speed endpoints), the existing Ideas line.
ADD (2):
  3. Droste spiral twist — each layer is rotated about the zoom centre by 0.30 rad per octave of its own zoom (angle = k·log2 zoom). A zoom plus a constant rotation per scale factor is the log-polar self-similarity of the Escher/Droste spiral; HEAD's layers are pure radial scalings, so the "self-similar zoom" never actually spiralled. Folded into the existing `spinAngle` (no new trig, no new taps).
  4. Expanding annulus windows — layer i's colour weight in the composite is a ring that grows outward with its zoom phase (radius 0.06→0.90, soft width 0.22, floor 0.35). HEAD blends the five octaves as five full-frame cross-fades; a zoom tunnel's octaves occupy nested rings. The *strength* of the composite is untouched (presence still comes from the temporal windows), only how the five layers are distributed across the frame.
FORBID on this file: springs/ripples/IQ palettes, a Mandelbrot/Julia re-implementation (the header already says it is not one), new params, orbit-trap/smooth-iteration rows (there is no iteration to trap).
A PACKING: none (writes no A, reads no C); ACES display on writeTexture, alpha and depth as HEAD.
```

§12.1 answers: *Tactic 1 (deepen the kernel)* — zoom → zoom+rotation (the next-better approximation of a Droste operator). *Tactic 2 (physics one step further)* — a real nested/feedback tunnel's copies sit at nested radii and each copy is rotated by the loop's roll: ring distribution + per-generation rotation. *Tactic 3 (promote an intermediate)* — `layerPhase` already exists per layer and is only used for zoom and window; it now also sets the ring radius and the twist. *Tactic 6* — no history owned. §12.4: neither idea is a §12.2 row (domain-native). Deletion test ✓ (without them: HEAD's tunnel exactly); keep-only-the-idea test ✓ (a twist/ring alone is not the effect — no photo layers). Same-noun ✓ (Droste, tunnel). Rejected: radial zoom-blur (the R/G/B taps at 0.982/1/1.018 already are a 3-tap radial zoom blur), per-generation tint (reads as a colour overlay), cursor-lag anchor (needs state).

```
SHADER: volumetric-rainbow-clouds
IDENTITY (one sentence): 3-slab fbm cloud volume lit from the cursor, hue taken from the surface-normal angle, with Beer-Lambert alpha — pass 1 of the prismatic cloud pair.
KEEP VERBATIM: vnoise3d/fbm3d (6 octaves, abs(noise) density), three layers, Beer-Lambert opacity/alpha, rainbow-by-normal hue, light-march self-shadow, HG silver lining, scattering-angle corona, fog + ACES, outputs (RGBA + depth packing read by prismatic-3d-compositor), the saved params (Scale, Flow Speed, Density, Light Intensity) and their roles, the existing Ideas line, the mouse-down perspective pull.
RESCUE R1: view vector has a +z component (see above); specular term alive.
ADD (2):
  5. Wind shear — each of the three slabs is advected horizontally at its own speed and heading (0.06 / 0.14 / 0.26 noise-units/s × Flow Speed, headings sheared 0.35 rad per layer). HEAD's only motion is a z-boil through the noise, so the three slabs never slide past each other; real cloud decks shear with altitude. Zero extra taps; the shadow march and normal taps use the same advected position so lighting stays consistent. At t=0 the picture is HEAD's.
  6. In-cloud lightning — bass over a gate (smoothstep 0.25→0.6 on plasmaBuffer[0].x) fires a flash cell at a position hashed from floor(t·2.5), decaying exp(-7·phase); it lights only where there is cloud (weighted by each layer's own opacity 1-layerTransmittance), cold white tinted 40 % by that layer's rainbow hue. No bass → no change. Makes the JSON `audio-reactive` tag true (HEAD had none).
FORBID on this file: Beer-Lambert/HG extensions (powder, multiple-scatter octaves, god-rays march — shipped rows, ownership rule), springs/ripples, an audio pump on global density or lightIntensity, IQ palettes, a billow/coverage re-map of the density (changes the whole picture).
A PACKING: none (RGBA to writeTexture, depth out); ACES on display colour; lightning added pre-ACES.
```

§12.1 answers: *Tactic 2* — cloud decks shear (wind) and cumulonimbus flash internally. *Tactic 4 (second-order parameter)* — Flow Speed is one scalar for the whole volume → a per-layer velocity vector with the same slider as gain. *Tactic 3* — `layerOpticalDepth/layerTransmittance` are already computed per slab; the flash is weighted by them. §12.4: neither is a §12.2 row; Beer-Lambert/HG untouched. Cost: wind free; lightning 2 hashes + 1 exp per pixel (+3 per-layer mults); target ≤ 1.05×.
