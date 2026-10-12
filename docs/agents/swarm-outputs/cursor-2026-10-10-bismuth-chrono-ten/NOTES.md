## Notes — Bismuth + Chrono Ten (2026-10-10)

- `gen-bismuth-crystal-citadel`
  - Kept: terrace wall/step architecture, melt pool + beacon reflection model, slider mappings.
  - Added: terrace-index hopper striae; sixfold pinnacle cathodoluminescent arcs.
  - A packing: HDR RGB + semantic alpha (history read from exact C, ACES on display only).

- `gen-bismuth-hyper-crystals`
  - Kept: nucleation seed, fractional fold interpolation, lineage-driven iridescence.
  - Added: crystal twinning seam highlights; lineage-phased Bragg scintillation.
  - A packing: HDR RGB + semantic alpha.

- `gen-celestial-clockwork-plasma-loom`
  - Kept: keplerian gear rings, over/under thread motif, shuttle transport, material split.
  - Added: meshing ratchet sparks (`ctx.spark`); catenary sag in thread bays.
  - A packing: ACES display RGBA + semantic alpha with exact-C temporal blend.

- `gen-celestial-nanite-swarm-nebula`
  - Kept: Kuramoto blink field, lattice docking, face-dust extinction, volumetric integration.
  - Added: shepherd-ring traffic lanes around cursor; quorum-front amber ignition pulses.
  - A packing: ACES display RGBA + semantic alpha.

- `gen-celestial-yggdrasil-matrix`
  - Kept: KIFS branch identity, phyllotactic buds, counterflow sap channels.
  - Added: xylem-style radial growth rings; mycorrhizal junction node halos.
  - A packing: ACES display RGBA + semantic alpha.

- `gen-chromatic-singularity-loom`
  - Kept: gravity-warped thread loom, parity families, orbital infall trail from C.
  - Added: ergosphere azimuth shear bands; mass-scaled photon-ring caustics.
  - A packing: HDR RGB + semantic alpha.

- `gen-chrono-kinetic-fractal-engine`
  - Kept: 4D fold engine, escapement/backlash logic, iridescent palette path.
  - Added: torsion-shaft filament bands; flyball-governor radial flare spokes.
  - A packing: ACES display RGBA + semantic alpha.

- `gen-chronodynamic-aether-weaver-automata`
  - Kept: Rule-90 gear automata and capstan-wrap thread architecture.
  - Added: differential-cage planet-arm precession; bobbin charge knots on wrapped thread/rim contact.
  - A packing: HDR RGB + semantic alpha with exact-C echo/smear history.

- `gen-chronos-biomechanical-void-leviathan`
  - Kept: phase-lag swim body, rib/wake glow structure, volumetric tail wake.
  - Added: fluttering pectoral membrane fins in SDF; snout electroreceptor pore sparks.
  - A packing: ACES display RGBA + semantic alpha.

- `gen-chronomorphic-glass-tesseract`
  - Kept: 4D rotation + tesseract SDF, birefringent refraction paths, W-face caustics.
  - Added: schlieren-like shear stress lines; corner total-internal-reflection flashes.
  - A packing: ACES display RGBA + semantic alpha.

## Gates

- Scoped naga wasm: 10/10 valid.
- `audit:dead-sliders` scoped to these 10 IDs: pass.
- `audit:extrabuffer`: pass (no new violations).
- `generate_shader_lists` + `check_duplicates`: pass.
- `npm test -- --watchAll=false --ci`: pass.
- `SKIP_WASM_BUILD=1 npm run build`: pass.
