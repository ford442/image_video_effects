# Coordinator review — simpler / mid crystal-math ten

Cards in `BRIEFS.md` were written before the WGSL edits. Each numbered idea is named in the shader.

| Shader | Card first | Ideas in WGSL | Kept identity | No shared overlay | Packing | Params | Springs | Naga | Result |
|---|---|---|---|---|---|---|---|---|---|
| gen-crystal-lattice-growth | yes | striae; nucleation core | twin + hopper kept | yes | HDR A / ACES write | exact | none added | pass | pass |
| gen-chromatic-zonohedron | yes | zone belts; inset | 4 generators, stars, dichroism | yes | ACES display | exact | none | pass | pass |
| gen-cyber-terminal | yes | column gaps; wrap flash | glyphs + leader | yes | HDR history | exact | none | pass | pass |
| gen-cyclic-automaton | yes | pacemaker; cooldown ticks | chirality + halo + tracer | yes | raw GH | exact | existing kept | pass | pass |
| gen-cycloid-bloom | yes | epicycloid; crossings | vein + stamen | yes | ACES display | exact | none | pass | pass |
| gen-de-jong-attractor | yes | critical curves; antipode | stretch + dwell | yes | raw density | exact | existing kept | pass | pass |
| gen-crystal-caverns | yes | phantom; pinacoid | three habits + caustics | yes | ACES display | exact | none | pass | pass |
| gen-celestial-forge | yes | temper; hammer flats | greebles + spring + arcs | yes | ACES display | exact | existing kept | pass | pass |
| gen-cosmic-web-filament | yes | walls; beads | Zel'dovich + quasars | yes | ACES display | exact | existing kept | pass | pass |
| gen-dla-copper-deposition | yes | screening; front sheen | cathode + oxidation + tips | yes | raw fields | exact | none | pass | pass |

extraBuffer audit: 0 new. Dead sliders: 0 on these ten. Catalog 1,373. Jest 741 pass / 6 fail / 1 skip (pre-existing WASM `bridge/api.js`). SKIP_WASM_BUILD=1 build green. Real-GPU QA external.
