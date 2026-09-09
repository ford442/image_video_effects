# Weather / wind / condensation ten — Idea Cards (written before WGSL)

Family: snowfall, rain-ripple height fields, bubble-wrap membranes, hanging wind-chime strips, buoyancy smoke, saturation auras, pixel wind, LiDAR ranging, and rain-lens wipe. Native ideas only. No spring+ripple+IQ stamp. Springs kept only where HEAD already owned them (none of these except rain-lens-wipe’s existing click wipe fronts). radiating-haze / radiating-displacement Uniforms order canonicalized so JSON sliders land on `zoom_params`.

---

SHADER: snow
IDENTITY: layered hexagonal snowflakes falling with wind, plus snow that accumulates on upward-facing depth
KEEP VERBATIM: speed / density / wind / accumulation params; hex snowflake SDF; three depth layers; up-facing accumulation; melt
ADD:
  1. Flake tumble — each crystal rotates by seed×time so hex arms spin as they fall
  2. Land fade — falling flakes dim where C already holds accumulation (they settle, they don’t punch through the bank)
FORBID: springs, IQ palettes, replacing hex flakes with noise blobs
A PACKING: accumulation in A.r (raw field). Do not ACES the stored bank. Display is ACES RGB.

---

SHADER: raindrop-ripples
IDENTITY: Verlet height-field raindrops with a mouse shield that damps and wakes
KEEP VERBATIM: intensity / decay / speed / shield params; height+prev packing; mouse shield + rim wake
ADD:
  1. Wave-speed in the Laplacian (speed slider was assigned and unused — it is the c² of this pond)
  2. Slope caustic sparkle — second-difference focusing, not a new specular costume
FORBID: springs, replacing the height field with display-history sparkles
A PACKING: raw height / prev-height in A.rg (HEAD). Exact C loads. ACES on display only.

---

SHADER: bubble-wrap
IDENTITY: poppable dome cells that stay popped, with refraction and specular
KEEP VERBATIM: scale / popStrength / refraction / highlight (JSON still named Unused); pop timestamp; elastic collapse; wrinkle; burst ring
ADD:
  1. Hex packing — odd rows offset ½ cell (this is bubble wrap, not a square grid)
  2. Neighbor sympathetic pop — if two hex neighbors are already popped, this dome weakens and can go
FORBID: new springs, IQ palettes, replacing domes with liquid solver
A PACKING: popped flag + pop time in A.rg (HEAD). Exact C. Display ACES RGBA.

---

SHADER: pixel-wind-chimes
IDENTITY: hanging vertical photo strips that pendulum-sway from a top hinge, mouse-repelled
KEEP VERBATIM: strip_count / sway / wind_speed / gap; top-pivot rotate; mouse Gaussian push; per-strip source remap
ADD:
  1. Hinge specular — bright catch at the top pivot (chime hardware, not a bloom overlay)
  2. Closest-Z strip sort — overlapping swings keep the nearer strip (the comment already wanted this)
FORBID: springs, IQ palettes, turning strips into a particle field
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: sim-smoke-trails
IDENTITY: bottom-and-mouse seeded smoke with buoyancy, curl, and fire-tint at heat
KEEP VERBATIM: density / turbulence / rise / dissipation; A = density, temp, vel.xy; bottom + mouse + ripple seeds
ADD:
  1. Vorticity confinement — curl stretched by local vorticity so billows keep their spin (header claimed it; force was just curl add)
  2. Altitude cooling — temperature drops as smoke rises so the fire tint dies with height
FORBID: IQ palettes, extraBuffer springs, ACES on stored fields
A PACKING: raw density/temp/vel (HEAD). Exact C. ACES display only.

---

SHADER: radiating-haze
IDENTITY: animated aura around saturated colours; neutrals (browns/greys/blacks) stay unaura’d
KEEP VERBATIM: speed / intensity / satThresh / radius JSON roles; HSV neutral test; persist in A.r
ADD:
  1. Neighbor-bleed corona — 4-neighbor saturation lets the aura extend off the patch
  2. Mouse-origin waves — rings travel from the cursor (JSON already claims mouse-driven)
FORBID: springs, IQ palettes, Uniforms theft (canonicalize struct; extra colourMode from audio, not stolen sliders)
A PACKING: persist scalar in A.r (HEAD). Exact C. Display ACES.

---

SHADER: radiating-displacement
IDENTITY: displacement waves only on strong colours; neutrals stay sharp
KEEP VERBATIM: speed / strength / satThresh / radius; HSV neutral lock; click ripples already present
ADD:
  1. Spatial radiate from mouse — HEAD called `waveDisplacement(uv, uv)` so dist=0 (global pulse). Make it a real radial wave from the cursor
  2. Phase-split RGB sample of the same wave (tiny, same kernel — not a CA costume)
FORBID: springs, extra IQ, Uniforms theft (canonicalize so JSON sliders actually drive the wave)
A PACKING: ACES display RGBA (HEAD never wrote A; C unused)

---

SHADER: interactive-pixel-wind
IDENTITY: cursor-directed wind smear with turbulence curls and slower trailing history
KEEP VERBATIM: strength / turbulence / trails / shift; mouse windDir; fbm curls; existing CA from shift param
ADD:
  1. Luma-weighted advection — bright pixels blow farther (wind on specular, not a new palette)
  2. Wind shadow — sample luma upwind; occluded pixels get less offset
FORBID: more IQ palette, new springs, treating existing CA as the upgrade
A PACKING: ACES display RGBA (HEAD). Exact C history.

---

SHADER: lidar
IDENTITY: depth LiDAR with linear/radial/spiral beam, contours, Sobel edges, point cloud, echo
KEEP VERBATIM: speed / width / contours / edges; scan_pattern modes; point_cloud; height colour
ADD:
  1. Honest A echo — HEAD wrote echo to B and never A (engine A→C would kill it). Echo lives in A
  2. Range ticks — beam-local hash ticks along the scan, like a ranging reticle
FORBID: springs, IQ palettes, replacing the scan with a holographic overlay
A PACKING: echo in A.r (was B). Exact C. Display ACES. Mode from held (radial) / default linear — do not read time as mode.

---

SHADER: rain-lens-wipe
IDENTITY: falling lens drops + streak packets; mouse wipes an advected clean mask; clicks expand wipe fronts
KEEP VERBATIM: strength / decay / radius / density; rainDistortion cells; streakPacket; wipe state in A.r
ADD:
  1. Meniscus ridge — bright contact line at the wipe / wet boundary
  2. Bead runoff — leftover droplets hang just below a wiped region (gravity, not a new solver)
FORBID: new springs, IQ palettes, cloning snowflake SDFs onto the glass
A PACKING: wipe mask in A.r (HEAD). Exact C. Display ACES.
