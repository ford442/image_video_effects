# Liquid and vortex batch notes

The two named additions per shader are listed in BRIEFS.md and marked by the
corresponding variables or expressions in each shader. The previous kernels,
modes and simulation packing remain in place.

- `gen-chromatic-acid-drip`: `rivulet` and `bubbles`; A remains HDR color.
- `gen-liquid-metal-cymatic-resonator`: `radialBeat` and `crestRidge`; A remains display color.
- `vortex-warp`: `inflow` and `depthRetention`; A remains display color.
- `gen-von-karman-vortex`: `dyePacket` and `shearRibbon`; A remains display color.
- `gen-quantum-liquid-metal-chronosphere`: product of capillary modes and `liquidRim`; A remains display color.
- `interactive-magnetic-ripple`: `convergence` and `compression`; A remains raw envelope, pointer and ripple state.
- `gen-quantum-liquid-gold-cymatic-vortex`: `overtone` and `crestGlint`; A remains HDR color.
- `liquid_magnetic_ferro`: `meniscus` and `striation`; A remains raw magnetic field state.
- `liquid-time-warp`: `stretchedHistory` and `depthRetention`; A remains display color and B remains flow diagnostics.
- `gen-volcanic-ink`: `settledAsh` and `fissureCore`; A remains linear ink history and B retains diagnostic fields.

The two depth-retention masks compare the current depth at the destination and
the current depth at the advected source; they do not claim a stored depth history.
Six pasted binding headers were migrated with the repository script. The magnetic
ripple shader now respects the saved decay, field strength and chromatic split
roles, and no longer interprets its raw state channels as previous-frame color.
The vortex street and volcanic ink definitions had no runtime `params`; the four
controls documented in their existing upgrade metadata are now exposed.

Naga WASM, the targeted precommit binding/workgroup gate, the extraBuffer and
dead-slider audits, definition validation, the foundation gates and the production
build passed. The prelude tracker was regenerated to remove entries for files that
already included the prelude. Each of the ten expanded shaders also compiled
into a compute pipeline on a SwiftShader WebGPU device.
Full-suite and global prelude-gate limitations are recorded in the coordinator
review. Visual quality, interaction and performance still need real-GPU review.
