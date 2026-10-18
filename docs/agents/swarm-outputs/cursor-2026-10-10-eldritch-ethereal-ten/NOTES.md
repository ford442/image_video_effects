## Notes — Eldritch/Ethereal Ten (2026-10-10)

- `gen-eldritch-quantum-fractal-eye`
  - Kept: raymarched eye anatomy, fractal iris, dilation, and plasma-vein response.
  - Added: limbal crypt spokes; nictitating membrane sweep shadow.
  - A packing: ACES display RGBA history.

- `gen-eldritch-tesseract-hive-mind`
  - Kept: 4D tesseract fold language, voxel tearing, sentinel swarm traffic.
  - Added: hypercube seam runes; brood pulse nodules on corner junctions.
  - A packing: raw HDR trail RGB + depth in A.a.

- `gen-ethereal-bismuth-resonance-void-owl`
  - Kept: eased singularity, resonance envelope, stepped bismuth shell, hopper eyes.
  - Added: facial-disk diffraction rings; auricular notch glints.
  - A packing: HDR display history RGB + semantic alpha.

- `gen-ethereal-chrono-plasma-void-manta`
  - Kept: spring-banked manta body, flap modulation, chrono-plasma wing behavior.
  - Added: cephalic-fin vortex streaks; ventral gill-slit pulses.
  - A packing: ACES display RGBA history.

- `gen-ethereal-cyber-chrono-nebula-phoenix`
  - Kept: orbit-trap/nebula body language, wing filament and ember-tail systems.
  - Added: crest-crown ion arcs; talon wake contrails.
  - A packing: raw telemetry RGBA in A.

- `gen-ethereal-cyber-plasma-void-dragon`
  - Kept: segmented spine, crystalline armor, breath jet, halo structures.
  - Added: dorsal spine plasma pennants; jawline arc-weld filaments.
  - A packing: ACES display RGBA in A.

- `gen-ethereal-quantum-holographic-fractal-coral`
  - Kept: fractal coral body, polyp mouth pits, interior symbiont glow pulse.
  - Added: calcification growth-ring terraces; branch-tip polyp biolight flicker.
  - A packing: ACES display RGBA.

- `gen-ethereal-chrono-fluid-symbiote`
  - Kept: fluid/crystal dual-material model, seam meniscus, chrono smear.
  - Added: peristaltic vein bands; crystal twinning shear planes.
  - A packing: ACES display RGBA (exact C read).

- `gen-ethereal-cyber-chrono-void-whale`
  - Kept: ribbed skeletal whale core, temporal streams, sonar and mist behavior.
  - Added: pectoral fin-ray fans; ventral throat-pleat shimmer.
  - A packing: ACES display RGBA in A.

- `gen-emergent-calligraphic-ecosystems`
  - Kept: calligraphic growth flow, predator-prey ink ecology, death/rebirth cycle.
  - Added: capillary backrun blooms; ligature bridge strokes.
  - A packing: ACES display RGBA.

## Gates

- Prelude migration: migrated 7, skipped 3, no refusals.
- Scoped naga wasm: 10/10 valid.
- Scoped precommit gate: 10/10 pass (bindgroup + workgroup + extraBuffer checks).
- `audit:dead-sliders` scoped to these IDs: pass.
- `audit:extrabuffer`: pass (no new violations).
- `generate_shader_lists` + duplicate check: pass.
- Jest (`npm test -- --watchAll=false --ci`): pass (`134` suites; `1033` passed, `1` skipped).
- Build (`SKIP_WASM_BUILD=1 npm run build`): pass.
