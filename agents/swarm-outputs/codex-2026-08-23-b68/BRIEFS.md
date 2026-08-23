# Batch 68 briefs — 2026-08-23 — STATEFUL SIMULATION AND FEEDBACK UPGRADE

Batch 68 upgrades ten existing simulation, feedback, generative, image, and
post-processing effects under the Batch 58D shader contract. No tracker numbers
are allocated and no renderer, graph, bind-group, TypeScript, dependency, or
WASM behavior changes.

| Shader | A ownership | Upgrade focus |
|---|---|---|
| `cellular-automata-3d` | projected display RGBA | Live audio, sprung volume attraction, bounded births, exact projected persistence |
| `elastic-chromatic-explosion` | display RGBA | Exact chromatic EMA, sprung prism focus, stronger bounded shocks |
| `fire_smoke_volumetric` | smoke RGB + density | Exact advected raw smoke, sprung heat, bounded ignition fronts |
| `glitch-ripple-drag` | display RGBA | Exact displaced history, plasma drag, sprung origin, ripple trains |
| `ink-marbling` | pigment RGB + thickness | Exact pigment advection, audio turbulence, sprung stirring, click drops |
| `magnetic-luma-sort` | display RGBA | Canonical plasma/FFT voices, exact trails, retained guarded spring |
| `neural-synapse-web` | display RGBA | Six-float spring state, uniform clicks, consistent A/C display history |
| `phase-memory-weave` | psiR + psiI + slow memory + activity | Exact state stencil, uniform phase fronts, B removal |
| `prismatic-feedback-loop` | raw accumulated RGBA | Exact accumulation, sprung held deformation, output-only ACES glow |
| `temporal-phosphor-burn` | display RGBA | Exact immediate C plus seven older ring frames, beam/click burns |

## Shared contract

- Preserve canonical bindings 0–12, the uniform layout, 16x16x1 workgroups,
  output bounds guards, and every source `params` array.
- Binding 13 remains exclusive to `temporal-phosphor-burn`, whose
  `requiresHistoryRing` flag stays true.
- Use `plasmaBuffer[0].xyz`; optional FFT detail is read-only in `[5..132]`.
- Every C access is a clamped integer-coordinate `textureLoad`; A is the sole
  feedback write and B is intentionally unwritten.
- Guard spring availability with `arrayLength`, restrict persistent state to
  `[133..138]`, and persist it only from invocation `(0,0)`.
- Cap click loops with `min(u32(u.config.y), 50u)`, use finite lifetimes and
  aspect-correct falloffs, apply canonical ACES, derive semantic alpha, and
  preserve source depth.
- Add aligned indexed `updatedParams` only where missing, update additive
  metadata, and regenerate relative category lists and the unified manifest.
