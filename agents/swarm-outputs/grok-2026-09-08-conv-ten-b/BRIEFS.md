# Convolution ten B — Idea Cards (written before WGSL)

Family: remaining `conv-*` kernels after the 2026-09-08 print/paint/convolution ten. Quiet native ideas. No spring+ripple+IQ stamp. Palettes kept where HEAD already owned them.

---

SHADER: conv-guided-video-filter
IDENTITY: He guided filter — original frame is the guide, C is the processed input; mouse tightens the window
KEEP VERBATIM: rad / eps / guide_strength / mouse_strength; linear model q = aI + b; mouse smaller radius/eps
ADD:
  1. Depth-augmented guide — mix luma with depth so object boundaries join the linear model
  2. Exact integer C loads for P — the processed input is history, not a filtered sample
FORBID: springs, IQ palettes, replacing guided filter with bilateral
A PACKING: display RGBA (HEAD already writes A; C is processed RGB)

---

SHADER: conv-stochastic-stipple
IDENTITY: luminance-weighted blue-noise dots in cells; mouse densifies a well
KEEP VERBATIM: cell_size / threshold / saturation / mouse_influence; cell hash; blue-noise threshold; mouse smaller cells
ADD:
  1. Paper ground — dots sit on warm paper, not a dark void (stipple print)
  2. Gradient-stretched dots — ellipses along local luma gradient (print grain, not circles only)
FORBID: springs, replacing stipple with a hatch costume
A PACKING: ACES display RGBA (HEAD read C, never wrote A)

---

SHADER: conv-structure-tensor-flow
IDENTITY: structure-tensor eigenvectors + LIC streamlines; mouse seeds a vortex
KEEP VERBATIM: lic_steps / coherency_boost / flow_speed / mouse_influence; 3×3 tensor; mouse vortex; cosine palette
ADD:
  1. Minor-eigenvector LIC — integrate along the edge (λ2), not across it (classic tensor LIC)
  2. Source-luma tint — LIC keeps photo tone under the flow color
FORBID: springs, replacing LIC with a particle solver
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: conv-spiral-blur
IDENTITY: log-spiral motion blur around a mouse-weighted center
KEEP VERBATIM: tightness / num_arms / samples / mouse_influence; polar arms; golden-ratio tint
ADD:
  1. φ-spaced arms — arm offset uses golden ratio, not equal 2π/N only
  2. Archimedean mix — blend linear radius into the existing exponential spiral
FORBID: springs, extra CA as the upgrade
A PACKING: ACES display RGBA (HEAD read C, never wrote A)

---

SHADER: conv-steerable-pyramid
IDENTITY: Freeman–Adelson G2 steerable bands at 0/45/90/135; mouse steers θ
KEEP VERBATIM: sigma / response_scale / color_boost / mouse_influence; g2Basis steer; cosine palette
ADD:
  1. H2 quadrature energy — HEAD already defined `h2Basis` and never called it; use the odd partner
  2. Source-tied reconstruction — mix oriented energy back onto the photo
FORBID: springs, extra CA as the upgrade
A PACKING: ACES display RGBA (HEAD read C, never wrote A)

---

SHADER: conv-reaction-convolution
IDENTITY: one Gray-Scott step seeded from photo luma/edges, mixed over the picture
KEEP VERBATIM: diffA / diffB / feedRate / mouseInfluence; lap A/B; mouse B inject; false-color A,B,blue store
ADD:
  1. Honest A/B persistence — load C.rg as chemicals so the step continues (HEAD re-seeded from the photo every frame)
  2. Pearson F/k ratio from the existing feed slider — spots vs worms, still Gray-Scott
FORBID: springs, IQ palettes, rewriting as a different RD
A PACKING: display-ish RGBA matching HEAD store (A, B, mixed-blue, activity) so C.rg is chemicals

---

SHADER: conv-guided-filter-depth
IDENTITY: depth is the guide; mouse is a sharper aperture; mix by depth_influence
KEEP VERBATIM: radius / epsilon / depth_influence / mouse_influence; a,b linear model on depth
ADD:
  1. Joint luma range — photo edges that disagree with depth keep more original
  2. Coefficient box — a small second mean on a (He’s second box, still guided filter)
FORBID: springs, IQ palettes, replacing with a DoF toy
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: conv-bilateral-grid-splat
IDENTITY: fast bilateral via spatial × intensity × grid-bin weights; mouse tightens the well
KEEP VERBATIM: spatial_sigma / intensity_sigma / grid_resolution / mouse_influence; 2D splat loop; gridQuant bins
ADD:
  1. Joint depth range in the bilateral term
  2. Adjacent-bin slice — mix neighboring luma bins (grid slice, not a new filter)
FORBID: springs, extra psychedelic overlay
A PACKING: ACES display RGBA (HEAD read C, never wrote A)

---

SHADER: conv-frequency-domain-notch
IDENTITY: bank of cosine kernels as a spatial-frequency notch/boost; mouse picks target frequency
KEEP VERBATIM: num_bands / bandwidth / boost_cut / mouse_influence; cosine kernels; notchFilterResponse
ADD:
  1. Oriented notch — kernel distance along mouse radial direction (anisotropic)
  2. Residual mix — cut mode subtracts the band from the photo (true notch)
FORBID: springs, extra CA as the upgrade
A PACKING: ACES display RGBA (HEAD read C, never wrote A)

---

SHADER: conv-fractal-kernel
IDENTITY: Mandelbrot membership shapes the blur kernel; mouse warps the set center
KEEP VERBATIM: kernel_radius / fractal_zoom / iterations / mouse_influence; mandelbrotMember weights; Julia ripples
ADD:
  1. Boundary vs interior weight — set edge (dwell ~ 0.5) samples more than deep interior
  2. Distance-estimator glint on the set boundary
FORBID: springs, replacing the kernel with a full Mandelbrot renderer
A PACKING: ACES display RGBA (HEAD never wrote A)
