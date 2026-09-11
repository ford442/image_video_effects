# Temporal ghost / lag eight — Idea Cards (written before WGSL)

Family: delay, ghost, slit. Not camera/grade language. Not CRT/datamosh. No IQ palette stamp.

---

SHADER: time-lag-map
IDENTITY: per-pixel delay map (radial / wipe / spiral / noise) blending current against C history
KEEP VERBATIM: bufferLength / mappingFunction / feedbackMix / motionSense; five mapping modes; mouse lag well; A = updated history
ADD:
  1. Luma-keyed delay — brighter pixels lag more (time smear on lights, this is a lag map)
  2. Motion-gated smear — existing motionSense also smears history along the UV gradient of |current−C|
FORBID: writing B, IQ palettes, new springs (HEAD has click lag ripples — keep those)
A PACKING: history RGB in A (C is previous history). ACES on display only.

---

SHADER: temporal-rift
IDENTITY: mouse-centered smear that paints current into C with chroma-split history
KEEP VERBATIM: decay / width / chroma / mix params; existing `[133..138]` spring; click rift/shear; FFT-voiced chroma
ADD:
  1. Distance-arrival delay — farther pixels mix toward C later (rift front)
  2. C ghost shear — exact-load C offset along the sprung velocity
FORBID: IQ palettes, new extraBuffer slots
A PACKING: nextHist RGBA in A (C is previous hist). ACES on display.

---

SHADER: phantom-lag-history
IDENTITY: offset echo from C plus rolling luminance in alpha, glow where it WAS bright
KEEP VERBATIM: echo_decay / lag_offset_x/y / hue_shift; echo UV offset; luma history in A.a; mouse luma boost; 4-neighbor luma diffusion
ADD:
  1. Age-tint — older luma (high A.a vs current) shifts cooler
  2. Luma-weighted persist — decayEcho rises where prevAvgLuma is high (brights hang)
FORBID: springs, IQ palettes, packing luma out of A.a
A PACKING: display RGB + luminance history in A (A.a). Exact C loads. ACES on display RGB only (do not ACES stored luma).

---

SHADER: hyb-temporal-fbm-ghost
IDENTITY: per-channel UV drift + FBM domain warp ghost over the plate
KEEP VERBATIM: temporal_shift / fbm_scale / warp_amount / effect_mix; domainWarp; per-channel angle dirs
ADD:
  1. Per-channel lag from exact C — R/G/B mix C at different amounts (history lag, not a new warp)
  2. Source-tied ghost — halo/ghost luma follows source luma (do not add a new IQ palette)
FORBID: extra IQ palette stamp, springs
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: spectral-slit-scan
IDENTITY: 3–7 parametric slits sampling C history with chroma offsets
KEEP VERBATIM: slitCount / trailDecay / chromaShift / curveAmp; sine/spiral/radial curves; loadHistory; held curl; click fronts
ADD:
  1. Wavelength-staggered slits — R/G/B prefer neighboring slit indices
  2. Luma-hold — dark C texels keep more of the previous history (slit doesn’t eat shadows)
FORBID: springs, IQ palettes
A PACKING: ACES display RGBA (C is previous display/history via loadHistory)

---

SHADER: rgb-delay-brush
IDENTITY: brush that delays R/G/B at different speeds under the pointer with wavelength absorption alpha
KEEP VERBATIM: decay / split / radius / alpha_scale; existing `[133..138]` spring; click stamps; Beer-Lambert channel alpha
ADD:
  1. Bristle along stroke — sample C offset perpendicular to spring velocity
  2. Wet C trail — exact-load C persistence under the mask (paint, not a new sim)
FORBID: new extraBuffer slots, IQ palettes
A PACKING: delayed RGB in A (C is previous delayed color). ACES on display only.

---

SHADER: green-tracer
IDENTITY: green-tinted video with motion trails, edge glow, grain
KEEP VERBATIM: trailLen / glowInt / greenTint / noiseAmt JSON roles; motion vs persist; Sobel-ish edge glow
ADD:
  1. Phosphor persist from exact C — trails use C load, fade from trailLen
  2. Edge-only trail — persist more where edgeDetect is high
FORBID: new springs, reading extraBuffer[0..132]
A PACKING: trail RGB in A (C is previous trail). ACES on display.
LANDMINE: Uniforms field order is currently `config, zoom_params, zoom_config, ripples`. Canonicalize to `config, zoom_config, zoom_params, ripples` and map sliders onto zoom_params.xyzw. Derive trail fade from trailLen. Do not treat zoom_config as extra sliders (it is mouse/time).

---

SHADER: phase-shift
IDENTITY: RGB rotationally shifted around the mouse, with layered zoom speeds
KEEP VERBATIM: layer_speed_low / layer_speed_high / edge_glow / fog_density; 5-layer mix of speeds; ping-pong UV; mouse as zoom center (engine UV, not /resolution)
ADD:
  1. Per-channel angular period — R/G/B sample at different rotation angles around the mouse
  2. Distance-modulated phase — rotation amount grows with distance from the mouse
FORBID: extraBuffer[0] / [10] (engine FFT slots); cloning interactive-rgb-split wavelength split; IQ palettes
A PACKING: ACES display RGBA (HEAD never wrote A)

---
