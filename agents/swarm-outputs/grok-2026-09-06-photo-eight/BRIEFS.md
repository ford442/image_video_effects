# Photo / print / grade eight — Idea Cards (written before WGSL)

Family: photographic, print, and grade filters. Quiet native ideas. No spring+ripple+IQ overlay.

---

SHADER: pp-bloom
IDENTITY: HDR threshold bloom added onto the source photo, with optional anamorphic Y stretch
KEEP VERBATIM: intensity / anamorphic / threshold / quality tap-count params; soft-knee bright extract; multi-tap Gaussian; additive composite
ADD:
  1. Hue-preserving bright extract — keep highlight tint instead of luma-scaling RGB (this is a bloom)
  2. Horizontal anamorphic streak along the already-stretched axis — a second 1D kernel, not a new effect
FORBID: springs, click shockwaves, IQ palettes, ferrofluid
A PACKING: ACES display RGBA (HEAD stored the blur in A — packing lie; C is unused as history)

---

SHADER: pp-tone-map
IDENTITY: four-curve HDR grade (ACES / Uncharted 2 / Reinhard / AgX) plus exposure, contrast, saturation
KEEP VERBATIM: algorithm / exposure / contrast / saturation roles; the four named curves
ADD:
  1. Continuous algorithm mix — slider blends neighboring curves instead of hard 0.25 bands
  2. Hue-preserving contrast — scale around luma so the grade does not crush chroma
FORBID: springs, ripples, a second ACES after AgX, holographic neon
A PACKING: display RGBA (the tone-mapped picture). Do not ACES stored fields twice.

---

SHADER: analog-film-degrade
IDENTITY: grain, hairline scratches, dust, sepia fade, vignette on the photo
KEEP VERBATIM: grain_intensity / fade_amount / scratch_freq / vignette_strength; sepia+desat fade; vignette
ADD:
  1. Per-channel grain (R/G/B different spatial scales) — analog stock, not mono hash
  2. Continuous gate-weave + traveling hairline instead of `floor(time * 8)` strobed scratches
  3. Print-through ghost from exact C — previous frame faintly in the emulsion
FORBID: springs, IQ palettes, replacing film with a glitch block solver
A PACKING: ACES display RGBA (print-through reads C as color)

---

SHADER: color-blindness
IDENTITY: protan / deutan / tritan simulation with optional mouse-X split vs original
KEEP VERBATIM: type / severity / split params and the three Brettel-style matrices; split uses mouse X
ADD:
  1. Continuous type mix — Type slider interpolates neighboring matrices instead of three hard bands
  2. Confusion-axis assist from the unused 4th param — hatch where |sim − original| is large (does not rename saved `unused`)
FORBID: springs, palettes, turning this into a color-grade playground
A PACKING: display RGBA

---

SHADER: crumpled-paper
IDENTITY: FBM crease heightfield, mouse irons a disc flat, lighting from crease normals
KEEP VERBATIM: scale / depth / smooth_radius / light_strength; ridge mix; mouse flatten; existing AO / sheen / wear
ADD:
  1. Fibre grain along the crease tangent (paper, not film grain)
  2. Ironing memory — exact C keeps recently flattened height so the ironed patch lingers
FORBID: springs, ripples, liquid solvers
A PACKING: display RGBA in A (C read as previous color/height proxy via alpha-encoded height)

---

SHADER: retro-gameboy
IDENTITY: four-shade olive LCD, blocky pixels, grid, horizontal shadow
KEEP VERBATIM: pixel_size / contrast / grid_strength / shadow_offset; 4-color palette; block quantize
ADD:
  1. Round LCD dots inside each block (dot-matrix, not only square cells)
  2. Honest LCD ghosting — write A so the existing C persistence is THIS shader’s previous palette, not a random prior slot
FORBID: springs, neon palettes, replacing GB with a full CRT sim
A PACKING: ACES display RGBA (ghost reads C as color)

---

SHADER: conv-bilateral-dream
IDENTITY: edge-preserving bilateral smooth of the photo; mouse tightens the spatial sigma
KEEP VERBATIM: spatial_sigma / color_sigma / hue_shift / mouse_influence; bilateral weight; mouse sharpness well
ADD:
  1. Joint bilateral — depth joins the range term so photo edges that match depth stay sharper
  2. Luma-range option baked into the existing color_sigma path — range on luma, scale RGB (stops chroma bleed while smoothing)
FORBID: extra ripple overlays, IQ palettes as the look, springs
A PACKING: ACES display RGBA (HEAD never wrote A; C mix was a lie — write A)

---

SHADER: tilt-shift
IDENTITY: miniature tilt-shift: Scheimpflug focal band, spiral CoC blur, toy saturation
KEEP VERBATIM: strength / focusWidth / saturation / tiltAngle; mouse sets focal Y; golden-angle blur
ADD:
  1. Hexagonal aperture bokeh in the CoC (sample the existing spiral with a hex radius, not a disk)
  2. Specular bloom only in out-of-focus highlights (optical, not a second bloom shader)
FORBID: springs, replacing tilt-shift with a full lens-flare stack
A PACKING: ACES display RGBA
