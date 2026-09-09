# Camera / shutter / grade eight — Idea Cards (written before WGSL)

Family: photographic optics, shutter, stock, and grade. Quiet native ideas. No spring+ripple+IQ overlay. Night-vision already owns `[133..138]` — keep it; do not add springs to the rest.

---

SHADER: pp-ssao
IDENTITY: stylized screen-space depth occlusion that darkens creases and optionally bleeds occluder color
KEEP VERBATIM: radius / intensity / quality / color_bleed params; rotating sample kernel; quality 4/8/16 taps; held-pointer radius bump; existing click fronts and scan packets
ADD:
  1. Cosine-weighted hemisphere — weight each tap by max(N·offsetDir, 0) so grazing samples contribute less (this is SSAO, not a disk blur)
  2. Bent-normal color bleed — average unoccluded sample directions and tint bleed along that bent normal into the existing color_bleed path
FORBID: extraBuffer springs, replacing AO with a holographic scanner, IQ palettes
A PACKING: ACES display RGBA (HEAD stored AO grayscale in A and never read C)

---

SHADER: long-exposure
IDENTITY: open shutter that accumulates bright frames into C and lets dark regions decay; click erases / stamps flashes
KEEP VERBATIM: accumSpeed / decayRate / glowRadius / threshold; exact C load of the exposure buffer; positional eraser; ripple warm flashes; 4-tap glow from C; FFT band decay drift
ADD:
  1. Reciprocity-law fade — dim accumulated trails decay faster than hot ones (Schwarzschild, this is a long exposure)
  2. Highlight-only plate mix — current frame composites more where it is above threshold, so the live plate shows through the hottest traces
FORBID: new springs, IQ palettes, turning this into a slit-scan
A PACKING: raw HDR exposure RGB in A (C is the previous accumulation — do not ACES stored fields). ACES/Reinhard on writeTexture only.

---

SHADER: tone-histogram
IDENTITY: local-window histogram stretch plus film toe/shoulder curve, split-tone, grain, depth haze
KEEP VERBATIM: stretch / toe / shoulder / haze params (ids `target` / `contrast` / `saturation` / `psychedelic`); 3×3 local mean/std; filmCurve; split-tone; existing held dodge disc
ADD:
  1. Mouse as local metering window — stretch gain is biased toward luma sampled at the cursor (spot meter), not a second effect
  2. Per-channel shoulder — filmCurve on R/G/B with a slight shoulder offset so highlights roll off per dye, not only luma
FORBID: springs, ripples, holographic neon
A PACKING: ACES display RGBA (HEAD packed telemetry and never read C)

---

SHADER: temporal-halation-freeze
IDENTITY: hex-bokeh film halation that accumulates into C with a ghost echo and warm/cool bloom temp
KEEP VERBATIM: exposure / decay / color_temp / ghost params; 7-tap HEX_TAPS bloom; bass envelope in A.a; ACES display
ADD:
  1. Red dye-layer lag — C’s red channel lags the new halo more than G/B (print halation is red-heavy)
  2. C freeze-hold — held pointer freezes the accumulated halo from exact C so the ghost plate holds
FORBID: springs, writing new B packing, IQ palettes, slit-scan language
A PACKING: accumulated halo RGB + envelope A (raw bloom energy; C is previous halo). ACES on display only. Stop unused B write.

---

SHADER: double-exposure-zoom
IDENTITY: two plates — primary photo plus mouse-pivoted zoom/rotate second plate, luminance matte, film response
KEEP VERBATIM: rotation / zoom / edgeFade / audioReact; mouse pivot + depth parallax; edge CA; screen/soft-light hybrid; filmResponse; light leak
ADD:
  1. Plate registration drift — continuous sub-pixel offset between plates (analog sandwich, not a new warp)
  2. Highlight-keyed second plate — matte from plate-2 highlights so only bright second-exposure content prints through
FORBID: cloning HDR-overlap bloom from double-exposure-hdr, springs, IQ palettes
A PACKING: ACES display RGBA (C trail reads previous display; exact textureLoad)

---

SHADER: night-vision-scope
IDENTITY: green intensifier tube with a mouse-tracked scope disc, grain, scanlines, click flares
KEEP VERBATIM: scopeSize / grainAmount / brightness / scanlineStrength; existing `[133..138]` spring; click intensifier rings; NV green luma remap; inside/outside mix
ADD:
  1. MCP scintillation — sparse hash sparkles inside the tube (microchannel plate, this is NV)
  2. Bright-source blooming — neighbors above a luma knee smear into the phosphor (blooming, not a new CRT)
FORBID: new extraBuffer slots, IQ palettes, replacing the scope with a thermal camera
A PACKING: ACES display RGBA

---

SHADER: chromatographic-separation
IDENTITY: depth-scaled RGB channel split along a rotating axis (params stay viscosityR/G/B/temperature mapped onto zoom_params)
KEEP VERBATIM: param roles (x=amount, y=spin, z=depthWeight, w=mode); per-channel offset samples; depth-layered alpha
ADD:
  1. Solvent-front Rf — a traveling Y front (time + temperature/w) so separation only develops past the solvent line (paper chromatography)
  2. Capillary tailing — smear each channel a short extra step along its own offset axis (spots elongate, not a liquid solver)
FORBID: renaming saved params, springs, IQ palettes, turning this into RGB delay brush
A PACKING: ACES display RGBA (C unused as history)

---

SHADER: double-exposure-hdr
IDENTITY: screen-blend of a mouse-pivoted zoom/rotate overlay plus HDR bloom, ACES to display
KEEP VERBATIM: zoom / rotation / opacity / saturation; mouse pivot; screen blend; existing held mouse glow and click flashes
ADD:
  1. Overlap-only bloom knee — bloom extracts where BOTH plates are bright (the overlap halo the description already claims)
  2. Pivot-locked second plate — second UVs stay locked to the mouse pivot while bloom is taken from the overlap, not a drifting registration (that idea belongs to double-exposure-zoom)
FORBID: registration-drift clone, springs, IQ palettes
A PACKING: ACES display RGBA (HEAD stored HDR in A and never read C)

---
