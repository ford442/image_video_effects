# Post-Processing Seven — Idea Cards (written before any WGSL edit)

**Agent:** spark · **Date:** 2026-09-21 · **Contract:** `docs/SHADER_UPGRADE_BATCH.md` §0/§2/§7

Post-processing: 22 of 28 files with no `Ideas:` line. Two cohorts live here, and this batch takes
from both. §1: *post-process and photographic shaders need quieter ideas. A sharpen upgrade that a
photographer still uses as sharpen is success.*

**Photo tools (3):** pp-sharpen, pp-vignette, pp-chromatic
**Temporal / history-ring (4):** temporal-slit-scan, optical-flow-tracer,
temporal-frequency-decomposition, spatio-temporal-3d-conv

## Excluded after reading

| ID | Why |
|---|---|
| `radial-blur` | `Upgraded: 2026-08-23 (Batch 67)` — already done |
| `soft-vignette-bloom` | flare, starburst, hex bokeh DOF, anamorphic streaks — idea-dense already |
| `temporal-feedback-zoom-tracer` | a known naga failure (`__finalRGB` reserved prefix). Fixing it is a separate job |
| `temporal-rgb-ghost` | the only native idea I could find (sub-frame interpolation) is the one given to slit-scan. Two files cannot share it |
| `temporal-decay-multiresolution` | could not name two ideas that aren't already on another card here |
| `temporal-layered-time-stamps` | described as the binding-13 *infrastructure proof shader* — a reference, like liquid-v1 |
| `tone-histogram-apply`, multipass | shared packing contract across passes |

## Floor fix applied to all four temporal files (NOT counted as an idea)

**History-ring depth bug.** `docs/BINDING_CONTRACT.md`: the ring is *at most* 8 layers; after the VRAM
probe the runtime may allocate 8, 4 or 1. The renderer wraps its write head at the allocated count
(`src/renderer/webgpu/frame.ts:109`, `% historyLayers`). Every binding-13 shader in the catalog wraps
at a hardcoded `HISTORY_DEPTH = 8u`. On a 4-layer device `(head + 8 − age) % 8` asks for layers 4–7,
which do not exist; WGSL clamps the array index to layer 3, so frame ages come back scrambled, silently.
Fix: `histDepth = max(textureNumLayers(historyTexture), 1u)`, wrap by it, clamp every age to
`histDepth − 1`. On an 8-layer device this is bit-identical to HEAD.

All 11 binding-13 shaders have the bug. This batch fixes the 4 it touches. The other 7 are listed in
NOTES as a follow-up, not silently widened into this batch.

**Also stated, not changed:** the four temporal files do not run ACES, while their JSON carries
`upgraded-rgba`. They pass a display-referred source straight through; bolting ACES on would dim the
photo, which is the hygiene-as-upgrade trap. Left alone, flagged.

---

## 1. `pp-sharpen`

```
SHADER: pp-sharpen
IDENTITY: an unsharp-mask sharpen a photographer would use, with bilateral range weights and coring,
          three modes, and a pointer inspection lens.
KEEP VERBATIM: amount / radius / edge threshold / mode; the 8-tap bilateral blur (already the §7
          example idea); coring in mode 0; all three modes including mode 2 as HEAD shipped it;
          spring lens; ripple surge; C anti-jitter; A display packing.
ADD (2 quiet, native ideas):
  1. Anti-halo overshoot clamp — the tell-tale of bad sharpening is the bright/dark halo either side of
     an edge. Clamp the sharpened value to the 3×3 min/max envelope the kernel has already sampled,
     plus a small tolerance, so edges get crisper without ringing. Every pro sharpener does this.
  2. Luminance-only sharpening — sharpening RGB independently amplifies colour noise and fringes on
     saturated edges. Apply the detail as a luma delta (preserving the pixel's chroma), which is what
     "sharpen in Lab / luminosity blend" means to a photographer.
FORBID: anything new in mode 2's neon direction; springs; palettes.
A PACKING: HDR display RGB + semantic alpha in A; C read as colour. Unchanged.
```

## 2. `pp-vignette`

```
SHADER: pp-vignette
IDENTITY: a photographic vignette with film grain, a colour-grade blend, and two blend modes.
KEEP VERBATIM: intensity / grain / colour style / blend mode; sepia/warm/cool grade chain; both blend
          branches; triangular grain; spring aperture; ripple bloom; C anti-strobe; A packing.
ADD (2 quiet, native ideas):
  1. cos⁴ natural falloff — real lens vignetting follows the cos⁴θ law (inverse-square × obliquity ×
     pupil foreshortening), not a smoothstep. Blend the cos⁴ term into vigMask so the falloff has the
     shape a lens actually makes: gentle across the frame, accelerating only into the corners.
  2. Grain rides the emulsion — film grain is densest in the midtones and shadows and all but vanishes
     in the highlights, and it lives in the emulsion, i.e. under the vignette, not on top of it. Weight
     the grain by a midtone response curve and apply it before the vignette darkens the frame.
FORBID: more ripples, palettes, anything with a pointer.
A PACKING: HDR display RGB + semantic alpha in A. Unchanged.
```

## 3. `pp-chromatic`

```
SHADER: pp-chromatic
IDENTITY: lateral chromatic aberration — five Cauchy wavelengths displaced radially/axially/
          tangentially through a curved lens, with a vignette and a fringe history.
KEEP VERBATIM: chroma / curvature / vignette / mode; lensWarp; five-band Cauchy sampling and the
          RGB reconstruction weights; click lens; spectral caustic; history mix; A packing.
ADD (2 quiet, native ideas):
  1. Longitudinal (axial) CA — the file models LATERAL CA only (colour-dependent magnification). Real
     lenses also focus each wavelength at a different depth, so out-of-focus edges fringe magenta in
     front of the focal plane and green behind it. Use scene depth against a focal depth to blur R and B
     in opposite directions of defocus. The sign flip across the focal plane is the giveaway.
  2. Purple fringing on blown highlights — the most recognisable real-lens CA artifact: a violet halo
     wherever a clipped highlight meets a dark edge (sensor bloom + axial CA). Detect near-clipped
     luma in the neighbourhood and bleed a violet fringe onto the darker side.
FORBID: more caustic rings, springs, palettes.
A PACKING: tone-mapped display RGBA in A/C. Unchanged.
```

## 4. `temporal-slit-scan`

```
SHADER: temporal-slit-scan
IDENTITY: a slit-scan camera — time laid out along one spatial axis from the history ring, with a
          pointer pivot, click tears, and per-column spectral jitter.
KEEP VERBATIM: vertical / spread / reverse / orig-blend; tent-map pivot; click tears; spectral jitter;
          alpha formula; A packing.
ADD (2 native ideas):
  1. Sub-frame layer interpolation — offsetF is rounded to an integer frame, so the "continuous" time
     ramp is actually eight hard bands with visible seams. Blend floor/ceil layers by the fractional
     age so time flows smoothly across the image.
  2. Slit exposure integration — a real slit-scan camera integrates light while the slit is open, so
     each column is a short average over time, not one instantaneous frame. Box-integrate the ages
     around the target, width set by spread, so moving things smear along time the way they do on
     film. (Idea 1 removes seams *across* columns; idea 2 adds exposure *within* one.)
FORBID: ghosts, glows, palettes.
A PACKING: display RGBA in A. Unchanged.
```

## 5. `optical-flow-tracer`

```
SHADER: optical-flow-tracer
IDENTITY: Lucas–Kanade optical flow against the previous frame, used to warp a decaying trail of
          history frames along the motion.
KEEP VERBATIM: decay / flow scale / max age / blend; the 5×5 LK normal equations and solve; the
          warped-history accumulation; raw flow packing in A.
ADD (2 native ideas):
  1. Shi–Tomasi confidence — LK is only trustworthy where the structure tensor has two strong
     eigenvalues; in flat regions and along straight edges (the aperture problem) it returns noise.
     Return λmin from the same sums and damp the flow where it is small. The trails stop sprouting from
     flat sky and clean walls.
  2. Pyramidal (coarse-to-fine) LK — single-level LK only sees motion of a pixel or two. Solve once on a
     coarse 4-px stride, then run the existing fine solve with the previous frame pre-warped by that
     coarse flow. Fast motion finally registers, which is the whole point of a flow tracer.
FORBID: palettes, springs, flow colour-wheel overlays.
A PACKING: raw — (flow.xy · scale, motion magnitude, 1). Unchanged.
```

## 6. `temporal-frequency-decomposition`

```
SHADER: temporal-frequency-decomposition
IDENTITY: a per-pixel DFT over the history ring — pixels that flicker at the chosen frequency glow in a
          chosen hue, with a sprung analysis lens and click tuning-fork pings.
KEEP VERBATIM: frequency / glow brightness / glow hue / base blend; the real/imag accumulation; lens;
          pings; band voices; alpha; A packing.
ADD (2 native ideas):
  1. Hann window — an unwindowed 8-sample DFT leaks badly: a pixel changing at any rate lights up at
     every frequency, so the "frequency selector" barely selects. Weight the samples by a Hann window
     and renormalise. Selectivity is the effect.
  2. Phase → hue — the file computes phase and throws it away. Rotate the glow hue around the
     user's hue by the DFT phase, so regions oscillating in sync share a colour and a travelling wave
     shows up as a hue sweep. The base hue slider still sets the palette centre.
FORBID: new springs (it has one), more pings, palettes beyond the existing hue2rgb.
A PACKING: display RGBA in A. Unchanged.
```

## 7. `spatio-temporal-3d-conv`

```
SHADER: spatio-temporal-3d-conv
IDENTITY: a 3-D (x, y, t) convolution over the history ring with three modes — temporal noise
          reduction, motion blur, temporal sharpening.
KEEP VERBATIM: spatial sigma / temporal depth / mode / strength; gaussWeight and both 3×3 helpers;
          per-mode temporal weights; per-mode composites; A packing.
ADD (2 native ideas):
  1. Motion-adaptive temporal weights — the defining failure of temporal NR is ghosting: anything that
     moved gets averaged with where it used to be. Multiply each frame's temporal weight by its
     photometric similarity to the current frame (a bilateral in time), so static detail averages and
     moving objects stay sharp. Applied in NR mode only; motion-blur mode keeps its ghosts, because
     there they ARE the effect.
     > CORRECTION (made during implementation, before gating): this card originally said "NR and
     > sharpen modes". Sharpen mode boosts `current − temporalMean`, i.e. it EMPHASISES motion;
     > rejecting moved frames would drive that residual to zero on exactly the moving regions it
     > exists to show. So NR only.
  2. Variance-driven NR strength — a real video denoiser estimates the noise before removing it.
     Measure per-pixel temporal variance across the frames already fetched (weighted by idea 1's
     similarity, so motion is not mistaken for noise) and scale NR strength by it, so the temporal
     averaging works hardest where there is actually noise to remove.
FORBID: anything shared with pp-sharpen (no min/max envelope clamp here), palettes, springs.
A PACKING: display RGBA in A. Unchanged.
```

---

## Shared discipline

- 14 ideas, 7 files, none reused. Checked for near-duplicates explicitly: optical-flow originally had a
  photometric occlusion check, dropped because it is the same mechanism as 3d-conv idea 1; pp-sharpen's
  min/max clamp is forbidden on 3d-conv for the same reason.
- No springs, ripple loops or palettes added. The ring-depth fix is floor, stated as floor.
- Saved `params` byte-exact.
