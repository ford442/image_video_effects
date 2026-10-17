## Notes — Cosmic/Crystalline/Cyber Ten (2026-10-10)

- `gen-cosmic-clockwork-dyson-sphere`
  - Kept: clockwork brass lattice, conduit medium, core-light/shadow system.
  - Added: eclipse-shutter crowns; meridian radiator fins with polar blueing.
  - A packing: ACES display RGBA history.

- `gen-crystalline-chrono-dyson`
  - Kept: statites, packet conduits, louvred shell, quasar core interactions.
  - Added: chronometer tick-crowns; quartz twinning seam highlights.
  - A packing: HDR RGB + semantic alpha history.

- `gen-crystalline-nebula-weaver-forge`
  - Kept: base KIFS forge body, nebula layering, core/refraction controls.
  - Added: forge-jet plasma plumes; loom-shuttle filaments through fold planes.
  - Also aligned output to ACES display RGBA in `dataTextureA` (removed debug A payload).

- `gen-crystalline-nebula-weaver-void-spider`
  - Kept: metachronal spider gait, dragline sag, nebula-condensed node model.
  - Added: orb-web spoke/capture-spiral overlays; dragline dewdrop caustic beads.
  - A packing: HDR RGB + semantic alpha history.

- `gen-cyber-organic-void-mycelium-pulsar`
  - Kept: axis-tube network, node glow, spore pulse behavior.
  - Added: rhizomorphic root-fan branch capsules; electroplaque ring discharges.
  - A packing: ACES display RGBA.

- `gen-cybernetic-crystalline-neuro-lattice`
  - Kept: nucleation front + bit-memory logic + light-piped links.
  - Added: braided axonal bundles in gyroid links; synaptic vesicle burst flares.
  - A packing: HDR RGB + semantic alpha history.

- `gen-cybernetic-liquid-chrome-engine`
  - Kept: V8 firing order, compression ignition, ignition heat shimmer feedback.
  - Added: camshaft lobe timing notches; exhaust-manifold blueing bands.
  - A packing: HDR RGB + semantic alpha history.

- `gen-cybernetic-plasma-orchid-nexus`
  - Kept: full orchid anatomy stack and existing lip/column/pollinia/sepal system.
  - Added: anther-filament whisker tethers; serrated petal-edge corona.
  - A packing: ACES display RGBA.

- `gen-cryogenic-frost-plasma-matrix`
  - Kept: cryogenic/plasma dual material, seam sublimation, fog and shock integration.
  - Added: rime-plate terracing; plasma-tongue seam licks.
  - A packing: HDR RGB + semantic alpha history.

- `gen-cybernetic-mycelium-neural-web`
  - Kept: spring cursor safe-zone state, refractory behavior, neighbor-history coupling.
  - Added: saltatory conduction leaps; astrocyte calcium halos.
  - A packing: ACES display RGBA feedback.

## Gates

- Scoped naga wasm: 10/10 valid.
- Scoped precommit gate: 10/10 pass (bindgroup + workgroup + extraBuffer checks).
- `audit:dead-sliders` scoped to these IDs: pass.
- `audit:extrabuffer`: pass (no new violations).
- `generate_shader_lists` + duplicate check: pass.
- Jest (`npm test -- --watchAll=false --ci`): pass.
- Build (`SKIP_WASM_BUILD=1 npm run build`): pass.
