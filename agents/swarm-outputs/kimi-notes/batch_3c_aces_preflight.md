# Batch 3C Pre-Flight: ACES Duplicate Audit — 2026-06-06

## Method

For each of the 10 Batch 3C chromatic-sweep targets, checked for:
1. Total `acesToneMap` / `aces_tonemap` function definitions
2. Inline ACES formula mentions
3. Legacy vs canonical naming

## Results

| Shader | Function Defs | Inline Mentions | Canonical `acesToneMap` | Legacy `aces_tonemap` | Status |
|--------|---------------|-----------------|-------------------------|-----------------------|--------|
| aurora-curtain | 1 | 0 | 1 | 0 | ✅ Clean |
| bioluminescent-bloom | 1 | 0 | 1 | 0 | ✅ Clean |
| gen-belousov-zhabotinsky | 1 | 0 | 1 | 0 | ✅ Clean |
| gen-bio-luminescent-jelly | 1 | 0 | 1 | 0 | ✅ Clean |
| gen-celestial-nanite-swarm-nebula | 1 | 0 | 1 | 0 | ✅ Clean |
| gen-crystal-lattice-growth | 1 | 0 | 1 | 0 | ✅ Clean |
| gen-crystalline-mandala-bloom | 1 | 0 | 1 | 0 | ✅ Clean |
| gen-dla-copper-deposition | 1 | 0 | 1 | 0 | ✅ Clean |
| gen-dynamic-tessellation-ornate-fractal-tiles | 1 | 0 | 1 | 0 | ✅ Clean |
| gen-fourier-epicycles | 1 | 0 | 1 | 0 | ✅ Clean |

## Summary

- **0 duplicate ACES functions**
- **0 legacy `aces_tonemap` names**
- **10/10 shaders use canonical `acesToneMap`**

Batch 3C is clean for ACES. Codex can proceed with chromatic-only insertion validation without risk of duplicate-function stacking.
