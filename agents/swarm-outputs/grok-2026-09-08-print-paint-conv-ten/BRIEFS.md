# Print / paint / convolution ten — Idea Cards (written before WGSL)

Family: convolution kernels plus painterly/print grades. Quiet native ideas. No spring+ripple+IQ stamp. Springs kept only where HEAD already owned them (film-cross-process enlarger).

---

SHADER: conv-non-local-means
IDENTITY: patch-similarity denoiser with artistic overdrive; mouse tightens `h` in a focus zone
KEEP VERBATIM: patch_radius / search_radius / filter_strength / overdrive; SSD patchDistance; mouse h-well; overdrive mix back to center
ADD:
  1. Luma-weighted patch SSD — chroma differences count less so denoise does not smear local color
  2. Gradient-aligned search — extra weight when the neighbor offset follows the local edge tangent
FORBID: springs, IQ palettes, treating existing CA as the upgrade
A PACKING: ACES display RGBA (HEAD read C as color but never wrote A — packing lie, fix)

---

SHADER: conv-anisotropic-diffusion
IDENTITY: Perona–Malik 4-neighbor diffusion that flattens into oil-paint regions; mouse is a heat source
KEEP VERBATIM: kappa / dt / iterations / mouse_influence; 4-neighbor flux from readTexture; mouse heat; existing CA
ADD:
  1. Tukey biweight conductivity mixed with the existing exponential — classic PM variant that stops leaking across strong edges
  2. Coherence boost — extra flux along the weaker axis so smoothing follows the edge (Weickert-lite, still 4-neighbor)
FORBID: springs, replacing PM with a liquid solver, more CA
A PACKING: ACES display RGBA (HEAD read C, never wrote A)

---

SHADER: conv-difference-of-gaussians-cascade
IDENTITY: 4-scale signed DoG; mouse pulls fine vs coarse; cosine palette maps responses
KEEP VERBATIM: scale_base / contrast / color_shift / mouse_influence; four DoG scales; cosine palette
ADD:
  1. Zero-crossing ridges — thin Marr–Hildreth lines where the fine DoG changes sign
  2. Source-tied XDoG tanh — mix a photographic ink threshold into the palette so edges stay attached to the photo
FORBID: springs, replacing DoG with a different detector, extra CA as the upgrade
A PACKING: ACES display RGBA (HEAD read C, never wrote A)

---

SHADER: conv-morphological-erosion-dilation
IDENTITY: min/max morphology with a mouse-elongated structuring element; blend erode/dilate plus gradient
KEEP VERBATIM: kernel_radius / erode_dilate_blend / gradient_boost / mouse_influence; circular SE; mouse rotate/stretch
ADD:
  1. Black-hat (dilation − center) beside the existing top-hat — native morphology, mixed by the blend slider
  2. Ridge skeleton hint — morphological gradient kept where it is a local max along the SE axis
FORBID: springs, IQ palettes
A PACKING: ACES display RGBA (HEAD read C, never wrote A)

---

SHADER: conv-gabor-texture-analyzer
IDENTITY: 4-orientation Gabor bank; mouse rotates the bank; signed responses colorize texture
KEEP VERBATIM: frequency / sigma / response_scale / mouse_influence; 0/45/90/135 bank; cosine palette
ADD:
  1. Quadrature energy — odd (sin) partner so each orientation contributes envelope energy, not only even-phase
  2. Dominant-orientation grain — faint lines along argmax θ (texture direction, not a hatch costume)
FORBID: springs, extra CA as the upgrade
A PACKING: ACES display RGBA (HEAD read C, never wrote A)

---

SHADER: watercolor-bloom
IDENTITY: soft watercolor bloom, paper fibre, wet-edge darken, C drying advection
KEEP VERBATIM: bloom_radius / wet_edge / paper_texture / dry_speed; 13-tap bloom; wet-edge; paper noise; C advection; held brush + click blooms
ADD:
  1. Granulation — pigment settles in paper-noise valleys (watercolor, not film grain)
  2. Backrun cauliflower — frilly blooms where C is wetter than the fresh wash (dry-edge backruns)
FORBID: springs, IQ palettes, replacing watercolor with a liquid solver
A PACKING: display RGBA (HEAD already writes A; keep leftover B write)

---

SHADER: film-cross-process
IDENTITY: E6-in-C41 per-channel S-curves, cyan/orange skew, grain, vignette
KEEP VERBATIM: contrast / colorSkew / grain / vignette; per-channel scurve; existing developer spring + chemical rings
ADD:
  1. Per-channel grain (R/G/B different seeds) — film stock, not mono hash
  2. Highlight cyan-green crossover — classic XPro highs go cyan while shadows stay orange-skewed
FORBID: adding more springs/ripples as the upgrade
A PACKING: display RGBA (HEAD already writes A)

---

SHADER: engraving-stipple
IDENTITY: copperplate hatch + stipple on paper; mouse burin; click impact rings
KEEP VERBATIM: line_density / stipple_scale / contrast / light_rotation; hatch/cross/contour; burin + click rings
ADD:
  1. Roulette stipple — circular burr dots denser in shadows (second copperplate tool)
  2. Burin taper — line weight from |grad| so darks cut thicker
FORBID: springs, IQ palettes
A PACKING: keep HEAD telemetry in A (ink, hatch, burin, alpha) — C unused as color

---

SHADER: rotoscope-ink
IDENTITY: Sobel outlines + posterize flats; mouse paints extra ink
KEEP VERBATIM: edge_threshold / posterize_levels / ink_density / shade_mix; posterize; tapered brush stroke
ADD:
  1. Variable ink weight from edge magnitude — thicker on strong edges
  2. Cel hold-flats — away from edges, snap harder to posterize (cel animation hold)
FORBID: springs, replacing with a different toon shader
A PACKING: keep HEAD telemetry in A (outline, motion, mouse, alpha)

---

SHADER: encaustic-wax
IDENTITY: thermal wax strata over the photo; mouse is a heat gun; melt displaces UVs
KEEP VERBATIM: brush_scale / melt_intensity / pigment_deposit / relief; 3 strata; flow displace; SSS/spec
ADD:
  1. Wax bloom — white crystalline haze where heat is low (cooling bloom)
  2. Iron-scrape — held mouse locally thins wax, revealing more of the photo
FORBID: springs, IQ palettes, replacing with a liquid solver
A PACKING: keep HEAD telemetry in A (ridge, pigment, heatMouse, alpha)
