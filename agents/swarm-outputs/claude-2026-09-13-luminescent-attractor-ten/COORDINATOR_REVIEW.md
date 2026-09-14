# Coordinator Review — luminescent / attractor ten (2026-09-13)

Structural gates re-run by coordinator after all agents finished (Cloud VM, no GPU).

| Shader | Ideas (pointable) | Floor / bug fixes | A packing | Verdict |
|---|---|---|---|---|
| gen-lorenz-attractor | per-wing density accumulation (true lobe chroma); orbit-speed tint | header trimmed to 3 tags; tube/fold/trap untouched | r=right-wing dens, g=left-wing dens, b=speed dens, a=alpha | PASS |
| gen-lorenz-attractor-flow | chaos-ridge filaments (twin-orbit divergence); wing-switch parity bands; flow-advected history | ACES added; history blended post-tonemap (removed double tonemap drift) | ACES display RGBA | PASS |
| …aether-plasma-astro-axolotl | gill regeneration front; gill capillary pulses; gold skin flecks | Reinhard→ACES; semantic alpha; matId ranges | display RGBA | PASS |
| …aether-plasma-nebula-koi | alternating tail-beat wake; head→tail scale-row flash; true C feedback | `u.config.y` as audio → plasmaBuffer; fake history (input image) → exact C load; depth inverted fixed | display RGBA | PASS |
| …chrono-fluid-astrolabe | limb degree graduations; gear-ratio ring train + teeth; rete star-chart plate | helper extraction only | ACES display RGBA (unchanged) | PASS |
| …chrono-prism-astro-stag | branching antler tines; per-channel prism dispersion; afterimage from C | mouse/res double-divide; guarded capsule; stag re-centred + un-flipped; dead Prismatic slider revived | ACES display RGBA | PASS — **visual QA: framing changed** |
| …cyber-chrono-void-turtle | scute plate drift; mouse time-dilation; growth rings; void wake from C | config.y audio → plasmaBuffer; mouse double-divide; dead ripple loop; constant depth; added dataA | raw linear wake RGB + energy a | PASS |
| …nebula-silk-weaver | plucked-string thread vibration; dew beads; silk afterglow | filtered C read as "audio" → plasmaBuffer; added depth + dataA | linear pre-ACES RGB + density a | PASS |
| …quantum-flora-symphony | phyllotaxis seed spiral; petal veins + backlight; stem nodes + rising sap | none needed | ACES display RGB + spore a (unchanged) | PASS |
| …quantum-glass-phoenix-egg | shell crack network w/ ember leak; caustic threads; ember afterglow from C.x | config.y audio → plasmaBuffer; mouse dead; fake history removed; refract eta>1 TIR collapse | raw: x=heat, y=density, z=fog, w=alpha | PASS |

## Gates
- Naga 10/10, `wgsl_precommit_gate.py` 10/10 (bindgroup compatible), no `textureStore(dataTextureC`.
- `audit:extrabuffer` PASS. Dead sliders: audit passes but scans 0 defs for files lacking `params` (only `updatedParams`) — agents verified all 4 `zoom_params` reads by grep.
- `generate_shader_lists.js` + `check_duplicates.js`: 1378 unique IDs.
- Saved `params` unchanged; JSON features only gained true tags.

## Watch on real GPU
- stag framing (re-centred, antlers now up); lorenz-flow ridge threshold flooding; koi wake visibility behind camera axis;
  axolotl gill swell blobbiness; phoenix-egg afterglow ghosting on fast orbit; lorenz-flow legacy click `sin(t*20)` pulse.

## Out of scope, noticed
- `gen-luminescent-quantum-void-astral-turtle` and `gen-luminescent-quantum-void-anglerfish` still read `u.config.y` as audio.
- phoenix-egg `updatedParams` names (Scale/Intensity/Speed/Detail) don't match shader roles — pre-existing.
