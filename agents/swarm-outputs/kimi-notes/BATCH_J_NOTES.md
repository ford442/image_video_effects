# Batch J — 12 Generative Shader Upgrades

**Agent:** Kimi
**Date:** 2026-05-31
**Scope:** Upgrade 12 unclaimed generative shaders with temporal feedback, chromatic dispersion, and enhanced audio reactivity.

---

## Shader List

| # | ID | Lines Before | Lines After | Key Upgrade |
|---|----|-------------:|------------:|-------------|
| 1 | `gen-vortex-cathedral` | 83 | 106 | Temporal ghost cathedral (dataTextureC blend), chromatic R/G/B separation on arches/columns/fog |
| 2 | `gen-celestial-weave` | 89 | 112 | Star trail persistence, chromatic warp/weft/star separation with audio-shifted hues |
| 3 | `gen-magnetic-kelp` | 89 | 112 | Kelp sway memory, chromatic green strands/cyan fronds/gold spores |
| 4 | `gen-luminous-cauldron` | 90 | 113 | Bubble boil persistence, chromatic purple bowl/orange heat/white foam/blue sparks |
| 5 | `gen-neon-snowfall` | 90 | 113 | Snow streak accumulation, chromatic per-flake hue with R/G/B band shifts |
| 6 | `gen-bioreactor-bloom` | 91 | 114 | Colony grow/fade persistence, chromatic green colony/cyan nucleus/red poison/gold spores |
| 7 | `gen-opal-circuit` | 92 | 115 | Signal echo through traces, chromatic opal R/G/B phase offsets per audio band |
| 8 | `gen-prism-tide` | 98 | 121 | Crest/foam accumulation, chromatic prism dispersion with R/G/B phase displacement |
| 9 | `gen-echo-dunes` | 101 | 124 | Echo ring decay, chromatic warm sand/blue mirage/cyan echo |
| 10 | `gen-quantum-pollen` | 105 | 128 | Pollen drift trail persistence, chromatic per-layer color shifts (treble/mids/bass) |
| 11 | `gen-volcanic-ink` | 111 | 134 | Lava smear & smoke accumulation, chromatic warm lava/amber sparks/blue-shifted smoke |
| 12 | `gen-aurora-silk` | 113 | 136 | Aurora ribbon fade persistence, chromatic palette shifted by bass/treble/mids |

---

## Upgrade Patterns Applied

### Temporal Feedback (`dataTextureC`)
- Added `textureSampleLevel(dataTextureC, u_sampler, uv, 0.0)` read in all 12 shaders
- Blend factor: `0.02–0.06` base + audio modulation (`bass * 0.01` to `bass * 0.015`)
- Contextually weighted by effect (e.g., `trail * 0.05` in Quantum Pollen, `foam * 0.06` in Prism Tide)
- All blends use `mix(current, prev * 0.88–0.92, factor)`

### Chromatic Dispersion
- Each shader assigns distinct RGB offsets to its primary visual elements
- Audio bands (bass/mids/treble) modulate individual channel intensities (typically `±0.05–0.15`)
- Prevents uniform white-wash and adds spectral richness

### Enhanced Audio Reactivity
- Existing `plasmaBuffer[0].xyz` usage preserved
- Additional modulation injected into chromatic channels
- No new uniform bindings added (compliant with 13-binding contract)

### Depth-Aware Compositing
- All shaders already wrote `writeDepthTexture`; no changes needed
- Depth values incorporate audio and parameter mixes as before

### Header Updates
- Added `temporal`, `chromatic`, `upgraded-rgba`, `depth-aware` to Features
- Changed Complexity: Medium → High
- Added `Upgraded: 2026-05-31` line

---

## JSON Definition Changes
- Features array updated in all 12 JSONs:
  - Before: `["procedural", "audio-reactive", "mouse-driven", "upgraded-rgba"]`
  - After: `["procedural", "audio-reactive", "mouse-driven", "upgraded-rgba", "temporal", "chromatic", "depth-aware"]`
- No new parameters added (existing 4 params sufficient)

---

## Validation Status
- Pending: `generate_shader_lists.js` + `check_duplicates.js`

---

## Claude Polish Notes
- All shaders use `textureSampleLevel(dataTextureC, u_sampler, uv, 0.0)` — verify LOD 0 is correct for feedback
- Temporal blend factors are conservative; Claude may want to increase echo in `echo-dunes` and `quantum-pollen`
- Chromatic offsets are subtle; Claude may want to amplify prism dispersion in `prism-tide`
- Consider adding `dataTextureB` usage for dual-pass variants in future batches
