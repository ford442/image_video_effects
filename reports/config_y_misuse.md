# `u.config.y` misuse audit

`config = [time, rippleCount, resW, resH]` — see `src/contracts/uniforms_layout.json`.
Every row below reads `config.y` (or a legacy `config` swizzle) as something else.

**Total: 40 reads across 36 shaders**

| Category | Count |
|----------|-------|
| `audio` | 16 |
| `unclassified` | 9 |
| `click_or_frame_count` | 8 |
| `delta_time` | 7 |

## Findings

| File | Line | Category | Code |
|------|------|----------|------|
| `public/shaders/4d-projection-dream-weavers.wgsl` | 131 | delta_time | `let dt = clamp(u.config.y, 0.001, 0.05);` |
| `public/shaders/acoustic-string-theory.wgsl` | 92 | delta_time | `let dt = clamp(u.config.y, 0.001, 0.05);` |
| `public/shaders/alpha-em-field-simulation.wgsl` | 149 | click_or_frame_count | `let clickParity = select(-1.0, 1.0, u.config.y % 2.0 < 1.0);` |
| `public/shaders/aurora-rift-pass2.wgsl` | 157 | unclassified | `let globalIntensity = clamp(u.config.y, 0.1, 1.5);` |
| `public/shaders/chronos-brush.wgsl` | 56 | click_or_frame_count | `let clickCount = u.config.y;` |
| `public/shaders/dla-crystals.wgsl` | 93 | click_or_frame_count | `let frame = u.config.y;` |
| `public/shaders/gen-abyssal-leviathan-iridescence.wgsl` | 145 | unclassified | `g_audio = u.config.y * 0.1;` |
| `public/shaders/gen-auroral-ferrofluid-monolith.wgsl` | 220 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-chromatic-singularity-loom.wgsl` | 104 | audio | `let audio_intensity = u.config.y;` |
| `public/shaders/gen-chronodynamic-aether-weaver-automata.wgsl` | 81 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-ethereal-anemone-bloom.wgsl` | 377 | audio | `let audio_pulse = plasmaBuffer[0].x; // was u.config.y (MouseClickCount)` |
| `public/shaders/gen-quantum-aether-origami.wgsl` | 207 | audio | `let audio_pulse = 1.0 + u.config.y * zparams.z;` |
| `public/shaders/gen-quantum-chrome-serpent-ouroboros.wgsl` | 218 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-quantum-fluorescent-nebula-anemone.wgsl` | 140 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-quantum-foam.wgsl` | 151 | delta_time | `let dt    = u.config.y;` |
| `public/shaders/gen-quantum-liquid-metal-chronosphere.wgsl` | 101 | unclassified | `if (f32(i) >= u.config.y) { break; }` |
| `public/shaders/gen-radiant-cyber-chrono-void-stag.wgsl` | 113 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-radiant-cyber-chrono-void-stag.wgsl` | 372 | audio | `var glow_intensity = u.config.y; // audio` |
| `public/shaders/gen-radiant-quantum-plasma-kraken-core.wgsl` | 90 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-radiant-quantum-plasma-kraken-core.wgsl` | 196 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-sentient-cyber-aurora-void-owl.wgsl` | 192 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-sentient-quantum-chrono-leviathan-moth.wgsl` | 110 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-sentient-quantum-chrono-leviathan-moth.wgsl` | 207 | audio | `let audio = u.config.y;` |
| `public/shaders/gen-sentient-quantum-chrono-leviathan-moth.wgsl` | 301 | click_or_frame_count | `let clickVal = u.config.y; // Simplified` |
| `public/shaders/gen-singularity-forge-blackbody.wgsl` | 133 | unclassified | `let spaghettification = u.config.y;` |
| `public/shaders/gen_reaction_diffusion.wgsl` | 144 | click_or_frame_count | `let clickCount = u.config.y;` |
| `public/shaders/glass-bead-curtain.wgsl` | 72 | unclassified | `let target = select(0.0, 1.0, u.config.y > 0.0);` |
| `public/shaders/holographic-crystal.wgsl` | 53 | delta_time | `let dt = min(u.config.y, 0.05);` |
| `public/shaders/holographic-entropy-vortex.wgsl` | 156 | click_or_frame_count | `let clicks = u.config.y;` |
| `public/shaders/hybrid-chromatic-liquid.wgsl` | 79 | audio | `let audioOverall = u.config.y;` |
| `public/shaders/interactive-voronoi-lens.wgsl` | 81 | delta_time | `let dt = u.config.y;` |
| `public/shaders/mouse-ink-bleed.wgsl` | 94 | delta_time | `let dt = u.config.y;` |
| `public/shaders/origami-fold.wgsl` | 69 | click_or_frame_count | `let clickCount = u.config.y;` |
| `public/shaders/photonic-trace.wgsl` | 58 | click_or_frame_count | `let frame = u.config.y;` |
| `public/shaders/plasma.wgsl` | 73 | audio | `var audioOverall = u.config.y;` |
| `public/shaders/quantum-foam-pass2.wgsl` | 154 | unclassified | `let globalIntensity = u.config.y;` |
| `public/shaders/quantum-foam-pass3.wgsl` | 111 | unclassified | `let globalIntensity = u.config.y;` |
| `public/shaders/spec-runge-kutta-advection.wgsl` | 108 | unclassified | `if (isMouseDown \|\| u.config.y > 0.0) {` |
| `public/shaders/temporal-rgb-smear.wgsl` | 174 | delta_time | `let dt = clamp(u.config.y, 0.0, 0.1);` |
| `public/shaders/vortex-distortion.wgsl` | 83 | unclassified | `let numV     = min(i32(u.config.y), 20);   // cap at 20 vortices for performance` |
