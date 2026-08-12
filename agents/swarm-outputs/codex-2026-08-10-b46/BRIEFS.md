# Batch 46 briefs — 2026-08-10 (tracker #395–406) — PSYCHEDELIC ENCORE + COMPLEX SIX

Batch 46 gives the six Batch 45 generators a denser second visual layer and
upgrades six unclaimed complex generative shaders with live drag/click motion,
safe bounded history, and truthful depth/state ownership.

| # | Shader | Lines | Second-pass focus |
|---|--------|-------|-------------------|
| 395 | `gen-kaleidoscopic-synapse-bloom` | 98→104 | Counter-rotating dendrites and bridge sparks |
| 396 | `gen-liquid-cathedral-dream` | 102→108 | Rose tracery and floor caustics |
| 397 | `gen-mushroom-mandala-garden` | 104→108 | Mycelium pulses and fairy rings |
| 398 | `gen-prismatic-serpent-river` | 101→105 | Prism fins and river current |
| 399 | `gen-cosmic-velvet-hypnosis` | 99→102 | Counter-spiral moire |
| 400 | `gen-chromatic-oracle-jelly` | 107→112 | Oracle sigils and deep bells |
| 401 | `gen-gravitational-strain` | 451→461 | Drag strain runners and bounded RK4 budget |
| 402 | `gen-holographic-data-core` | 382→410 | Smooth scan packets, beams, rings, history |
| 403 | `gen-art-deco-sky` | 408→432 | Drag searchlights and skyline halos |
| 404 | `gen-ethereal-anemone-bloom` | 385→415 | Drag blooms and bioluminescent fronts |
| 405 | `gen-liquid-crystal-hive-mind` | 371→384 | Click chemotactic fronts in preserved state |
| 406 | `gen-celestial-prism-orchid` | 408→437 | Correct pointer wind, prism petals, history |

## Shared contract

- Canonical bindings, 16x16x1 workgroups, invocation guards, real audio, and no `extraBuffer` writes.
- All four slider channels and mouse position/down are live; click loops cap at 50.
- Source `params` and `updatedParams` arrays remain byte-exact.
- A remains simulation state for Gravitational Strain and Hive-Mind; the other ten use bounded display history. B remains unused.
- Every C history read is an exact clamped `textureLoad`; motion is continuous rather than frame-hash strobing.
- Generated depth claims are limited to shaders that write scene-derived depth.
- Cloud-VM proof is structural; visual and performance acceptance require a discrete GPU.
