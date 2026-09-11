# Temporal ghost / lag eight — NOTES

Cards in BRIEFS.md were written before WGSL. Per shader:

## time-lag-map
- KEPT: four params; five mapping modes; mouse lag well; A = history RGB
- ADDED: luma-keyed delay; motion-gated smear along |current−C|
- A PACKING: history RGB in A. Exact C load. ACES display. No B write.
- Springs: none (existing click lag ripples kept)

## temporal-rift
- KEPT: decay/width/chroma/mix; `[133..138]` spring; click rift/shear
- ADDED: distance-arrival delay; C ghost shear along sprung velocity
- A PACKING: nextHist in A. Exact C loads. ACES display.
- Springs: existing only

## phantom-lag-history
- KEPT: echo decay / lag xy / hue; luma in A.a; mouse boost; 4-neighbor diffusion
- ADDED: age-tint (cooler when old luma > current); luma-weighted persist
- A PACKING: display RGB + luma history A. Exact C. ACES display RGB only.
- Springs: none

## hyb-temporal-fbm-ghost
- KEPT: temporal_shift / fbm_scale / warp_amount / effect_mix; domainWarp; per-channel dirs
- ADDED: per-channel lag from exact C; source-tied ghost (no new IQ palette)
- A PACKING: ACES display RGBA (HEAD never wrote A)

## spectral-slit-scan
- KEPT: slit count/decay/chroma/curve; sine/spiral/radial; loadHistory; held curl
- ADDED: wavelength-staggered R/G/B slit offsets; luma-hold on dark C
- A PACKING: ACES display RGBA

## rgb-delay-brush
- KEPT: persistence/split/radius/alpha_scale; `[133..138]` spring; click stamps; Beer-Lambert alpha
- ADDED: bristle perpendicular to spring vel; wet C trail
- A PACKING: delayed RGB in A. ACES on display only. Canonical sampler names.

## green-tracer
- KEPT: trailLen / glowInt / greenTint / noiseAmt JSON roles; edge glow; grain
- ADDED: phosphor persist from exact C; edge-only trail
- A PACKING: trail RGB in A. ACES display.
- Uniforms canonicalized: sliders on zoom_params, mouse/time on zoom_config. trailFade derived from trailLen (old zoom_config extra slots were never saved params).

## phase-shift
- KEPT: layer speed low/high, edge glow, fog; 5-layer zoom mix; ping-pong wrap; mouse as zoom center (engine UV)
- ADDED: per-channel angular period around mouse; distance-modulated phase
- A PACKING: ACES display RGBA (HEAD never wrote A)
- STOPPED extraBuffer[0] and [10] reads (engine FFT slots)
