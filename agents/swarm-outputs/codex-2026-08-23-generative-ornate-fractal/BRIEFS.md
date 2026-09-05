# Codex ornate / fractal-growth generative batch

Date: 2026-08-23

## Cohort

1. `gen-dynamic-tessellation-ornate-fractal-tiles`
2. `gen-echo-dunes`
3. `gen-eldritch-quantum-fractal-eye`
4. `gen-emergent-calligraphic-weave`
5. `gen-ferrofluid-monolith`
6. `gen-fibonacci-spiral-garden`
7. `gen-flame-fractal-attractor`
8. `gen-flowing-silk-ribbons`
9. `gen-fractal-flame-classic`
10. `gen-fractal-tree-growth`

The repository contained only the first three exact IDs. The remaining seven were implemented greenfield under the requested IDs; nearby preset-bearing effects were not renamed or reused as aliases.

## Acceptance contract

- Bindings 0–12 and 16×16×1 compute entry points.
- ACES-mapped display output, semantic alpha, and meaningful near-is-one depth.
- Raw HDR display RGBA written only to `dataTextureA`; no B writeback.
- Every C history read uses exact integer `textureLoad` access.
- Bass, mids, and treble from `plasmaBuffer[0].xyz` affect distinct visual details.
- Persistent state is confined to `extraBuffer[133..138]`; only Echo Dunes uses slot 133.
- Mouse, held, and timestamped click-ripple interaction are preserved or implemented.
- Four named JSON controls mapped in x/y/z/w order and aligned with `updatedParams`.
- Focused Naga and repository validation must pass.
