# Batch 45 briefs — 2026-08-10 (tracker #389–394) — PSYCHEDELIC GENERATIVE SIX

Six new single-pass generative shaders explore distinct colorful,
psychedelic-inspired forms. Each exposes four live sliders and responds to
pointer position, held drag, bounded click history, and real audio.

| # | Shader | Lines | Visual focus | Four controls |
|---|--------|-------|--------------|---------------|
| 389 | `gen-kaleidoscopic-synapse-bloom` | 98 | Neural petals and axon runners | Bloom Density, Pulse Speed, Neural Warp, Color Flux |
| 390 | `gen-liquid-cathedral-dream` | 102 | Melting stained-glass architecture | Spire Density, Melt Speed, Refraction, Stained Hue |
| 391 | `gen-mushroom-mandala-garden` | 104 | Breathing caps, gills, and spores | Cap Count, Breathe Rate, Gill Detail, Bioluminescence |
| 392 | `gen-prismatic-serpent-river` | 101 | Braided serpents and racing scales | Serpent Count, Flow Speed, Body Scale, Iridescence |
| 393 | `gen-cosmic-velvet-hypnosis` | 99 | Soft spiral wells and runners | Spiral Arms, Spin Rate, Velvet Softness, Saturation |
| 394 | `gen-chromatic-oracle-jelly` | 107 | Drifting oracle jellies and tentacles | Swarm Density, Drift Speed, Tentacle Curl, Oracle Chroma |

## Shared contract

- Canonical bindings, 16x16x1 workgroups, invocation bounds guards, and no `extraBuffer` writes.
- `config=[time,rippleCount,resW,resH]`; click loops cap at 50.
- `zoom_config=[time,mouseX,mouseY,mouseDown]`; position and held state jointly drive local deformation.
- Four ordered `params` entries with explicit mappings plus matching indexed `updatedParams`.
- Real `plasmaBuffer[0].xyz` audio, semantic alpha, and generated structural depth.
- A stores bounded display history, B remains unused, and C uses exact clamped `textureLoad`.
- Motion is closed-form/history-advected without frame-hash strobing.
- Cloud-VM proof is structural; visual and performance acceptance require verified discrete-GPU hardware.
