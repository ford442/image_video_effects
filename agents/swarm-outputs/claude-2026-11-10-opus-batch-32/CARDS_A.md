# opus/batch-32 — fork A Idea Cards (written before WGSL edits)

SHADER: sph-fluid (density / force / render)
IDENTITY: WCSPH particle liquid (mercury-chrome metaballs) refracting the image; pointer parts it.
KEEP VERBATIM: solver (density + force passes, stride-2 packing, hash, CPU spec parity), A/C stamp packing, all 4 params.
ADD (render pass only — solver untouched so scripts/sim_models/sph_fluid.py stays the spec):
  1. Caustic focus — Laplacian-of-Gaussian of the same 5×5 coverage gather; convex droplet lenses focus light into bright caustic pools on the image just down-light of each drop.
  2. Contact shadow — coverage resampled up-light offset darkens the background beside droplets (liquid sitting on the photo).
  3. Compression shimmer — the stamped rho/rho0 (.b, previously unread) brightens and cools compressed liquid: pressure fronts become visible as faint bright bands.
FORBID: new forces, palette swaps, ripple overlays.
A PACKING: existing stamp field (.r speed, .g vort tint, .b rho/rho0, .a coverage) — unchanged.

SHADER: spec-histogram-equalize
IDENTITY: per-16×16-tile CLAHE contrast enhancement of the photo.
KEEP VERBATIM: workgroup histogram, clip+redistribute, params roles, shoulder, C temporal mix.
ADD:
  1. Sub-bin CDF interpolation — remap lerps CDF(bin-1)→CDF(bin) by the fractional luma, removing the 256-step posterization in smooth gradients.
  2. Honest tile census — out-of-bounds lanes on edge tiles no longer vote clamped edge pixels; CDF normalizes by the true tile pixel count.
  3. Saturation compensation — in Color Preserve mode, RGB×scale lifts oversaturate shadows; chroma is re-scaled by scale^-0.25 around luma so lifted shadows stay natural.
FORBID: palettes, glow, pointer effects beyond existing lens.
A PACKING: ACES display RGBA (unchanged).

SHADER: motion-heatmap
IDENTITY: thermal-camera heat accumulated from frame-difference motion, additive over the video.
KEEP VERBATIM: R=heat/A=prev-luma packing, decay/sensitivity/mouse/shift params, flow advection, runners, click fronts.
ADD:
  1. Thermal conduction — heat diffuses through a 4-neighbour Laplacian each frame, so hot spots bleed into soft blooms like real heat.
  2. FLIR isotherm contours — thin bright contour lines at fixed heat bands, the classic thermal-imager read-out.
  3. Plumbing: ACES on display RGB (was raw sum up to 4.0).
FORBID: springs, IQ palettes, ripple stamps beyond existing.
A PACKING: raw sim state (R heat, A prev luma) — untouched by tonemap.
