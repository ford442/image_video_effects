# Codex crystalline / cybernetic generative batch

Date: 2026-08-23

## Cohort

1. `gen-crystal-lattice-growth` — crystal lattice growth
2. `gen-crystalline-chrono-dyson` — crystalline chrono Dyson structure
3. `gen-crystalline-mandala-bloom` — crystalline mandala bloom
4. `gen-crystalline-nebula-weaver-void-spider` — nebula weaver / void spider
5. `gen-cyber-organic-liquid-neon-pulsar` — cyber-organic neon pulsar
6. `gen-cyber-terminal` — cyber terminal display
7. `gen-cybernetic-aether-moth-chrysalis` — cybernetic aether moth chrysalis
8. `gen-cybernetic-crystalline-neuro-lattice` — cybernetic crystalline neuro lattice
9. `gen-cybernetic-ferro-coral` — cybernetic ferro-coral
10. `gen-cybernetic-liquid-chrome-engine` — cybernetic liquid chrome engine

## Acceptance contract

- Canonical bindings 0–12 and a 16×16×1 entry point.
- ACES-mapped display output with semantic alpha and meaningful depth.
- Primary raw HDR display history written only to `dataTextureA`; no B writeback.
- Every `dataTextureC` read uses exact integer `textureLoad` access.
- Bass, mids, and treble come from `plasmaBuffer[0].xyz` and affect distinct details.
- No persistent state outside `extraBuffer[133..138]`; this cohort needs no extra-buffer state.
- Existing mouse / held interaction remains intact, and timestamped click ripples are retained or added where appropriate.
- Four named JSON `params`, mapped in x/y/z/w order and aligned with `updatedParams`.
- Focused Naga and repository validation must pass.
