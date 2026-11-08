SHADER: gen-fractal-ember-lattice (2nd pass)
IDENTITY: hot triangular/hex ember lattice; click shatters into rigid shards that reform
KEEP VERBATIM: shard state machine + A packing, palette, existing 6 ideas
ADD:
  7. Bellows gust front — slow diagonal draught pushing lines/junctions to white heat, cores warmer
  8. Rising ash flecks — screen-space grey flakes drifting up with sway; rare ones glow (bass)
RESCUES:
  - Fresh C (all zero) = reform 0 → shader booted fully "shattered" for ~1.5 s (and forever in short thumb captures). Now treated as solid.
  - Shard boundary glow was inverted (1-smoothstep) → whole shards washed white-grey while shattered; now rim-only.
Stats (384px, 20f, t=3, defaults): before meanL .42 grey wash → after .141 ember-dark; held click .54 wash → .26 legible shards.
Open: composite still lets ~10% input through lines (alpha ≤0.9), pre-existing.
