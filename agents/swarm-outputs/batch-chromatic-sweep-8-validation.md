# Batch Chromatic Sweep — 8 Shaders Validation Report

**Date:** 2026-06-06
**Agent:** Kimi Claw (4 parallel subagents)
**Scope:** 8 generative shaders with ACES + dataTextureA but no chromatic aberration

---

## Summary

| Check | Result |
|-------|--------|
| naga (8/8) | ✅ Pass |
| generate_shader_lists.js | ✅ Pass (14 lists) |
| check_duplicates.js | ✅ Pass (0 duplicates) |
| Duplicate ACES | 3 found + fixed during sweep |

---

## Shader Details

| # | Shader ID | Lines Before | Lines After | Depth in caStr | Fixed dup ACES |
|---|-----------|-------------:|------------:|:--------------:|:--------------:|
| 1 | neon-fern-garden | 260 | 262 | ✅ Yes (frond Y + alpha) | No |
| 2 | aurora-borealis-loom | 234 | 236 | ✅ Yes (curtain/weave) | No |
| 3 | morphogenic-resonance | 228 | 230 | ✅ Yes (morph field dist) | No |
| 4 | solar-flare-cascade | 225 | 227 | ✅ Yes (presence/coreGlow) | No |
| 5 | crystalline-fracture | 180 | 182 | ✅ Yes (readDepthTexture) | ✅ `aces_tone_map` → `acesToneMap` |
| 6 | topological-acoustic-knots | 175 | 178 | ❌ No | No |
| 7 | gen-molten-planetary-core | 171 | 173 | ✅ Yes (nz * onSphere) | ✅ `aces` → `acesToneMap` |
| 8 | emergent-calligraphic-weave | 165 | 167 | ✅ Yes (readDepthTexture) | ✅ `aces_tone_map` → `acesToneMap` |

**Notes:**
- 6/8 shaders used a meaningful `depth` value in `caStr`.
- 2/8 used bass-only CA (`topological-acoustic-knots` has no depth var).
- 3 shaders had **duplicate/non-canonical ACES functions** that were cleaned up:
  - `crystalline-fracture`: removed `aces_tone_map`, unified to `acesToneMap`
  - `gen-molten-planetary-core`: removed `aces`, unified to `acesToneMap`
  - `emergent-calligraphic-weave`: removed `aces_tone_map`, unified to `acesToneMap`
- All 8 shaders already had audio (`plasmaBuffer[0].xyz`) and mouse (`zoom_config.yz`) plumbed.
- No JSON changes needed — chromatic is not a feature flag.

---

## Pattern Used

```wgsl
let caStr = 0.003 * (1.0 + bass) + depth * 0.001;  // depth optional
color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);
```

Inserted after color computation, before ACES tone mapping.

---

## Blockers / Issues

- None. All 8 shaders validated cleanly.

## Remaining Gap

- 54 generative shaders still have ACES + dataA but no chromatic (down from ~169 at start of sprint).
