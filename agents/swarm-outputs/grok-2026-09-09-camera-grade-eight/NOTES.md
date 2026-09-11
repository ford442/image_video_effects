# Camera / shutter / grade eight — NOTES

Cards in BRIEFS.md were written before WGSL. Per shader:

## pp-ssao
- KEPT: radius/intensity/quality/color_bleed; 4/8/16 taps; held radius bump; click fronts; scan packets
- ADDED: cosine-weighted hemisphere (N·offsetDir); bent-normal color bleed along unoccluded average
- A PACKING: ACES display RGBA (was AO grayscale, C unread)
- Springs: none (HEAD had click fronts only)

## long-exposure
- KEPT: accum/decay/glow/threshold; exact C load; eraser; ripple flashes; 4-tap C glow; FFT band decay
- ADDED: reciprocity-law fade (dim trails die faster); highlight-only plate mix
- A PACKING: raw HDR exposure RGB (not ACES’d). Display ACES after Reinhard.
- Springs: none (existing ripples kept)

## tone-histogram
- KEPT: stretch/toe/shoulder/haze (`target`/`contrast`/`saturation`/`psychedelic`); 3×3 stats; filmCurve; split-tone; held dodge
- ADDED: mouse spot-meter biases stretch ref; per-channel dye shoulder
- A PACKING: ACES display RGBA (was telemetry, C unread)
- Springs: none

## temporal-halation-freeze
- KEPT: exposure/decay/color_temp/ghost; HEX_TAPS bloom; bass envelope in A.a
- ADDED: red dye-layer lag; held C freeze-hold
- A PACKING: accumulated halo RGB + envelope A. Exact textureLoad C. Stopped unused B write.
- Springs: none

## double-exposure-zoom
- KEPT: rotation/zoom/edgeFade/audioReact; mouse pivot + parallax; edge CA; screen/soft hybrid; filmResponse; light leak
- ADDED: continuous registration drift; highlight-keyed second plate
- A PACKING: ACES display RGBA. Exact C load for trail.
- Springs: none. Did not clone HDR overlap bloom.

## night-vision-scope
- KEPT: four params; `[133..138]` spring; click rings; NV green remap; inside/outside mix
- ADDED: MCP scintillation; bright-source blooming
- A PACKING: ACES display RGBA
- Springs: existing only

## chromatographic-separation
- KEPT: zoom_params roles (amount/spin/depthWeight/mode) — saved viscosity* ids unchanged
- ADDED: solvent-front Rf; capillary tailing along each channel offset
- A PACKING: ACES display RGBA. Mouse UV (engine 0–1), not /resolution.
- Springs: none

## double-exposure-hdr
- KEPT: zoom/rotation/opacity/saturation; mouse pivot; screen blend; held glow; click flashes
- ADDED: overlap-only bloom knee; pivot-locked second UV (not registration drift)
- A PACKING: ACES display RGBA (was HDR in A, C unread)
- Springs: none
