# Generative Hyper / Geometry Batch Upgrade

Five existing effects were upgraded in place:

- `gen-hyper-rainbow-vortex`: corrected normalized mouse coordinates while
  retaining layered Rankine flow and adding vortex-energy depth.
- `gen-hyper-refractive-rain-matrix`: gained exact A/C rain history,
  effect-specific controls, three-band fluid/caustic response, and input-aware
  depth while preserving pointer repulsion.
- `gen-hyper-warp`: retained the legacy `gen_hyper_warp.*` path, stabilized
  flow advection, and held-pointer warp while correcting audio-band reads.
- `gen-hyperbolic-crystal-symbiosis`: retained hyperbolic translation,
  competing crystals, and advected trails with truthful raw HDR history.
- `gen-hyperbolic-tessellation`: all four controls now drive symmetry,
  recursive-depth color, rotation, and boundary glow.

Five independent effects were added under the requested exact IDs:

- `gen-ice-crystal-lattice`: hexagonal frost branches, held nucleation, and
  click fracture fronts.
- `gen-interference-moire-field`: crossed analytic line fields, phase warping,
  and circular interference pulses.
- `gen-iris-bloom-fractal`: recursive polar petals, iris aperture, pupil, and
  vein detail.
- `gen-islamic-geometric-tiling`: interlaced star polygons, rosettes, and
  gilded click waves.
- `gen-julia-set-classic`: escape-time Julia iteration, orbit traps, and
  held-pointer control of complex C.

All ten declare the canonical bindings 0–12, dispatch at 16×16×1, load C with
exact integer `textureLoad`, write temporal history only to A, retain raw HDR
RGBA in A/C, use ACES only for display RGB, produce semantic alpha and depth,
respond to bass/mids/treble, and expose four live named parameters.
