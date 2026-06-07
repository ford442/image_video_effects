# Showcase Shader: gen-fractal-ember-lattice

## Concept
Hexagonal crystal lattice glowing like hot embers. Mouse click shatters the lattice into rigid shards that fly outward; release to watch them drift back and reform. Agent-swarm-synthesized design.

## Features
- generative, audio-reactive, mouse-driven, temporal, depth-aware
- upgraded-rgba, aces-tone-map, chromatic-aberration

## Parameters (zoom_params)
| # | ID | Name | Default | Mapping |
|---|----|------|---------|---------|
| x | glowIntensity | Glow Intensity | 0.4 | Edge glow multiplier |
| y | shardSize | Shard Size | 0.4 | Rigid shard grid size in pixels |
| z | latticeScale | Lattice Scale | 0.5 | Hex DF tiling density |
| w | sparkDensity | Spark Density | 0.3 | Treble-driven edge sparks |

## State Packing (dataTextureC → dataTextureA)
| Channel | Meaning |
|---------|---------|
| R | displacement X |
| G | displacement Y |
| B | shard seed (0–1) |
| A | reform progress (0=shattered, 1=reformed) |

## Audio Reactivity
- **bass** → edge glow intensity + chromatic strength
- **mids** → lattice scale breathing
- **treble** → shard-edge spark frequency

## Mouse Interaction
- **Mouse down**: shards explode outward from cursor with audio-boosted force and per-shard rotation
- **Mouse up**: exponential decay reform with per-shard stagger (0.987–0.992 decay)

## Validation
```bash
naga public/shaders/gen-fractal-ember-lattice.wgsl
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
```
All pass ✅

## Agent Swarm Credits
- Explore agent: identified gap in crystal+ember+shatter combination
- Coder agent (mechanic): designed rigid-grid shard state machine
- Coder agent (aesthetic): specified ember palette, hex DF lattice, audio mapping
