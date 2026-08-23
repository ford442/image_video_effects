# Codex Fractal / Gravity Generative Batch

Upgraded ten existing effects in place while preserving their visual identities:

- `gen-fractal-clockwork`: interlocking raymarched brass gears and sprung orbit.
- `gen-fractal-ember-lattice`: rigid shard state over a hot triangular lattice.
- `gen-fractured-monolith`: levitating stone fragments with a luminous core.
- `gen-galactic-aether-crystal-geode-core`: KIFS crystals around an aether core.
- `gen-ghost-flame`: advected temperature/fuel ghost-fire simulation.
- `gen-glacial-aether-quantum-cavern`: raymarched crystalline ice cavern.
- `gen-glass-mosaic-liquid-refraction`: flowing Voronoi stained-glass refraction.
- `gen-gravitational-ferrofluid-singularity-engine`: spiked magnetic horizon fluid.
- `gen-gravitational-strain`: bounded multi-well geodesic strain field.
- `gen-gravito-phononic-accretion`: audio-sculpted multi-body accretion disks.

Every shader uses all 13 bindings, a 16×16×1 workgroup, exact integer
`textureLoad` feedback from `dataTextureC`, writes feedback only to
`dataTextureA`, responds to bass/mids/treble, produces semantic display alpha,
and applies ACES tone mapping. Every definition exposes four named live controls.
