# Catalog drift audit

Generated: 2026-08-30T03:57:29.646309+00:00

Source of truth: `shader_definitions/** (id + url path)`
Lists regenerated this run: True

## Summary

- Definitions scanned: 1366
- Valid definitions: 1366
- WGSL files on disk: 1401
- Shader list ids: 1353
- Violations: **118**

| Type | Count |
|------|------:|
| `id-filename-mismatch` | 51 |
| `orphan-graph-entry` | 39 |
| `wgsl-without-definition` | 28 |

## Violations (first 100)

- `id-filename-mismatch` **anisotropic-kuwahara** — definition id 'anisotropic-kuwahara' vs url stem 'anisotropic-kuwahara-tensor' (`shader_definitions/artistic/anisotropic-kuwahara.json`)
- `id-filename-mismatch` **dla-crystals** — definition id 'dla-crystals' vs url stem 'dla-walkers' (`shader_definitions/artistic/dla-crystals.json`)
- `id-filename-mismatch` **galaxy-sim** — definition id 'galaxy-sim' vs url stem 'galaxy' (`shader_definitions/artistic/galaxy.json`)
- `id-filename-mismatch` **log-polar-droste** — definition id 'log-polar-droste' vs url stem 'log-polar-droste-remap' (`shader_definitions/distortion/log-polar-droste.json`)
- `id-filename-mismatch` **gen-lorenz-attractor-flow** — definition id 'gen-lorenz-attractor-flow' vs url stem 'lorenz-attractor-flow' (`shader_definitions/generative/gen-lorenz-attractor-flow.json`)
- `id-filename-mismatch` **gen-capabilities** — definition id 'gen-capabilities' vs url stem 'gen_capabilities' (`shader_definitions/generative/gen_capabilities.json`)
- `id-filename-mismatch` **gen-cyclic-automaton** — definition id 'gen-cyclic-automaton' vs url stem 'gen_cyclic_automaton' (`shader_definitions/generative/gen_cyclic_automaton.json`)
- `id-filename-mismatch` **gen-fluffy-raincloud** — definition id 'gen-fluffy-raincloud' vs url stem 'gen_fluffy_raincloud' (`shader_definitions/generative/gen_fluffy_raincloud.json`)
- `id-filename-mismatch` **gen-grid** — definition id 'gen-grid' vs url stem 'gen_grid' (`shader_definitions/generative/gen_grid.json`)
- `id-filename-mismatch` **gen-grok41-mandelbrot** — definition id 'gen-grok41-mandelbrot' vs url stem 'gen_grok41_mandelbrot' (`shader_definitions/generative/gen_grok41_mandelbrot.json`)
- `id-filename-mismatch` **gen-grok41-plasma** — definition id 'gen-grok41-plasma' vs url stem 'gen_grok41_plasma' (`shader_definitions/generative/gen_grok41_plasma.json`)
- `id-filename-mismatch` **gen-grok4-life** — definition id 'gen-grok4-life' vs url stem 'gen_grok4_life' (`shader_definitions/generative/gen_grok4_life.json`)
- `id-filename-mismatch` **gen-grok4-perlin** — definition id 'gen-grok4-perlin' vs url stem 'gen_grok4_perlin' (`shader_definitions/generative/gen_grok4_perlin.json`)
- `id-filename-mismatch` **gen-grokcf-interference** — definition id 'gen-grokcf-interference' vs url stem 'gen_grokcf_interference' (`shader_definitions/generative/gen_grokcf_interference.json`)
- `id-filename-mismatch` **gen-grokcf-voronoi** — definition id 'gen-grokcf-voronoi' vs url stem 'gen_grokcf_voronoi' (`shader_definitions/generative/gen_grokcf_voronoi.json`)
- `id-filename-mismatch` **gen-hyper-warp** — definition id 'gen-hyper-warp' vs url stem 'gen_hyper_warp' (`shader_definitions/generative/gen_hyper_warp.json`)
- `id-filename-mismatch` **gen-julia-set** — definition id 'gen-julia-set' vs url stem 'gen_julia_set' (`shader_definitions/generative/gen_julia_set.json`)
- `id-filename-mismatch` **gen-kimi-crystal** — definition id 'gen-kimi-crystal' vs url stem 'gen_kimi_crystal' (`shader_definitions/generative/gen_kimi_crystal.json`)
- `id-filename-mismatch` **gen-kimi-nebula** — definition id 'gen-kimi-nebula' vs url stem 'gen_kimi_nebula' (`shader_definitions/generative/gen_kimi_nebula.json`)
- `id-filename-mismatch` **gen-orb** — definition id 'gen-orb' vs url stem 'gen_orb' (`shader_definitions/generative/gen_orb.json`)
- `id-filename-mismatch` **gen-psychedelic-spiral** — definition id 'gen-psychedelic-spiral' vs url stem 'gen_psychedelic_spiral' (`shader_definitions/generative/gen_psychedelic_spiral.json`)
- `id-filename-mismatch` **gen-rainbow-smoke** — definition id 'gen-rainbow-smoke' vs url stem 'gen_rainbow_smoke' (`shader_definitions/generative/gen_rainbow_smoke.json`)
- `id-filename-mismatch` **gen-reaction-diffusion** — definition id 'gen-reaction-diffusion' vs url stem 'gen_reaction_diffusion' (`shader_definitions/generative/gen_reaction_diffusion.json`)
- `id-filename-mismatch` **gen-trails** — definition id 'gen-trails' vs url stem 'gen_trails' (`shader_definitions/generative/gen_trails.json`)
- `id-filename-mismatch` **gen-wave-equation** — definition id 'gen-wave-equation' vs url stem 'gen_wave_equation' (`shader_definitions/generative/gen_wave_equation.json`)
- `id-filename-mismatch` **kimi-fractal-dreams** — definition id 'kimi-fractal-dreams' vs url stem 'kimi_fractal_dreams' (`shader_definitions/generative/kimi_fractal_dreams.json`)
- `id-filename-mismatch` **kimi-nebula-depth** — definition id 'kimi-nebula-depth' vs url stem 'kimi_nebula_depth' (`shader_definitions/generative/kimi_nebula_depth.json`)
- `id-filename-mismatch` **kimi-quantum-field** — definition id 'kimi-quantum-field' vs url stem 'kimi_quantum_field' (`shader_definitions/generative/kimi_quantum_field.json`)
- `id-filename-mismatch` **psy-swirls** — definition id 'psy-swirls' vs url stem 'generative-psy-swirls' (`shader_definitions/generative/psy-swirls.json`)
- `id-filename-mismatch` **turing-veins** — definition id 'turing-veins' vs url stem 'generative-turing-veins' (`shader_definitions/generative/turing-veins.json`)
- `id-filename-mismatch` **kinetic-tiles** — definition id 'kinetic-tiles' vs url stem 'kinetic_tiles' (`shader_definitions/geometric/kinetic_tiles.json`)
- `id-filename-mismatch` **graphic-novel** — definition id 'graphic-novel' vs url stem 'graphic_novel' (`shader_definitions/image/graphic_novel.json`)
- `id-filename-mismatch` **ring-slicer** — definition id 'ring-slicer' vs url stem 'ring_slicer' (`shader_definitions/image/ring_slicer.json`)
- `id-filename-mismatch` **interactive-frost** — definition id 'interactive-frost' vs url stem 'frost-reveal' (`shader_definitions/interactive-mouse/interactive-frost.json`)
- `id-filename-mismatch` **kimi-chromatic-warp** — definition id 'kimi-chromatic-warp' vs url stem 'kimi_chromatic_warp' (`shader_definitions/interactive-mouse/kimi_chromatic_warp.json`)
- `id-filename-mismatch` **kimi-ripple-touch** — definition id 'kimi-ripple-touch' vs url stem 'kimi_ripple_touch' (`shader_definitions/interactive-mouse/kimi_ripple_touch.json`)
- `id-filename-mismatch` **kimi-spotlight** — definition id 'kimi-spotlight' vs url stem 'kimi_spotlight' (`shader_definitions/interactive-mouse/kimi_spotlight.json`)
- `id-filename-mismatch` **kimi-liquid-glass** — definition id 'kimi-liquid-glass' vs url stem 'kimi_liquid_glass' (`shader_definitions/liquid-effects/kimi_liquid_glass.json`)
- `id-filename-mismatch` **byte-mosh** — definition id 'byte-mosh' vs url stem 'byte-mosh-mangle' (`shader_definitions/retro-glitch/byte-mosh.json`)
- `id-filename-mismatch` **chromatographic-fluid** — definition id 'chromatographic-fluid' vs url stem 'chromatographic-force' (`shader_definitions/simulation/chromatographic-fluid.json`)
- `id-filename-mismatch` **fabric-of-reality** — definition id 'fabric-of-reality' vs url stem 'fabric-verlet' (`shader_definitions/simulation/fabric-of-reality.json`)
- `id-filename-mismatch` **gray-scott-tank** — definition id 'gray-scott-tank' vs url stem 'gray-scott-step' (`shader_definitions/simulation/gray-scott-tank.json`)
- `id-filename-mismatch` **jfa-aurora-voronoi** — definition id 'jfa-aurora-voronoi' vs url stem 'jfa-aurora-seed' (`shader_definitions/simulation/jfa-aurora-voronoi.json`)
- `id-filename-mismatch` **optical-flow-dream** — definition id 'optical-flow-dream' vs url stem 'optical-flow-estimate' (`shader_definitions/simulation/optical-flow-dream.json`)
- `id-filename-mismatch` **photonic-caustics-graph** — definition id 'photonic-caustics-graph' vs url stem 'photonic-emitter' (`shader_definitions/simulation/photonic-caustics-graph.json`)
- `id-filename-mismatch` **poincare-tiling** — definition id 'poincare-tiling' vs url stem 'poincare-tiling-map' (`shader_definitions/simulation/poincare-tiling.json`)
- `id-filename-mismatch` **predator-prey-ecology** — definition id 'predator-prey-ecology' vs url stem 'predator-prey-ecology-step' (`shader_definitions/simulation/predator-prey-ecology.json`)
- `id-filename-mismatch` **ripple-tank** — definition id 'ripple-tank' vs url stem 'ripple-tank-step' (`shader_definitions/simulation/ripple-tank.json`)
- `id-filename-mismatch` **sim-fluid-feedback-field** — definition id 'sim-fluid-feedback-field' vs url stem 'sim-fluid-feedback-field-pass1' (`shader_definitions/simulation/sim-fluid-feedback-field.json`)
- `id-filename-mismatch` **wave-tank** — definition id 'wave-tank' vs url stem 'wave-step' (`shader_definitions/simulation/wave-tank.json`)
- `id-filename-mismatch` **warp-drive** — definition id 'warp-drive' vs url stem 'warp_drive' (`shader_definitions/visual-effects/warp_drive.json`)
- `wgsl-without-definition` **anisotropic-kuwahara-filter** — public/shaders/anisotropic-kuwahara-filter.wgsl
- `wgsl-without-definition` **anisotropic-kuwahara-render** — public/shaders/anisotropic-kuwahara-render.wgsl
- `wgsl-without-definition` **byte-mosh-render** — public/shaders/byte-mosh-render.wgsl
- `wgsl-without-definition` **chromatographic-advect** — public/shaders/chromatographic-advect.wgsl
- `wgsl-without-definition` **chromatographic-diffuse** — public/shaders/chromatographic-diffuse.wgsl
- `wgsl-without-definition` **chromatographic-interact** — public/shaders/chromatographic-interact.wgsl
- `wgsl-without-definition` **chromatographic-phase** — public/shaders/chromatographic-phase.wgsl
- `wgsl-without-definition` **chromatographic-render** — public/shaders/chromatographic-render.wgsl
- `wgsl-without-definition` **dla-render** — public/shaders/dla-render.wgsl
- `wgsl-without-definition` **fabric-constraint** — public/shaders/fabric-constraint.wgsl
- `wgsl-without-definition` **fabric-render** — public/shaders/fabric-render.wgsl
- `wgsl-without-definition` **fabric-tear** — public/shaders/fabric-tear.wgsl
- `wgsl-without-definition` **gray-scott-inject** — public/shaders/gray-scott-inject.wgsl
- `wgsl-without-definition` **gray-scott-render** — public/shaders/gray-scott-render.wgsl
- `wgsl-without-definition` **jfa-aurora-flood** — public/shaders/jfa-aurora-flood.wgsl
- `wgsl-without-definition` **jfa-aurora-render** — public/shaders/jfa-aurora-render.wgsl
- `wgsl-without-definition` **log-polar-droste-grade** — public/shaders/log-polar-droste-grade.wgsl
- `wgsl-without-definition` **optical-flow-advect** — public/shaders/optical-flow-advect.wgsl
- `wgsl-without-definition` **optical-flow-grade** — public/shaders/optical-flow-grade.wgsl
- `wgsl-without-definition` **photonic-accumulate** — public/shaders/photonic-accumulate.wgsl
- `wgsl-without-definition` **photonic-trace** — public/shaders/photonic-trace.wgsl
- `wgsl-without-definition` **poincare-tiling-layer** — public/shaders/poincare-tiling-layer.wgsl
- `wgsl-without-definition` **predator-prey-ecology-render** — public/shaders/predator-prey-ecology-render.wgsl
- `wgsl-without-definition` **ripple-tank-inject** — public/shaders/ripple-tank-inject.wgsl
- `wgsl-without-definition` **ripple-tank-pass2** — public/shaders/ripple-tank-pass2.wgsl
- `wgsl-without-definition` **ripple-tank-pass3** — public/shaders/ripple-tank-pass3.wgsl
- `wgsl-without-definition` **wave-inject** — public/shaders/wave-inject.wgsl
- `wgsl-without-definition` **wave-render** — public/shaders/wave-render.wgsl
- `orphan-graph-entry` **anisotropic-kuwahara-tensor** — graph node entry referenced by 'anisotropic-kuwahara' (`shader_definitions/artistic/anisotropic-kuwahara.json`)
- `orphan-graph-entry` **anisotropic-kuwahara-filter** — graph node entry referenced by 'anisotropic-kuwahara' (`shader_definitions/artistic/anisotropic-kuwahara.json`)
- `orphan-graph-entry` **anisotropic-kuwahara-render** — graph node entry referenced by 'anisotropic-kuwahara' (`shader_definitions/artistic/anisotropic-kuwahara.json`)
- `orphan-graph-entry` **dla-walkers** — graph node entry referenced by 'dla-crystals' (`shader_definitions/artistic/dla-crystals.json`)
- `orphan-graph-entry` **dla-render** — graph node entry referenced by 'dla-crystals' (`shader_definitions/artistic/dla-crystals.json`)
- `orphan-graph-entry` **log-polar-droste-remap** — graph node entry referenced by 'log-polar-droste' (`shader_definitions/distortion/log-polar-droste.json`)
- `orphan-graph-entry` **log-polar-droste-grade** — graph node entry referenced by 'log-polar-droste' (`shader_definitions/distortion/log-polar-droste.json`)
- `orphan-graph-entry` **byte-mosh-mangle** — graph node entry referenced by 'byte-mosh' (`shader_definitions/retro-glitch/byte-mosh.json`)
- `orphan-graph-entry` **byte-mosh-render** — graph node entry referenced by 'byte-mosh' (`shader_definitions/retro-glitch/byte-mosh.json`)
- `orphan-graph-entry` **chromatographic-force** — graph node entry referenced by 'chromatographic-fluid' (`shader_definitions/simulation/chromatographic-fluid.json`)
- `orphan-graph-entry` **chromatographic-advect** — graph node entry referenced by 'chromatographic-fluid' (`shader_definitions/simulation/chromatographic-fluid.json`)
- `orphan-graph-entry` **chromatographic-diffuse** — graph node entry referenced by 'chromatographic-fluid' (`shader_definitions/simulation/chromatographic-fluid.json`)
- `orphan-graph-entry` **chromatographic-interact** — graph node entry referenced by 'chromatographic-fluid' (`shader_definitions/simulation/chromatographic-fluid.json`)
- `orphan-graph-entry` **chromatographic-phase** — graph node entry referenced by 'chromatographic-fluid' (`shader_definitions/simulation/chromatographic-fluid.json`)
- `orphan-graph-entry` **chromatographic-render** — graph node entry referenced by 'chromatographic-fluid' (`shader_definitions/simulation/chromatographic-fluid.json`)
- `orphan-graph-entry` **fabric-verlet** — graph node entry referenced by 'fabric-of-reality' (`shader_definitions/simulation/fabric-of-reality.json`)
- `orphan-graph-entry` **fabric-constraint** — graph node entry referenced by 'fabric-of-reality' (`shader_definitions/simulation/fabric-of-reality.json`)
- `orphan-graph-entry` **fabric-tear** — graph node entry referenced by 'fabric-of-reality' (`shader_definitions/simulation/fabric-of-reality.json`)
- `orphan-graph-entry` **fabric-render** — graph node entry referenced by 'fabric-of-reality' (`shader_definitions/simulation/fabric-of-reality.json`)
- `orphan-graph-entry` **gray-scott-step** — graph node entry referenced by 'gray-scott-tank' (`shader_definitions/simulation/gray-scott-tank.json`)
- `orphan-graph-entry` **gray-scott-inject** — graph node entry referenced by 'gray-scott-tank' (`shader_definitions/simulation/gray-scott-tank.json`)
- … and 18 more (see JSON)
