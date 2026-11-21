# BRIEFS — fork C (sonnet/batch-48): scanline-cyberpunk, spectrum-bleed

Written BEFORE any WGSL edit. Baselines snapshotted to the scratch dir (`.../scratchpad/c/<id>_head.wgsl` + `_prelude.wgsl` + `_std/`).
HEAD renders looked at (384², SRC=img, defaults, mouse 0.7,0.4, audio 0.4/0.3/0.3): both compile, NaN 0, not blank.

---

## 1. scanline-cyberpunk  (first pass)

```
SHADER: scanline-cyberpunk
IDENTITY (one sentence): a CRT monitor showing the photo — alternating scanline rows, RGB phosphor triads,
  a racing head-roll bar that shears the lines sideways, a diagonal phosphor runner, a teal neon lift and a
  teal/orange cyberpunk grade.
KEEP VERBATIM:
  params  zoom_params.x scanline_intensity (row dim 0..0.7) / .y phosphor_mask (triad dim + runner gain) /
          .z glitch_amount (0..0.04, ×(1+2·bass), ×1.35 held) / .w color_grade
  - the Fp128 pair arithmetic and the glitchOffset = fp128_sum(...) accumulator (new terms are added INTO it)
  - 20 glitch bands (floor(uv.y·20), hash carrier sin(t·(8+5·bass)+seed·2π))
  - headRoll = pow(max(0, sin(uv.y·68 − t·15)), 15)
  - mouseField / held amplifier, capped click fronts (ripple.z start time), C history mix (prev·0.9 at headRoll·0.15)
  - gid.y%2 scanline mask, gid.x%3 triad mask, phosphor_runner(), treble flicker, neon overlay, colorGrade, ACES
  - A = display RGBA (== writeTexture), B = (bass, mid, treble, glitchOffset) (HEAD already owns B), depth pass-through
MECHANISM INTERROGATION (§12.1):
  tactic 1 deepen the kernel — the shear is a per-band sinusoid plus a bar. On a real CRT/tape the horizontal
    displacement is the line-start PLL (AFC) answering a sync fault: yank at the fault, then exponential relaxation.
  tactic 2 physics one step further — a head-switch disturbance does not only draw a bar; the lines *after* it are
    still dragged sideways and recover over several lines (the "hook"/flag at the bottom of a VHS picture). The same
    machines drop RF envelope for a few % of a line: dropouts.
  tactic 3 promote an intermediate — headRoll's argument `uv.y·68 − t·15` is computed then thrown away after pow().
    Its fractional phase IS the distance (in lines) behind the bar → free decay coordinate for the hook, and its
    floor() is a per-bar label → free per-bar sign/amplitude.
  tactic 6 history — C is read as colour (display RGBA). Nothing new needed; dropouts are instantaneous signal loss.
ADD (2 native ideas):
  1. Sync-edge line hook — §12.2B "Sync-pulse timing": each head-roll bar yanks the lines just below it sideways by
     ±(0.9·glitchAmt) (sign/amplitude hashed per bar label), relaxing as exp(−4.5·linesBehindBar). Added as a third
     term inside the existing fp128 offset sum. Native: it is what the existing roll bar *does* to the picture.
  2. Dropout bursts — §12.2B "Dropout bursts": per scanline pair, per ~110 ms window, with probability driven by the
     existing glitch slider (+ pointer field, bass), a horizontal streak starts at a random x and decays
     exp(−22·dx) to the right; polarity white-flare or black-out. Applied to the signal BEFORE scanline/triad masks so
     the CRT mask still modulates it. Native: tape/broadcast dropouts accompany head-switching.
FORMULA ADMISSION: both rows are in the §12.2B distortion/glitch table (this shader *is* CRT + head-switch glitch);
  both consume quantities the file already has (headRoll phase, glitchAmt, mouseField, bass, uv.x, the scanline row
  index); deletion test: remove either → exactly HEAD; remove the CRT mask/roll bar and keep only the idea → not
  recognisable as this effect (it is a tear / a streak, not a scanline monitor) → additive, not replacing.
  Rows used here: sync-pulse timing + dropout bursts (2 of the ≤2 allowed). NOT used: field interlace, Schmitt lock
  (Schmitt would need a latch in C.a, which is semantic alpha here → packing lie; interlace would strobe the HEAD mask).
FORBID on this file: springs, new click overlays, IQ palettes, neon edge pop, a second unrelated tear system,
  frame-hash strobing (dropout windows are 9 Hz and per-line staggered, not per-frame), any new param, any change to
  the mask / triad / grade constants.
A PACKING: display RGBA (unchanged, == writeTexture); B unchanged (bass, mid, treble, glitchOffset — glitchOffset now
  includes the hook, which is what it already documented: the horizontal offset applied).
RESCUE (HEAD defect): `uv = gid/dims` samples the source at the texel CORNER → the bilinear sampler returns a 2×2
  box average of the photo and shifts it half a pixel up-left (HEAD softens the picture before any effect). Fix:
  `(gid + 0.5)/dims`. Changes the default look slightly (sharper photo) — flagged loudly in the report.
```

---

## 2. spectrum-bleed  (second pass)

```
SHADER: spectrum-bleed
IDENTITY (one sentence): ink-on-paper colour bleeding — the photo's colours spill outward by wavelength (red tight,
  blue wide), hue-drift, persist through C into a travelling chromatographic front with a darker dry-edge rim,
  pointer lens and click ink splatters.
EXISTING Ideas (KEEP VERBATIM): wavelength-ordered bleed distance (R 0.55 / G 1.0 / B 1.7 radii); chromatographic
  advance front (history weight gated by saturation gradient); dry-edge rim.
KEEP VERBATIM: params x intensity (blend 0..0.6 + persistence base) / y speed (hue drift) / z scale (blur radius 1..4)
  / w detail (saturation boost); spectralBleed() channel ordering; hsv hue rotation; lens + click ink; FFT voice;
  advance/frontGate/persistence/dryRim math; ACES; semantic alpha; A = ACES display RGBA (== writeTexture).
MECHANISM INTERROGATION (§12.1):
  tactic 1 deepen the kernel — the bleed is a symmetric 4-diagonal-tap blur per channel; a real chroma bleed (tape,
    NTSC, wet ink on a wick) is asymmetric: chroma is low-passed AND late relative to luma.
  tactic 2 physics one step further — a coloured fringe on a real device trails the edge in the scan/travel direction
    while the luminance edge stays crisp (YC bandwidth mismatch). On paper, ink wicks along the open fibres, so the
    bleed distance is not isotropic or uniform across the sheet.
  tactic 3 promote an intermediate — `blurRadius` (scale slider) is already a per-frame scalar; making it spatially
    varying (fibre) and deriving the chroma delay from it costs no new slider.
  tactic 6 history — C is read as colour through an advected coord. No new continuity needed; the fibre only
    modulates the weight already applied to C.
ADD (2 native ideas):
  4. Chroma delay line (4:2:0 style) — §12.2B: sample the wavelength-ordered bleed at uv − (δ,0), δ = 1.6·blurRadius
     texels, split Y/C and re-attach 50 % full-res source luma (first cut was 65 %, backed off: it read sharper than the soft bleed HEAD is). Colour smears RIGHT of luma edges, edges stay crisp.
     δ rides the existing scale slider (second-order param, tactic 4). One spectralBleed() call, same tap count.
  5. Paper-fibre wicking — §12.2C "paper granulation": a static, vertically-stretched value-noise grain (2×10 px
     cells, no time term) scales the per-pixel bleed radius 0.55×–1.45× and the persistence weight 0.8×–1.2×, so
     the fringes and the advancing front come out fibrous/ragged rather than a clean blur.
FORMULA ADMISSION: chroma delay line ∈ §12.2B (this shader is a retro-glitch chroma-bleed); paper granulation ∈
  §12.2C — admissible because this shader *is* an ink-diffusion-on-paper simulation (it already has "dry-edge rim" and
  "advance front", both paper/chromatography nouns). Both consume what the file has (blurRadius, spectralBleed,
  persistence, source luma). Deletion test both ways passes (without the original bleed, a fibre grain or a delayed
  chroma is not "spectrum bleed"). Rows are disjoint from fork C's other file (sync-pulse + dropout) and from the
  other forks' claims (no Cauchy / Brown–Conrady / CFA zipper, no Wallis, no sim rows).
FORBID on this file: Cauchy / lens-dispersion rows (pixel-focus owns them), a new spring or ripple overlay, IQ palette,
  replacing the wavelength-ordered radii with a single delay, new params.
A PACKING: ACES display RGBA (unchanged).
HEAD FINDING (not fixable here, report only): spring state lives in extraBuffer[133..138]; src/renderer/webgpu/
  audioDepth.ts `writeExtraBuffer` flushes the whole EXTRA_FLOATS scratch every frame (zeros at 133..255), so
  `initialized` is always false → springPos == rawMouse and springVel == 0 → `springVel·lens·0.5` is a dead term and
  the "sprung" lens is the raw pointer. Left as is: a real fix needs persistent state outside extraBuffer. (Note
  docs/agents/WGSL_BUILTINS_GENERATIVE.md still calls [133..255] "safe for persistent state" — it is not.)
```
