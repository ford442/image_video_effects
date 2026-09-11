# Pixel-sort eight — Idea Cards (written before WGSL)

Family: Asendorf-style interval sorts, flow-line sorts, magnetic luma smear, radial stretch-sort. Native sort ideas only. No spring+ripple+IQ stamp. No clone of explorer’s existing scan-sweep onto the other seven. Springs kept only where HEAD already owned them (`magnetic-luma-sort` magnet).

Skipped as already overlay-rich from Batches 58–66: `pixel-sort-glitch`, `glitch-pixel-sort`, `scanline-sorting`, `spectral-glitch-sort`. Skipped as already idea-bearing: `luma-pixel-sort`, `pixel-depth-sort`, `bitonic-sort`, `voxel-depth-sort`.

---

SHADER: pixel-sorter
IDENTITY: single-axis displacement sort of bright pixels, mouse-gated, optional mouse-velocity axis
KEEP VERBATIM: direction / reverse / intensityScale / threshold; luma+hue key; cursor Gaussian; existing wavelength tint
ADD:
  1. Asendorf interval close — walk the sort axis and stop when neighbor luma drops below threshold (classic segments, not more curl)
  2. Span-seam accent — thin highlight where this pixel is in-interval and the next sample along the axis is not
FORBID: new springs, IQ palettes, treating existing wavelength tint as the upgrade
A PACKING: ACES display RGBA. HEAD filtered C for temporal mix and wrote mouse into B@ (0,0) which A→C overwrites — exact C load; prev-mouse in extraBuffer[133..134] (1-frame delay, not a spring). Stop writing B.

---

SHADER: pixel-sort-explorer
IDENTITY: Asendorf interval sort inside a mouse spotlight, V/H axis, scan read-out band
KEEP VERBATIM: thresh / radius / dir / smooth; interval walk; wobble; scan sweep; spotlight dimming
ADD:
  1. Luma-hold — pixels just under threshold stay sorted if C already held a streak (hysteresis, not a new kernel)
  2. Exact-C streak persist — mix one frame of C.rgb into the streak so runs don’t strobe
FORBID: springs, replacing V/H with radial, cloning sorter’s span-seam as the whole upgrade
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: spectral-flow-sorting
IDENTITY: Lucas-Kanade optical flow, then luma-weighted gather along the flow
KEEP VERBATIM: flow_sensitivity / sort_threshold / freq_influence / smoothing; LK; mouse gravity; local frequency tap
ADD:
  1. Exact-C Lucas-Kanade — history is `textureLoad(dataTextureC)`, not a filtering sampler
  2. Asendorf close along the flow — stop the walk when luma drops below threshold; take the brightest in-interval sample (true sort, not a luma-weighted blur)
FORBID: new springs; treating existing flow-angle IQ mix / clock rings as the upgrade; `zoom_config.x` as audio
A PACKING: raw previous RGB in A for the next LK frame (do not ACES stored A). ACES on writeTexture only.

---

SHADER: hybrid-spectral-sorting
IDENTITY: vertical neighbor luma-swap, with spectral bands along Y
KEEP VERBATIM: sort_threshold / spectral_bands / displacement / hue_shift; vertical neighbor compare; band-indexed displacement
ADD:
  1. Band-length interval — walk several neighbors inside the same `floor(uv.y * bands)` row-band and keep the brightest (sort inside the band, not one swap)
  2. Honest three-band audio — `plasmaBuffer[0].xyz` drives band energy / glow (kill `zoom_config.x` as audio)
FORBID: springs; treating the existing IQ palette as the upgrade
A PACKING: ACES display RGBA (HEAD wrote no A)

---

SHADER: flow-sort
IDENTITY: Sobel-perpendicular streamline sort; darker flows down the field
KEEP VERBATIM: flowStrength / sortPasses / strandPersist / threshold; perp-to-gradient flow; mouse vortex; upstream/downstream luma swaps
ADD:
  1. LIC smear — two extra taps along the existing field so strands read as streamlines
  2. Interval gate on the streamline — skip a swap when the sample’s luma has already dropped below threshold (Asendorf on the flow, not a new field)
FORBID: new springs, IQ palettes, extraBuffer
A PACKING: ACES display RGBA so C persist is color. HEAD stored flow in A and read C as previous color (packing lie). Stop writing B. Exact `textureLoad` for persist.

---

SHADER: magnetic-luma-sort
IDENTITY: bright pixels smear toward/away from a sprung magnet via exact-C trail
KEEP VERBATIM: pullStrength / threshold / trailDecay / attract-repel; extraBuffer[133..138] spring; exact C gather; click vortices; FFT row voice
ADD:
  1. Dipole field-line offset — a perpendicular B-field component so trails follow loops, not only radial pull
  2. Luma domains — sort energy peaks at discrete luma steps (magnetic domains), not a second threshold slider
FORBID: a second spring, IQ palettes, rewriting the magnet as a pixel-sort explorer
A PACKING: ACES display RGBA (HEAD already)

---

SHADER: pixel-sort-radial
IDENTITY: luma-gated radial stretch toward/away from the mouse
KEEP VERBATIM: stretch / thresh / radius / dir; radial dir; existing CA; influence falloff
ADD:
  1. Radial Asendorf interval — walk along the radius and close when luma drops below threshold; sample the brightest in-run pixel
  2. Ring seam — concentric accent at the closed end of the radial run (sort geometry, not more spectral runners)
FORBID: new springs; treating existing click-front / spectral runners as the upgrade
A PACKING: ACES display RGBA (HEAD wrote display)

---

SHADER: mouse-pixel-sort
IDENTITY: mouse-loupe luma sort on V or H, with invert-dark mode
KEEP VERBATIM: threshold / length / direction / invert; mouse influence; existing curl/attractor/voronoi as already-there costume
ADD:
  1. Asendorf interval along the V/H axis — stop the offset walk when luma crosses threshold; take brightest (or darkest in invert)
  2. Exact-C ghost — one-frame persist of the sorted run so streaks hold
FORBID: more FBM/voronoi/attractor as the upgrade; new springs
A PACKING: ACES display RGBA. HEAD packed telemetry `(offset, influence, streak)` and never read C — packing lie, fix.
