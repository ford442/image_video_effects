# Phase C Agent Swarm Registry

**Status:** ✅ COMPLETE  
**Started:** 2026-06-28  
**Goal:** Execute deep upgrades on the next tier of small effect and generative shaders.

---

## Discovery Summary

- **Historical Effect targets** (from `agents/EFFECT_UPGRADE_SWARM.md` + `notes/EFFECT_SHADER_UPGRADE_MANIFEST.md`): 8 effect shaders already upgraded to 150-225 lines.
- **Historical Generative targets** (from `agents/GENERATIVE_UPGRADE_SWARM.md` + `notes/GENERATIVE_SHADER_UPGRADE_MANIFEST.md`): 8 generative shaders already upgraded to 165-282 lines.
- **Next-tier small effect shaders identified:** 8 candidates across post-processing, distortion, retro-glitch, and visual-effects categories, all <125 lines.
- **Next-tier small generative shaders identified:** 8 candidates in the generative category, all <125 lines.

**Conclusion:** Phase C pivots to applying the same deep-upgrade methodology to the next tier of small shaders that have not yet been expanded.

---

## Standards Checklist

- [x] Preserve canonical 13-binding header and Uniforms struct.
- [x] `@workgroup_size(16, 16, 1)`.
- [x] Generative shaders: `alpha = 1.0`, no input texture reads.
- [x] Effect shaders: preserve input alpha, clamp/normalize zoom_params, depth pass-through.
- [x] Expand each shader by 40-80 lines with advanced math/noise/SDF/lighting.
- [x] Add/update header comments with category and feature tags.
- [x] Validate with `naga <file> /tmp/out.wgsl`.

---

## Agent Assignments

### Agent 1c — Effect Shader Upgrade Specialist ✅
**Target:** Deep-upgrade 8 small effect shaders.

Files:
1. `public/shaders/temporal-feedback-zoom-tracer.wgsl` (97 lines)
2. `public/shaders/temporal-rgb-ghost.wgsl` (98 lines)
3. `public/shaders/temporal-phosphor-burn.wgsl` (101 lines)
4. `public/shaders/dimension-slicer.wgsl` (98 lines)
5. `public/shaders/prism-displacement.wgsl` (104 lines)
6. `public/shaders/xerox-degrade.wgsl` (102 lines)
7. `public/shaders/holographic-flicker.wgsl` (97 lines)
8. `public/shaders/chroma-vortex.wgsl` (101 lines)

Upgrade vectors (per shader):
- Add advanced noise/FBM, chromatic dispersion, or lens optics.
- Add temporal feedback or multi-frame accumulation logic.
- Add mouse/audio reactivity where appropriate.
- Preserve input alpha and depth pass-through.

### Agent 2c — Generative Shader Upgrade Specialist ✅
**Target:** Deep-upgrade 8 small generative shaders.

Files:
1. `public/shaders/gen-celestial-weave.wgsl` (114 lines)
2. `public/shaders/gen-magnetic-kelp.wgsl` (114 lines)
3. `public/shaders/gen-neon-snowfall.wgsl` (115 lines)
4. `public/shaders/gen-echo-dunes.wgsl` (115 lines)
5. `public/shaders/gen-luminous-cauldron.wgsl` (115 lines)
6. `public/shaders/generative-turing-veins.wgsl` (116 lines)
7. `public/shaders/gen-opal-circuit.wgsl` (116 lines)
8. `public/shaders/gen-bioreactor-bloom.wgsl` (116 lines)

Upgrade vectors (per shader):
- Add domain warping, FBM layering, SDF primitives, or reaction-diffusion.
- Add palette-based color grading and glow/bloom helpers.
- Add time-based animation and organic motion.
- Keep `alpha = 1.0` for generative backgrounds.

### Agent 3c — Mathematical Function Library Expansion ✅
**Target:** Extract any new reusable chunks from the upgraded shaders and append them to `agents/swarm-outputs/chunk-library.md`.

### Agent 4c — Advanced Hybrid Effect Creator ✅
**Target:** Create 2 advanced hybrid shaders combining effect + generative techniques.

Create:
1. `public/shaders/hyb-temporal-fbm-ghost.wgsl` — temporal feedback + FBM ghosting over input
2. `public/shaders/hyb-chromatic-circuit.wgsl` — opal-circuit style chromatic edge distortion over input

### Agent 5c — QA & Integration ✅
**Target:** Aggregate changes, run `naga` on every touched shader, run `node scripts/generate_shader_lists.js`, and update this registry.

---

## Success Criteria

- [x] 8 effect shaders upgraded and pass naga.
- [x] 8 generative shaders upgraded and pass naga.
- [x] Chunk library expanded with newly extracted functions.
- [x] 2 new hybrid shaders created with JSON definitions and pass naga.
- [x] Shader lists regenerated successfully.

---

## QA Results

| Check | Count | Status |
|-------|-------|--------|
| Effect shaders (naga) | 8 / 8 | ✅ PASS |
| Generative shaders (naga) | 8 / 8 | ✅ PASS |
| Hybrid shaders (naga) | 2 / 2 | ✅ PASS |
| Hybrid JSON definitions | 2 / 2 | ✅ VALID |
| `scripts/generate_shader_lists.js` | — | ✅ SUCCESS |
| Chunk library expanded | — | ✅ YES (1108 lines, 57 functions) |

### Effect shader naga results
- `temporal-feedback-zoom-tracer.wgsl` ✅
- `temporal-rgb-ghost.wgsl` ✅
- `temporal-phosphor-burn.wgsl` ✅
- `dimension-slicer.wgsl` ✅
- `prism-displacement.wgsl` ✅
- `xerox-degrade.wgsl` ✅
- `holographic-flicker.wgsl` ✅
- `chroma-vortex.wgsl` ✅

### Generative shader naga results
- `gen-celestial-weave.wgsl` ✅
- `gen-magnetic-kelp.wgsl` ✅
- `gen-neon-snowfall.wgsl` ✅
- `gen-echo-dunes.wgsl` ✅
- `gen-luminous-cauldron.wgsl` ✅
- `generative-turing-veins.wgsl` ✅
- `gen-opal-circuit.wgsl` ✅
- `gen-bioreactor-bloom.wgsl` ✅

### Hybrid shader & JSON results
- `hyb-temporal-fbm-ghost.wgsl` ✅
- `hyb-chromatic-circuit.wgsl` ✅
- `shader_definitions/hybrid/hyb-temporal-fbm-ghost.json` ✅
- `shader_definitions/hybrid/hyb-chromatic-circuit.json` ✅

### Notes
- `generate_shader_lists.js` emitted one pre-existing warning for `gen-showcase-nebula-core` (unexpected workgroup_size 8x8); this is unrelated to Phase C and did not block generation.
- All 14 shader list JSON files were regenerated successfully.
