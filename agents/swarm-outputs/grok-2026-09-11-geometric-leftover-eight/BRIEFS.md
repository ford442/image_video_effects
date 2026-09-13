# Geometric leftover eight — Idea Cards (written before WGSL)

Family: leftover hyperbolic / grid / zipper / field / contour. Two native ideas each. No spring+ripple+IQ stamp. Existing springs/click on cyber-grid and neon-topology kept.

Skipped: overlay-rich geometric (`digital-crease`, `interactive-origami`, `ascii-glyph`, `neon-quantum-lattice`, kaleido clones); lighting leftover ten; Batch 56 warp-drive; elastic-chromatic IQ overlay.

---

SHADER: hyperbolic-dreamweaver
IDENTITY: photo warped through a Poincaré disk (hyperbolic translate + rotate)
KEEP VERBATIM: hyperbolicDist / hyperbolicTranslate; JSON tile_count / curvature / aberration / glow_intensity (remap WGSL to those roles)
ADD:
  1. Angular tiling from tile_count (sector wrap — JSON already advertised this)
  2. Radial chromatic split in curved space (aberration) plus geodesic glow rings (glow_intensity)
FORBID: treating the existing clockRings/IQ spectral overlay as the upgrade — strip it
A PACKING: ACES display RGBA (HEAD never wrote A)

---

SHADER: hyperbolic-dreamweaver-julia
IDENTITY: quaternion Julia raymarched through Poincaré-warped camera
KEEP VERBATIM: zoom / morph_speed / color_cycles / detail; quaternionJuliaDE 12-iter; mouse orbit
ADD:
  1. Photo albedo on the hit surface (sample readTexture at projected hit)
  2. Horocycle fog from hyperbolicDist (farther in the disk fades to photo)
FORBID: zoom_config.x as audio — use plasmaBuffer. No new springs
A PACKING: ACES display RGBA (HEAD stored pre-ACES col in A; C unused)

---

SHADER: mouse-hyperbolic-navigator
IDENTITY: mouse Möbius navigation of a Poincaré disk with angular tiling
KEEP VERBATIM: navigationSpeed / tileCount / edgeGlow / zoomFactor; mobiusDisk; click hyperbolic waves
ADD:
  1. Horocycle rings at constant hyperbolic radius
  2. Tile mortar — darken the angular wrap seam
FORBID: new springs
A PACKING: ACES display RGBA (HEAD never wrote A). Early-out void also writes A.

---

SHADER: voxel-grid
IDENTITY: raymarched occupancy voxels that rotate toward the mouse
KEEP VERBATIM: grid / radius / strength / gap; rayBox; occupancy hash; exact-C trail; existing spring-free mouse
ADD:
  1. Mortar AO in the cell_gap (darken sdBox rim)
  2. Axis-face tint — dominant normal axis tints from a neighbor cell sample
FORBID: new springs; replacing occupancy with a different renderer
A PACKING: ACES display RGBA (HEAD already)

---

SHADER: cyber-grid-pulse
IDENTITY: glowing cyber grid that distorts toward a sprung mouse
KEEP VERBATIM: four params; extraBuffer[133..138] spring; click warp; gridMask
ADD:
  1. Half-cell dual lattice (vertex dots at cell corners)
  2. Traveling packet along X lines (fract(time) bright blob)
FORBID: a second spring; IQ palette as the whole look
A PACKING: ACES display RGBA (HEAD stored unmapped RGB — add ACES)

---

SHADER: zipper-reveal
IDENTITY: V-opening zipper with metal teeth revealing under-fabric
KEEP VERBATIM: spread / tooth_size / angle / tooth_amplitude; rotate local; weave; spec metal
ADD:
  1. Slider puller at the zipper head (mouse y)
  2. Staggered L/R teeth (odd rows offset)
FORBID: springs
A PACKING: ACES display RGBA (HEAD already)

---

SHADER: quantum-field-visualizer
IDENTITY: two-slit wavefunction, mouse measurement collapse, photo mix
KEEP VERBATIM: observation_strength / fluctuation_speed / energy_level / uncertainty; real/imag psi; HSV from phase
ADD:
  1. Literal barrier with two gaps (mask the wave behind a wall except slits)
  2. Held-only collapse (zoom_config.w gates measurement)
FORBID: springs
A PACKING: ACES display RGBA

---

SHADER: neon-topology
IDENTITY: glowing contour map of depth, mouse lens bump, click quakes
KEEP VERBATIM: density / height / mouse / glow; lens; quakes; major contours
ADD:
  1. Slope hachures — short ticks along the depth gradient between contours
  2. Hypsometric fill — band tint between contour levels
FORBID: new springs; cloning pulse-edge HSV tubes
A PACKING: ACES display RGBA
