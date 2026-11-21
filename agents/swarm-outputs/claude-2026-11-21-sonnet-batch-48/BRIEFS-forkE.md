# BRIEFS — fork E (sonnet/batch-48): hyb-kaleidoscope-pulse, rgb-topology

Written BEFORE any WGSL edit. Baselines snapshotted to the scratchpad (`…/scratchpad/e/<id>_head.wgsl`). HEAD renders (512², SwiftShader, `SRC=img`) read; NaN 0 on both.

---------------------------------------------------------------------------
## 1. hyb-kaleidoscope-pulse  (first pass — no `Upgraded:`/`Ideas:` at HEAD)

```
SHADER: hyb-kaleidoscope-pulse
IDENTITY (one sentence): the input image mirrored into FBM-domain-warped kaleidoscope wedges
  (+ a counter-rotating inner ring) with an ACES-tonemapped radial pulse / SDF star / strange-
  attractor tint and a radial chromatic split; alpha = pulse energy + depth.
KEEP VERBATIM: 4 params + roles (segments → wedge count, pulse_speed, pulse_width,
  effect_mix → pulse/warp/alpha blend); fbmWarp two-layer warp; kaleido() fold + kPhase drift;
  inner ring (centered*1.7, segments*2, −phase, 0.25*effectMix blend); rdPulse + sdfStar + smin +
  attractorOrbit pulse composite and its colour mix; ACES; radial chromatic split; semantic alpha
  (luma/pulse/depth); IGN dither; depth pass-through; no audio, no pointer (HEAD has neither).
RESCUE (HEAD defect, changes default look — flagged loudly):
  R1. `segments = mix(3,16,x)` is fractional (default 9.5). `kaleido()`/`sdfStar()` wrap at
      atan2 = ±π where 2π is not a multiple of the wedge angle, so a visible angular seam /
      discontinuity sits on the left axis (seen in the HEAD render at y≈0.5, x<0.5). Snap to
      the nearest integer count (`floor(x+0.5)`): every integer wedge count is seamless
      (|a mod seg − seg/2| is continuous across the wrap). Default 9.5 → 10.
ADD (2 native ideas):
  1. Mirror-bounce material — §12.2E "fold count as material". `kaleido()` already computes the
     wedge angle; also return the wedge index → reflection depth k = min(n, N−n) (a mirror-tube
     kaleidoscope sees wedge n after n reflections around the shorter way). Each reflection off
     real silvering loses a little energy and drifts warm: outRGB *= tint^k (per-channel,
     tint ≈ (0.96,0.94,0.90), strength rides the existing effect_mix so mix=0 is HEAD).
     Plus the mirror-edge hairline: angular distance to the fold line × r = true distance to the
     mirror; a thin dark groove where two mirrors meet. Both consume `a`/`seg` that kaleido()
     already holds.
  2. Object-cell twist — §12.2E "additive domain twist". After the fold, rotate the folded
     sample point by θ = twistGain·r²·sin(ωt) (ω from the existing pulse_speed, gain from
     effect_mix) before the texture lookup. Rotating the *already folded* point keeps exact
     mirror symmetry (mirror-related pixels share the folded point ⇒ same sample), so the mirrors
     stay straight and it still reads as a kaleidoscope whose object cell slowly swirls. Centre
     stays crisp; periphery twists.
FORBID on this file: springs/ripples/pointer (never pointer-led), IQ palette, new params, audio
  (HEAD claims none), thin-film, replacing the fbm warp or the pulse composite, changing any ACES
  / dither / alpha constant.
A PACKING: none — HEAD never writes dataTextureA / B and never reads C; unchanged (display RGBA
  in writeTexture, depth pass-through).
```

### §12.1 mechanism interrogation
- **Tactic 1 (deepen the kernel):** the kernel is the wedge fold `abs(a mod seg − seg/2)`. Same operator one step further: return *which* wedge as well (fold depth) and the distance to the fold line (mirror edge) — both fall out of the same two lines.
- **Tactic 2 (physics one step further):** a real mirror tube loses energy and warms per reflection (silvering ρ<1, slight spectral slope) and shows a hairline where the two mirrors meet. Idea 1.
- **Tactic 3 (promote an intermediate):** `a` (folded angle), `seg`, and the pre-wrap angle are computed and thrown away → fold depth + seam distance. `sampleUV` computed once is reused by the chromatic split, so the twist applied to it also moves the CA taps (consistent).
- **Tactic 6 (history):** HEAD owns no history (C unread). Not applicable; none added.

### §12.4 formula admission
| row | family match | operates on what exists | deletion test |
|---|---|---|---|
| fold count as material (§12.2E) | kaleidoscopic fold = KIFS-family fold | consumes `a`, `seg` from kaleido() | delete → HEAD; keep only it → not a kaleidoscope (it only multiplies a colour) ✓ additive |
| additive domain twist (§12.2E) | same | rotates the already-folded `kUV` before the existing lookup | delete → HEAD; keep only it → a twisted image, no mirrors ✓ additive |
Two rows only; both claimed by this fork (orbit trap / golden-angle unused — HEAD's `attractorOrbit` is already the trap).

---------------------------------------------------------------------------
## 2. rgb-topology  (creative first pass — `Upgraded: 2026-08-21` hygiene, no `Ideas:` at HEAD)

```
SHADER: rgb-topology
IDENTITY (one sentence): the photo read as three height fields (R/G/B + depth + a mouse tilt
  ramp) and drawn as a topographic map — per-channel iso-lines on golden-ratio intervals, index
  lines, hachures, ridge ticks, travelling runners, hypsometric tints, click fronts, held shear.
KEEP VERBATIM: 4 params + roles (contour_density, line_thickness, channel_separation,
  source_blend); topoR/G/B formulation (src·0.8+depth·0.2)·elevExag + the three rotUV ramps;
  intervals (1, φ, 1+√2); main lines / hachure / index / ridge ticks / runners / helix; hypsoTint;
  bounded click fronts; per-channel tilt sampling; spec; crossMix; ACES; semantic alpha; depth
  relief write; pointer use (centre, rotation, held) and audio use (bass/mids/treble from
  plasmaBuffer[0].xyz) exactly as HEAD.
ADD (3 native ideas — all read the height field the file already builds):
  1. Hillshade from the field's own gradient. Forward differences of the already-sampled
     R/G/B/depth give ∇h (2 extra src taps + 2 depth taps; the duplicate sampG tap = src.g is
     removed). Lambert n·L with the sun swinging with the SAME rotAngle the terrain tilt already
     uses (pointer-owned, not a new overlay). Lines on lit slopes glow, shadow slopes recede; the
     photo that `source_blend` lets through is relief-lit. Source Blend still means "how much
     photo", Contour Density etc. untouched.
  2. Supplementary (half-interval) dashed contours in gentle terrain. Cartographers add dashed
     intermediate contours where main contours are far apart (low slope): |cos(x)| zero set (x is
     the same phase the main lines use, so they sit exactly between them), dash coordinate
     = distance along the contour tangent (perp of the field gradient, ramp included),
     visibility = 1 − smoothstep(|∇h|) so steep ground stays clean. Per channel, hypso-tinted
     like the main lines. Not stored in A (A stays [lineR,lineG,lineB,alpha]).
  3. Elevation-proportional parallax (relief displacement). The R/B channel tilt now scales with
     the mean elevation (0.55+0.9·h): high ground leans further from the pointer-centre than low
     ground — what stereo disparity / aerial relief displacement does. Channel Separation keeps
     its role and amplitude (≈1× at mid-elevation).
FORBID on this file: SDF/raymarch costume, IQ palette (hypsoTint stays as is), new springs or
  ripple fronts (clickFront stays as HEAD), changing line/hachure/index maths, any new param,
  moving the mask out of A (A stays line masks mixed with prev·0.82), neon edge pop.
A PACKING: unchanged — dataTextureA = [lineR, lineG, lineB, alpha] (line masks, not display
  colour; JSON already documents it). C is read as that mask (exact textureLoad) only for the
  0.18·prev persistence; unchanged.
```

### §12.1 mechanism interrogation
- **Tactic 1 (deepen the kernel):** the contour kernel is `|sin(x)|` with thickness in elevation units. Next-better *same* operator: add the half-interval zero set (|cos x|) as a second, subordinate contour set — what cartographic "supplementary contours" are.
- **Tactic 2 (physics one step further):** a topographic map's two companions are relief shading and (for stereo/aerial source) relief displacement. Both derive from the height field: ideas 1 and 3.
- **Tactic 3 (promote an intermediate):** `topoR/G/B`, `depth`, `src`, `rotAngle`, `rotUV`, `peakMask` exist; the *gradient* of h is the one quantity the shader never forms (`peakMask·spec` uses a fake `specDir` from rotUV only). Forming ∇h pays for hillshade (1) and the flatness mask / contour tangent (2).
- **Tactic 6 (history):** `prev` (C) is read and persisted into A's mask but never reaches the picture. Noted; not used as an idea (kept to ≤3 and no extra state). A-mask semantics untouched.

### §12.4 formula admission
| row | family match | operates on what exists | deletion test |
|---|---|---|---|
| hillshade from the height field's gradient (field-native; not a §12.2 row) | contour/topographic family — the map's own companion | topo values + depth + rotAngle already computed | delete → HEAD; keep only it → no contours ⇒ not this effect ✓ |
| supplementary contours (cartographic extension of the existing `\|sin\|` contour kernel; gradient-gated) | contour kernel | same phase `x` as the main lines | delete → HEAD; keep only it → no main lines ✓ |
| relief displacement / elevation-scaled parallax | existing per-channel tilt | topo mean elevation | delete → HEAD; keep only it → no contours ✓ |
None uses a row claimed by another fork (no structure tensor / Cauchy / chroma-delay / orbit trap).

---------------------------------------------------------------------------
## Cross-file de-dup (fork E)
hyb-kaleidoscope-pulse uses §12.2E fold-count + additive-twist; rgb-topology uses field-native hillshade / supplementary contours / relief displacement — no shared formula row.
