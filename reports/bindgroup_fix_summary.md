# BindGroup Auto-Fix Summary

**Generated:** 2026-05-09 23:50 UTC  
**Tool:** `scripts/fix_bindgroups.py`

## Overview

| Metric | Count |
| --- | --- |
| Total shaders processed | 971 |
| Incompatible **before** fix | 50 |
| Incompatible **after** fix | 3 |
| Shaders auto-fixed | 47 |
| Shaders already compatible | 917 |
| Shaders requiring manual review | 2 |
| Shaders skipped (templates/render) | 5 |

## Fix Types Applied

| Fix Type | Shaders Fixed |
| --- | --- |
| `binding_12_access` | 22 |
| `binding_10_access` | 21 |
| `added_missing_bindings` | 3 |
| `uniforms_ripples_field_added` | 1 |

## Auto-Fixed Shaders

| Shader | Fixes Applied |
| --- | --- |
| `digital-moss` | `binding_10_access: read → read_write` |
| `echo-trace` | `binding_10_access: read → read_write` |
| `engraving-stipple` | `binding_10_access: read → read_write` |
| `fabric-zipper` | `binding_10_access: read → read_write` |
| `flux-core` | `binding_10_access: read → read_write` |
| `foil-impression` | `binding_10_access: read → read_write` |
| `fractal-glass-distort` | `binding_10_access: read → read_write` |
| `gen-cosmic-clockwork-dyson-sphere` | `added_missing_bindings: [12]` |
| `gen-luminous-fluid-chladni-resonator` | `added_missing_bindings: [4, 5, 6, 7, 8, 9, 10, 11]` |
| `gen-physarum-sacred-geometry` | `added_missing_bindings: [12]` |
| `gravity-lens` | `binding_12_access: <storage> → <storage, read>` |
| `holographic-contour` | `binding_12_access: <storage> → <storage, read>` |
| `holographic-projection` | `binding_12_access: <storage> → <storage, read>` |
| `hybrid-chromatic-liquid` | `binding_12_access: <storage> → <storage, read>` |
| `hybrid-sdf-plasma` | `binding_12_access: <storage> → <storage, read>` |
| `impasto-swirl` | `binding_12_access: <storage> → <storage, read>` |
| `ink-bleed` | `binding_10_access: read → read_write` |
| `ink_dispersion_alpha` | `binding_12_access: <storage> → <storage, read>` |
| `interactive-voronoi-lens` | `binding_10_access: read → read_write` |
| `kimi_nebula_depth` | `binding_12_access: <storage> → <storage, read>` |
| `light-leaks` | `binding_12_access: <storage> → <storage, read>` |
| `liquid-prism-cascade` | `binding_12_access: <storage> → <storage, read>` |
| `liquid-swirl` | `binding_12_access: <storage> → <storage, read>` |
| `liquid-warp` | `uniforms_ripples_field_added` |
| `matrix_digital_rain` | `binding_12_access: <storage> → <storage, read>` |
| `multi-fractal-compositor` | `binding_12_access: <storage> → <storage, read>` |
| `nano-assembler` | `binding_10_access: read → read_write` |
| `nebula-gyroid` | `binding_12_access: <storage> → <storage, read>` |
| `neon-edge-pulse` | `binding_12_access: <storage> → <storage, read>` |
| `neon-edges` | `binding_12_access: <storage> → <storage, read>` |
| `neural-raymarcher` | `binding_12_access: <storage> → <storage, read>` |
| `paper-cutout` | `binding_10_access: read → read_write` |
| `parallax-glow-compositor` | `binding_12_access: <storage> → <storage, read>` |
| `parallax_depth_layers` | `binding_12_access: <storage> → <storage, read>` |
| `particle_dreams_alpha` | `binding_12_access: <storage> → <storage, read>` |
| `phase-shift` | `binding_12_access: <storage> → <storage, read>` |
| `prismatic-mosaic` | `binding_12_access: <storage> → <storage, read>` |
| `quantum-field-visualizer` | `binding_10_access: read → read_write` |
| `rgb-delay-brush` | `binding_10_access: read → read_write` |
| `rgb-iso-lines` | `binding_10_access: read → read_write` |
| `scanline-tear` | `binding_10_access: read → read_write` |
| `sequin-flip` | `binding_10_access: read → read_write` |
| `signal-tuner` | `binding_10_access: read → read_write` |
| `sonic-boom` | `binding_10_access: read → read_write` |
| `strip-scan-glitch` | `binding_10_access: read → read_write` |
| `temporal-distortion-field` | `binding_10_access: read → read_write` |
| `voxel-grid` | `binding_10_access: read → read_write` |

## Shaders Requiring Manual Review

These shaders could not be auto-fixed. Human intervention is needed.

| Shader | Issues |
| --- | --- |
| `gen-superfluid-quantum-foam` | Uniforms missing ripples but has extra fields ['custom_params'] – manual layout fix required |
| `plasma` | binding 12 wrong type: 'array<PlasmaBall, 50>' |

## Remaining Incompatible Shaders (post-fix)

| Shader | Errors |
| --- | --- |
| `_hash_library` | No @compute, @vertex, or @fragment entry points found |
| `gen-superfluid-quantum-foam` | Uniforms struct missing fields: ['ripples'] |
| `plasma` | Binding 12 (plasmaBalls) has incompatible type: 'array<PlasmaBall, 50>' |

---

## Violation Type Reference

| Violation | Auto-fixable? | Fix applied |
| --- | --- | --- |
| `binding_10_access: read → read_write` | ✅ Yes | Changed `<storage, read>` to `<storage, read_write>` |
| `binding_12_access: <storage> → <storage, read>` | ✅ Yes | Added `, read` access qualifier |
| `added_missing_bindings` | ✅ Yes | Inserted canonical stub declarations |
| `uniforms_ripples_field_added` | ✅ Yes | Appended `ripples` field to Uniforms struct |
| Binding 12 wrong struct type (`array<PlasmaBall, …>`) | ❌ No | Needs custom rewrite |
| Uniforms struct with extra fields + missing `ripples` | ❌ No | Memory-layout conflict, manual fix |
| No `@compute` entry point | ❌ No | Library/utility file |
