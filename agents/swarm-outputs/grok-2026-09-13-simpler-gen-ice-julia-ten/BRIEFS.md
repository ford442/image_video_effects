# Grok-1 simpler generative ten — ice / IFS / moiré / inverse / iris / islamic / iso / Julia

Family: catalog generative math/ornament/city. Two native ideas each on leftovers. Identities kept. No new extraBuffer springs. Did not substitute IDs.

Claimed list: `gen-ice-crystal-lattice`, `gen-ifs-fractal-flame`, `gen-interference-moire-field`, `gen-inverse-mandelbrot`, `gen-iris-bloom-fractal`, `gen-islamic-geometric-tiling`, `gen-islamic-star-rose`, `gen-isometric-city`, `gen-julia-set` (`gen_julia_set.wgsl`), `gen-julia-set-classic`.

---

## SKIP — already idea-stamped 2026-09-09 (classic-gen-ten)

Do not edit WGSL/JSON. Do not bump `Upgraded:`. Cards live in `agents/swarm-outputs/grok-2026-09-09-classic-gen-ten/`.

| ID | Dated ideas already in header |
|---|---|
| `gen-ice-crystal-lattice` | secondary dendrite teeth; plate vs needle habit |
| `gen-interference-moire-field` | 6.8% density detune beat; two-source Young path-difference |
| `gen-iris-bloom-fractal` | collarette zigzag; Fuchs crypt pits near the pupil |
| `gen-islamic-geometric-tiling` | over-under strap shadow; half-angle girih dart |
| `gen-julia-set-classic` | exterior distance estimate; log\|z\| stripe coloring |

---

SHADER: gen-ifs-fractal-flame
IDENTITY: IFS flame density from four affine maps plus sin / spherical / swirl variations, warm flame palette, temporal trail
KEEP VERBATIM: Iterations / Spread / Heat / Chromatic Aberration roles; 4 affine picks; sin+spherical+swirl mix; gravity well; click burst; luma spawn; Beer-Lambert alpha
ADD (2 native ideas):
  1. Color-by-transform — flam3 color-speed from which of the four affine maps last fired, so the existing IFS tints the palette instead of density-only heat
  2. Final affine after each variation — small rotate+scale post-xform (flam3 final), fused into this loop, not a new solver
FORBID on this file: cloning Classic Fractal Flame log-density + spherical stamp; springs; IQ candy takeover
A PACKING: ACES display RGBA in A (C is previous display); bass envelope moves extraBuffer[0] → [133]
FLOOR (not an idea): extraBuffer[0] is engine-reserved — keep bass_env at [133]

---

SHADER: gen-inverse-mandelbrot
IDENTITY: color-space Mandelbrot — z0 from RGB-like noise, c from position, interior orbit-trap / exterior smooth dwell
KEEP VERBATIM: Iterations / Color Zoom / Colormap Rotate / Bailout Radius; z0 noise; interior trap; dwell bands; julia probe; escape-time normal; fbm interior; existing click ripples
ADD (2 native ideas):
  1. Pickover stalks on the color-space orbit — min(|Re z|, |Im z|) along THIS inverse iterate, not a position-space Julia rewrite
  2. Argument bands from arg(final_z) on escaped color vectors — binary decomposition of the color orbit, not log\|z\| stripes from Julia Classic
FORBID on this file: springs; replacing color-space z0 with a standard Mandelbrot; cloning Julia Classic DE+stripe
A PACKING: raw HDR display RGBA in A (ACES on writeTexture); C was unread — start honest display history

---

SHADER: gen-islamic-star-rose
IDENTITY: girih hex tessellation of φ-ratio pentagrams / n-gons with a central star-rose
KEEP VERBATIM: Pattern Complexity / Rotation / Zoom / Color Shift; hex cells; sd_star / sd_pentagram / φ inner radius; girih palette; mouse rotation override
ADD (2 native ideas):
  1. Nested φ pentagrams — a second star at outer/φ inside the same hex (this file already owns φ)
  2. 10-fold rose from 36° sectors around the central pentagram — the rose in the name, not a girih-dart clone of islamic-geometric-tiling
FORBID on this file: over-under strap + half-angle dart stamp from the 09-09 tiling upgrade; kaleido rewrite; springs
A PACKING: ACES display RGBA in A
FLOOR (not an idea): p1 Pattern Complexity was unread — wire extra strap / star-point range; exact textureLoad C; mouse UV is already 0–1

---

SHADER: gen-isometric-city
IDENTITY: orthographic isometric raymarch of a hashed building grid with neon windows and street traffic
KEEP VERBATIM: Density / Traffic Speed / Neon Glow / Building Height Scale; isometric rd; cell hash height; window grid; orange traffic pulses; mouse pan
ADD (2 native ideas):
  1. Setback terraces — podium + narrower tower on the same hashed cell (city massing, not a new scene)
  2. Window occupancy flicker — time-hashed lights on the existing window cells so occupancy breathes
FORBID on this file: springs; replacing the iso camera with a perspective flythrough; voxel-grid mortar stamp
A PACKING: ACES display RGBA in A (HEAD wrote no A)

---

SHADER: gen-julia-set (file `public/shaders/gen_julia_set.wgsl`)
IDENTITY: generalized Julia z^n+c with circle/line/cross orbit traps, smooth μ, cardioid-orbiting c
KEEP VERBATIM: Zoom / Exponent n / Trap Mode / Trap Scale; z^n+c; three traps; Lissajous c-morph; held-pointer c override; 2-sample AA; interior filaments
ADD (2 native ideas):
  1. Smooth trap-mode interpolation — lerp circle↔line↔cross along the existing Trap Mode slider instead of three hard bins
  2. Velocity trap — min|Δz| glow where the orbit stalls, extra orbit-trap channel on THIS solver
FORBID on this file: Pickover stalks (reserved for inverse-mandelbrot this batch); Julia Classic DE + log\|z\| stripes; springs
A PACKING: HEAD wrote telemetry (μ, trap, iter) into A while sampling C as color — lie. Fix to raw HDR display RGBA in A, exact textureLoad C, ACES on writeTexture
