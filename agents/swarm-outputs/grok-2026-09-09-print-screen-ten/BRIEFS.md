# Print-screen / dither / mosaic ten — Idea Cards (written before WGSL)

Family: AM/FM print screens, stipple packing, Bayer dither, tessera mosaics, and RGB weave. Quiet native ideas. No spring+ripple+IQ stamp. No ellipse+hex-rosette clone of yesterday’s Wave Halftone. Springs kept only where HEAD already owned them (`color-channel-weave` pointer).

---

SHADER: spec-blue-noise-stipple
IDENTITY: blue-noise jittered pointillist dots on paper; darker cells make bigger dots
KEEP VERBATIM: dot_scale / dot_size / color_var / density; R2 jitter; dual + golden tertiary dots; held densification; click splatter
ADD:
  1. Dark-cell packing — R2 jitter shrinks as luma drops so ink nests tighter (stipple packing, not a new sampler)
  2. Neighbor occupancy skip — if 4-neighbor cells are already ink-heavy, secondary/tertiary dots drop
FORBID: springs, IQ palettes, CMYK screens, Wave Halftone ellipse/rosette
A PACKING: ACES display RGBA (HEAD packed `(localColor, mask)` and never read C — packing lie, fix)

---

SHADER: stipple-render
IDENTITY: ink dots on paper (darker = bigger), wet bleed at the mouse, hatch in darks
KEEP VERBATIM: dot_scale / contrast / wet_radius / color_reveal; Lloyd-ish jitter; wet bleed; paper grain; ACES
ADD:
  1. Contour-aligned hatch — strokes follow the Sobel tangent instead of a 45° wallpaper
  2. Exact-C wet memory — ink stays wet one frame where C was already dark (bleed persistence)
FORBID: springs, replacing ink with color pointillism or CMYK
A PACKING: ACES display RGBA (HEAD already)

---

SHADER: halftone-reveal
IDENTITY: mouse-loupe reveals CMYK AM screens over the photo
KEEP VERBATIM: dot_size / angle / reveal_size / magnify; four rotated plates; loupe shrinks dots; paper; existing overlap term
ADD:
  1. Per-plate dot gain — cyan spreads more than black (newsprint, not a new screen)
  2. Highlight knockout — coated-stock specular punches holes in the AM dots
FORBID: springs, scanner overlay, Wave Halftone ellipse/rosette
A PACKING: ACES display RGBA (HEAD packed telemetry in A, never read C — fix)

---

SHADER: bayer-dither-interactive
IDENTITY: ordered 8×8 Bayer dither with mouse pixel-scale and retro bit-depth mix
KEEP VERBATIM: bit_depth / contrast / dither_spread / pixel_scale; bayer8 table; neighbor error; phosphor mask; existing scanline
ADD:
  1. Interleaved-gradient-noise assist mixed into the Bayer threshold (still ordered dither)
  2. Channel-rotated Bayer — G shifted +4, B shifted +2 (classic color dither, not CA costume)
FORBID: springs, treating existing scanline/CA as the upgrade
A PACKING: ACES display RGBA (HEAD packed telemetry; C unused — fix)

---

SHADER: halftone
IDENTITY: AM elliptical CMYK/mono screens with press misregistration and paper fibre
KEEP VERBATIM: dotScale / contrast / colorMode / screenAngle; ellipDot; plate offsets; paperGrain
ADD:
  1. Highlight skip — high luma punches a hole in the screen (newsprint shine)
  2. Overprint gain — dots swell where CMYK plates overlap (print gain, not extra CA)
FORBID: springs, Wave Halftone rosette, more misregistration as the upgrade
A PACKING: ACES display RGBA (HEAD already writes display)

---

SHADER: adaptive-mosaic
IDENTITY: depth-adaptive square tiles, finer near the mouse, grout bevel, C persistence
KEEP VERBATIM: tile_size / depth_blend / bevel_width / audio_sensitivity; mouse focus shrink; exact C mix; existing grout runners
ADD:
  1. Local-variance subdivision — high-contrast coarse cells use a finer grid (adaptive mosaic)
  2. Mortar mix from 4-neighbor tesserae (grout picks up adjacent tile color)
FORBID: new springs, IQ palettes, replacing tiles with Voronoi as the whole look
A PACKING: display RGBA (C is color history — keep)

---

SHADER: crystal-mosaic
IDENTITY: triangular crystal tiles that rotate near the mouse, with existing refraction/caustics/fresnel stack
KEEP VERBATIM: density / rotation / chroma / influence; triangle grid; existing lighting; mouse rotate
ADD:
  1. Facet crease — rhombus splits into two flat faces along u=v (mosaic geometry, not more sparkle)
  2. Lead came — dark grout at triangle borders (stained-glass mosaic)
FORBID: extra CA, extra springs, IQ palette, more caustics as the upgrade
A PACKING: ACES display RGBA (HEAD wrote premultiplied display; C unused)

---

SHADER: cyber-halftone-scanner
IDENTITY: rotated CMYK-style screens swept by a scanline with click bursts
KEEP VERBATIM: scale / speed / separation / brightness; 15/75/0/45 angles; scan/glitch/burst/mouse bloom
ADD:
  1. AM circular cells under the existing rotated screens (replace sin×sin grid, keep angles)
  2. Scan hard-dot — under the scanline the AM threshold goes binary (scanner exposing the plate)
FORBID: new springs, Wave Halftone ellipse/rosette, replacing the scanner with a still print
A PACKING: ACES display RGBA (HEAD already writes display)

---

SHADER: posterize-neon-edges
IDENTITY: luma posterize plus Sobel neon edges
KEEP VERBATIM: levels / edge_threshold / glow_intensity / hue_shift; Sobel; hue-preserving quantize; neonHue; existing FBM band noise
ADD:
  1. Band-hold flats — FBM noise dies in the band interior so cel cells stay flat
  2. Ridge neon — glow is a thin Sobel-magnitude ridge, not isotropic bloom
FORBID: springs, IQ overlay, replacing posterize with a different filter
A PACKING: ACES display RGBA (HEAD already)

---

SHADER: color-channel-weave
IDENTITY: RGB sampled as warp/weft fabric threads with over-under weave
KEEP VERBATIM: thread_spacing / weave_angle / shadow_depth / chroma_offset; existing extraBuffer[133..138] spring; pluck; warp/weft tints; leftover B write
ADD:
  1. Two-ply twist — each yarn is two offset fibers (textile, not extra chroma)
  2. Exact-C under-thread ghost — previous weft shows through gaps (weave occlusion)
FORBID: adding more springs, replacing weave with a liquid
A PACKING: display RGBA; keep leftover B write
