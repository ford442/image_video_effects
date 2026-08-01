# `u.config.y` misuse audit

`config = [time, rippleCount, resW, resH]` — see `src/contracts/uniforms_layout.json`.
Every row below reads `config.y` (or a legacy `config` swizzle) as something else.

**Total: 118 reads across 92 shaders**

| Category | Count |
|----------|-------|
| `audio` | 68 |
| `unclassified` | 22 |
| `click_or_frame_count` | 15 |
| `delta_time` | 12 |
| `resolution` | 1 |

## Findings

| File | Line | Category | Code |
|------|------|----------|------|
| `public/shaders/4d-projection-dream-weavers.wgsl` | 131 | delta_time | `let dt = clamp(u.config.y, 0.001, 0.05);` |
| `public/shaders/acoustic-string-theory.wgsl` | 92 | delta_time | `let dt = clamp(u.config.y, 0.001, 0.05);` |
| `public/shaders/alpha-em-field-simulation.wgsl` | 131 | click_or_frame_count | `let clickParity = select(-1.0, 1.0, u.config.y % 2.0 < 1.0);` |
| `public/shaders/aurora-rift-pass2.wgsl` | 153 | unclassified | `let globalIntensity = clamp(u.config.y, 0.1, 1.5);` |
| `public/shaders/cellular-automata-3d.wgsl` | 167 | audio | `let audioOverall = u.config.y;` |
| `public/shaders/cellular-automata-3d.wgsl` | 168 | audio | `let audioBass = u.config.y * 1.2;` |
| `public/shaders/chronos-brush.wgsl` | 56 | click_or_frame_count | `let clickCount = u.config.y;` |
| `public/shaders/cyber-rain.wgsl` | 87 | delta_time | `let dt = u.config.y;` |
| `public/shaders/datamosh.wgsl` | 131 | click_or_frame_count | `let frame_count = u.config.y;` |
| `public/shaders/dla-crystals.wgsl` | 93 | click_or_frame_count | `let frame = u.config.y;` |
| `public/shaders/elastic-chromatic.wgsl` | 167 | delta_time | `let dt = clamp(u.config.y, 0.001, 0.05);` |
| `public/shaders/gen-abyssal-chrono-coral.wgsl` | 164 | click_or_frame_count | `let clickCount = u.config.y;` |
| `public/shaders/gen-abyssal-leviathan-iridescence.wgsl` | 145 | unclassified | `g_audio = u.config.y * 0.1;` |
| `public/shaders/gen-abyssal-leviathan-scales.wgsl` | 134 | audio | `g_audio = u.config.y * 0.1; // u.config.y accumulates clicks/beats` |
| `public/shaders/gen-abyssal-quantum-leviathan-skeleton.wgsl` | 69 | audio | `let audio_react = u.zoom_params.w * u.config.y; // 1.0 default` |
| `public/shaders/gen-abyssal-quantum-leviathan-skeleton.wgsl` | 183 | audio | `color += vec3<f32>(0.5, 0.0, 1.0) * marrow_intensity * (1.0 + audio_pulse * u.config.y);` |
| `public/shaders/gen-astro-mechanical-quantum-furnace-engine.wgsl` | 191 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-auroral-ferrofluid-monolith.wgsl` | 220 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-bismuth-singularity-loom-engine.wgsl` | 59 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-bismuth-singularity-loom-engine.wgsl` | 167 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-celestial-quantum-glass-dragonfly.wgsl` | 155 | audio | `let audio = u.config.y * 2.0;` |
| `public/shaders/gen-celestial-quantum-glass-dragonfly.wgsl` | 202 | audio | `let audio = u.config.y * 2.0;` |
| `public/shaders/gen-cellular-automata-tapestry.wgsl` | 89 | delta_time | `let dt = 1.0 + u.config.y * 0.5;` |
| `public/shaders/gen-chromatic-singularity-loom.wgsl` | 104 | audio | `let audio_intensity = u.config.y;` |
| `public/shaders/gen-chrono-kitsune-prism-weaver.wgsl` | 109 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-chronodynamic-aether-weaver-automata.wgsl` | 81 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-depth-refracted-liquid-stained-glass.wgsl` | 78 | unclassified | `a += u.config.x * 0.2 + u.config.y * 0.5;` |
| `public/shaders/gen-depth-refracted-liquid-stained-glass.wgsl` | 102 | unclassified | `let depth_mod = sin(u.config.x * 2.0 + u.config.y * 3.0) * 0.5 + 0.5;` |
| `public/shaders/gen-eldritch-tesseract-hive-mind.wgsl` | 138 | resolution | `let resolution = vec2<f32>(u.config.x, u.config.y);` |
| `public/shaders/gen-ethereal-anemone-bloom.wgsl` | 338 | audio | `let audio_pulse = plasmaBuffer[0].x; // was u.config.y (MouseClickCount)` |
| `public/shaders/gen-ethereal-aurora-ghost-orchid.wgsl` | 154 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-ethereal-chrono-plasma-void-manta.wgsl` | 131 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-ethereal-chrono-plasma-void-manta.wgsl` | 169 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-ethereal-cyber-aurora-hummingbird-core.wgsl` | 184 | audio | `let audio = u.config.y * 2.0 + 1.0;` |
| `public/shaders/gen-ethereal-cyber-chrono-void-whale.wgsl` | 113 | unclassified | `let core_pulse = sin(time * 2.0) * 0.1 + u.config.y * 0.5;` |
| `public/shaders/gen-ethereal-cyber-plasma-void-dragon.wgsl` | 196 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-fireworks-nocturne.wgsl` | 137 | delta_time | `let dt = max(u.config.y, 0.001);` |
| `public/shaders/gen-fractured-monolith.wgsl` | 72 | audio | `let audioOverall = u.config.y;` |
| `public/shaders/gen-fractured-monolith.wgsl` | 73 | audio | `let audioBass = u.config.y * 1.2;` |
| `public/shaders/gen-galactic-aether-crystal-geode-core.wgsl` | 107 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-galactic-aether-crystal-geode-core.wgsl` | 220 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-glacial-aether-quantum-cavern.wgsl` | 44 | unclassified | `let qxy = q.xy * rotate(u.config.x * 0.1 + u.config.y * 0.5);` |
| `public/shaders/gen-glacial-aether-quantum-cavern.wgsl` | 107 | unclassified | `let fracture = fract(length(p) * u.zoom_params.z * 5.0 + u.config.y * 2.0);` |
| `public/shaders/gen-glacial-aether-quantum-cavern.wgsl` | 110 | audio | `+ vec3<f32>(0.2, 0.8, 1.0) * step(0.95, fracture) * (u.config.y + treble) * depth_fade;` |
| `public/shaders/gen-glacial-aether-quantum-cavern.wgsl` | 113 | audio | `col += vec3<f32>(0.2, 0.5, 0.6) * (u.config.y + bass * 0.5) * 0.1;` |
| `public/shaders/gen-kinetic-neo-brutalist-megastructure.wgsl` | 94 | unclassified | `pos.x += sin(u.config.x * 0.5 + u.config.y) * 2.0;` |
| `public/shaders/gen-liquid-neon-cyber-metropolis.wgsl` | 96 | audio | `let audioAmp = u.config.y * u.zoom_params.z;` |
| `public/shaders/gen-luminescent-aether-plasma-nebula-koi.wgsl` | 175 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-luminescent-chrono-fluid-astrolabe.wgsl` | 141 | unclassified | `let uv = (vec2<f32>(id.xy) * 2.0 - vec2<f32>(u.config.xy)) / u.config.y;` |
| `public/shaders/gen-luminescent-cyber-chrono-void-turtle.wgsl` | 211 | audio | `audioVal = u.config.y;` |
| `public/shaders/gen-luminescent-quantum-glass-phoenix-egg.wgsl` | 131 | unclassified | `let base = length(p) - 0.7 - u.config.y * 0.3;` |
| `public/shaders/gen-luminescent-quantum-glass-phoenix-egg.wgsl` | 158 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-luminescent-quantum-void-anglerfish.wgsl` | 79 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-luminescent-quantum-void-anglerfish.wgsl` | 143 | unclassified | `let shockwave = clamp(sin(t * 10.0) * exp(-fract(u.config.y)), 0.0, 1.0);` |
| `public/shaders/gen-luminescent-quantum-void-astral-turtle.wgsl` | 211 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-neon-plasma-biomechanical-hive.wgsl` | 136 | audio | `let audio = u.config.y * 2.0;` |
| `public/shaders/gen-neuro-kinetic-liquid-gold-lotus.wgsl` | 150 | audio | `let audio_val = u.config.y; // Simplified audio metric` |
| `public/shaders/gen-obsidian-echo-chamber.wgsl` | 156 | audio | `let audioIntensity = u.config.y * u.zoom_params.y;` |
| `public/shaders/gen-physarum-sacred-geometry.wgsl` | 134 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-prismatic-bismuth-lattice.wgsl` | 75 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-prismatic-bismuth-lattice.wgsl` | 212 | unclassified | `let thickness = mat + u.config.y * 0.1;` |
| `public/shaders/gen-prismatic-bismuth-lattice.wgsl` | 235 | unclassified | `color += irid_color * vec3<f32>(edge * u.config.y * 2.0);` |
| `public/shaders/gen-prismatic-cyber-aurora-astral-dragonfly.wgsl` | 173 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-prismatic-cyber-auroral-manta-swarm.wgsl` | 242 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-prismatic-cyber-chrono-nebula-peacock.wgsl` | 78 | audio | `let audio = u.config.y * u.zoom_params.w;` |
| `public/shaders/gen-prismatic-cyber-chrono-nebula-peacock.wgsl` | 206 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-prismatic-cyber-chrono-void-kitsune.wgsl` | 176 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-prismatic-cyber-chrono-void-kitsune.wgsl` | 177 | click_or_frame_count | `let click_shockwave = fract(u.config.y * 0.1); // Assuming some click mapping` |
| `public/shaders/gen-prismatic-cyber-chrono-void-tortoise.wgsl` | 146 | audio | `let audio_bass = plasmaBuffer[0].x * u.config.y;` |
| `public/shaders/gen-prismatic-fractal-dunes.wgsl` | 149 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-prismatic-void-weaver-ouroboros.wgsl` | 111 | audio | `let audio = u.config.y * audioReact * 2.0;` |
| `public/shaders/gen-prismatic-void-weaver-ouroboros.wgsl` | 194 | audio | `let audioReact = u.config.y * u.zoom_params.w;` |
| `public/shaders/gen-quantum-aether-origami.wgsl` | 207 | audio | `let audio_pulse = 1.0 + u.config.y * zparams.z;` |
| `public/shaders/gen-quantum-chrome-serpent-ouroboros.wgsl` | 218 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-quantum-fluorescent-aether-moth-swarm.wgsl` | 146 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-quantum-fluorescent-aether-moth-swarm.wgsl` | 149 | audio | `let click = select(0.0, 1.0, u.config.y > 0.5); // proxy for click or audio reactivity` |
| `public/shaders/gen-quantum-fluorescent-nebula-anemone.wgsl` | 140 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-quantum-foam.wgsl` | 151 | delta_time | `let dt    = u.config.y;` |
| `public/shaders/gen-quantum-mycelium.wgsl` | 130 | unclassified | `g_audio = u.config.y * 0.1;` |
| `public/shaders/gen-radiant-cyber-chrono-void-stag.wgsl` | 113 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-radiant-cyber-chrono-void-stag.wgsl` | 372 | audio | `var glow_intensity = u.config.y; // audio` |
| `public/shaders/gen-radiant-quantum-plasma-kraken-core.wgsl` | 90 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-radiant-quantum-plasma-kraken-core.wgsl` | 196 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-sentient-aether-flora-biosphere.wgsl` | 88 | audio | `let audio_react = u.zoom_params.w * u.config.y; // using click count as proxy if no audio data` |
| `public/shaders/gen-sentient-aether-flora-biosphere.wgsl` | 166 | audio | `let audio_react = u.zoom_params.w * u.config.y; // parameter 4` |
| `public/shaders/gen-sentient-cyber-aurora-void-owl.wgsl` | 192 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-sentient-quantum-chrono-leviathan-moth.wgsl` | 110 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-sentient-quantum-chrono-leviathan-moth.wgsl` | 207 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-sentient-quantum-chrono-leviathan-moth.wgsl` | 301 | click_or_frame_count | `let clickVal = u.config.y; // Simplified` |
| `public/shaders/gen-singularity-forge-blackbody.wgsl` | 129 | unclassified | `let spaghettification = u.config.y;` |
| `public/shaders/gen-singularity-forge-blackbody.wgsl` | 132 | audio | `let audioOverall = u.config.y;` |
| `public/shaders/gen-sonoluminescent-chrono-geode-matrix.wgsl` | 146 | unclassified | `let uv = vec2<f32>(f32(id.x) / u.config.x, f32(id.y) / u.config.y);` |
| `public/shaders/gen-stellar-web-loom.wgsl` | 144 | unclassified | `g_audio = u.config.y * 0.1;` |
| `public/shaders/gen_reaction_diffusion.wgsl` | 144 | click_or_frame_count | `let clickCount = u.config.y;` |
| `public/shaders/holographic-interferometry.wgsl` | 108 | audio | `let audioOverall = u.config.y;` |
| `public/shaders/holographic-interferometry.wgsl` | 109 | audio | `let audioBass = u.config.y * 1.2;` |
| `public/shaders/hybrid-chromatic-liquid.wgsl` | 79 | audio | `let audioOverall = u.config.y;` |
| `public/shaders/hybrid-magnetic-field.wgsl` | 98 | audio | `let audioOverall = u.config.y;` |
| `public/shaders/interactive-voronoi-lens.wgsl` | 81 | delta_time | `let dt = u.config.y;` |
| `public/shaders/liquid-prism.wgsl` | 95 | audio | `let audioOverall = u.config.y;` |
| `public/shaders/lorenz-attractor-flow.wgsl` | 46 | click_or_frame_count | `let click = u.config.y;` |
| `public/shaders/mouse-ink-bleed.wgsl` | 94 | delta_time | `let dt = u.config.y;` |
| `public/shaders/nano-assembler.wgsl` | 73 | unclassified | `let time = u.config.y;` |
| `public/shaders/neural-synapse-web.wgsl` | 77 | delta_time | `let dt = clamp(u.config.y, 0.001, 0.05);` |
| `public/shaders/optical-feedback.wgsl` | 117 | delta_time | `let dt = u.config.y;` |
| `public/shaders/origami-fold.wgsl` | 69 | click_or_frame_count | `let clickCount = u.config.y;` |
| `public/shaders/phase-memory-weave.wgsl` | 88 | click_or_frame_count | `let clicks = u.config.y;` |
| `public/shaders/photonic-caustics.wgsl` | 116 | click_or_frame_count | `let frame = u.config.y;` |
| `public/shaders/photonic-trace.wgsl` | 58 | click_or_frame_count | `let frame = u.config.y;` |
| `public/shaders/plasma.wgsl` | 67 | audio | `var audioOverall = u.config.y;` |
| `public/shaders/predator-prey.wgsl` | 133 | click_or_frame_count | `let frame = u.config.y;` |
| `public/shaders/quantum-foam-pass2.wgsl` | 150 | unclassified | `let globalIntensity = u.config.y;` |
| `public/shaders/quantum-foam-pass3.wgsl` | 107 | unclassified | `let globalIntensity = u.config.y;` |
| `public/shaders/spec-runge-kutta-advection.wgsl` | 92 | unclassified | `if (isMouseDown \|\| u.config.y > 0.5) {` |
| `public/shaders/stellar-plasma-blackbody.wgsl` | 130 | audio | `let audioLow = u.config.y;` |
| `public/shaders/temporal-rgb-smear.wgsl` | 174 | delta_time | `let dt = clamp(u.config.y, 0.0, 0.1);` |
| `public/shaders/time-lag-map.wgsl` | 102 | click_or_frame_count | `let frame = u.config.y;` |
| `public/shaders/vortex-distortion.wgsl` | 81 | unclassified | `let numV     = min(i32(u.config.y), 20);   // cap at 20 vortices for performance` |
