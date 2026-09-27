# NOTES — grok 2026-09-27 xeno / kimi / holo unused ten

Cards were written first in `BRIEFS.md`. Saved slider ids, names, defaults, and ranges were not changed. No new springs. Real-GPU QA is external.

## Per shader

- gen-xeno-botanical-synth-flora: midrib and lateral veins; treble filaments on branch ridges; held phototropism and click spore spray. Bounds guard, ACES, exact C load, bass/mids/treble. A is ACES display RGBA. `upgraded-rgba` added.
- gen-xeno-mycelial-resonance-web: anastomosis smin; septal rings; click inoculation (capped at 8 inside the SDF). Existing slider double-use left as-is. A is ACES display RGBA. `upgraded-rgba` added.
- gen-zeta-function-landscape: kept 2026-09-15 rails and |ζ|=1 contours. Added critical-line sheen and argument ticks. Spectral voice moved from extraBuffer[5..12] to plasmaBuffer bins.
- kimi-fractal-dreams (`kimi_fractal_dreams.wgsl`): interior lake persisted from C; fold-crease highlights. Spring c in [133..136] kept. [137..138] unused.
- kimi-nebula-depth (`kimi_nebula_depth.wgsl`): rosette screen angle; wet-ink bleed from C; click misregister. Sobel loop kept. This is still a halftone.
- kimi-quantum-field: nodal lines; click wave packet; decoherence haze from C. No spring.
- lava-lamp-blobs: saddle meniscus; cooler wax skin. Spring writes only at (0,0). C is textureLoad of previous raw fields. A stays raw.
- holographic-crystal: facet grooves; stepped diffraction orders. Existing audio spring kept.
- holographic-entropy-vortex: Atmosphere Density drives Rayleigh and Mie; caustics() folded into the vortex UV. workgroupBarrier removed. `target` was not in this file.
- gravito-phononic-accretion: phonon ridges between the two centers; shock shells outside the core inject. Renamed the reserved `target` binding to `audioMean`. Did not edit `gen-gravito-phononic-accretion`.

## Gates

- Naga precommit 10/10.
- extraBuffer full tree: 1417 files, 0 new writes to [0..132].
- Dead sliders: 0 new on the seven definitions that have a `params` array. Flora and mycelial only declare `updatedParams`, and both still read zoom_params.xyzw.
- Catalog 1,373. Generative list 478.
- Jest: 741 passed, 6 failed, 1 skipped. The six failures are `Cannot find module './bridge/api.js'` from `src/wasm/wasm_bridge.ts`.
- `SKIP_WASM_BUILD=1 npm run build` compiled successfully.
