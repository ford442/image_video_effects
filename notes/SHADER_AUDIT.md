# Shader Audit & Improvement Projects

**Date**: 2025-12-09  
**Branch**: main-edit

---

## Summary

Reviewed 63 WGSL shader files in `public/shaders/`. This document tracks shaders that:

1. **Broken** - Don't compile or render correctly
2. **Underperforming** - Work but miss their intended effect
3. **Enhancement Opportunities** - Work well but could be improved

---

## 🔴 Critical Issues (Broken Shaders)

### 1. `spectral-vortex.wgsl`

**Status**: Uses deprecated binding names  
**Issue**: Uses old binding names like `readTexture`, `writeTexture`, `u_sampler` instead of standard `videoTex`, `outTex`, `videoSampler`.  
**Impact**: May work due to same binding indices, but inconsistent with project conventions.  
**Fix**: Update binding variable names to match standard pattern.

---

## 🟡 Shaders Missing Intended Functionality

### 2. `rainbow-cloud.wgsl`

**Status**: Works but feedback effect is weak  
**Issue**: The `temporalBlend` is hardcoded to `0.9` instead of using the `persistence` parameter from uniforms.  
**Fix**: Change line 174 from:

```wgsl
let temporalBlend = 0.9;
```

to:

```wgsl
let temporalBlend = persistence;
```

---

### 3. `chromatic-folds.wgsl`

**Status**: Works but feedback is inverted  
**Issue**: The `feedbackStrength` parameter creates a blend where high values = less current frame visibility (inverted intuition). Users expect high values = more trails.  
**Fix**: Invert the blend at line 188 to `mix(prev, foldedColor, 1.0 - feedbackStrength)` or rename the parameter to "Current Frame Mix".

---

### 4. `quantum-wormhole.wgsl`

**Status**: Works but "void pockets" rarely trigger  
**Issue**: The condition `if (hsv.z < voidThreshold)` on line 160 checks value (brightness), but typical video rarely has values below 0.1-0.4 threshold. The void effect almost never activates.  
**Fix**: Consider using luminance instead: `let lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));` and checking `if (lum < voidThreshold)`.

---

## 🟢 Enhancement Opportunities

### 5. `neural-resonance.wgsl`

**Status**: Works well  
**Opportunity**: The curl noise calculation samples the feedback texture 8 times per pixel (4 for gradient, then 4 more for curl). This could be optimized:

- Cache `luminanceGradient` results
- Consider computing curl in a separate pass for performance on lower-end GPUs

---

### 6. `quantum-smear.wgsl`

**Status**: Works well  
**Opportunity**: The "anti-matter voids" effect is sparse (only triggers when `voidNoise > 0.85`). Could add a "void frequency" parameter to control this distribution.

---

### 7. `chromatic-crawler.wgsl`

**Status**: Works well  
**Opportunity**:

- The 6 color swap patterns are randomly selected per-region. Could add a "pattern lock" mode where user picks which pattern to use globally.
- Flash effect at line 221 is very aggressive - could benefit from a `flashIntensity` parameter.

---

### 8. `aurora-rift.wgsl` & `aurora-rift-2.wgsl`

**Status**: Works well  
**Opportunity**: These two shaders are very similar (85%+ code overlap). Consider:

- Merging into a single shader with a "variant" uniform
- Or clearly documenting the differences (aurora-rift-2 has improved hypercube noise and spectralPower, aurora-rift has different parameter ranges)

---

### 9. All New Psychedelic Shaders

**Status**: Untested at runtime  
**Risk**: The following shaders were recently added and need runtime validation:

- `nebulous-dream.wgsl`
- `ethereal-swirl.wgsl`
- `quantum-foam.wgsl`
- `aurora-rift.wgsl`
- `aurora-rift-2.wgsl`
- `astral-kaleidoscope.wgsl`
- `chromatic-manifold-2.wgsl`
- `chromatic-folds-2.wgsl`

**Action**: Test each in the live app to verify they compile and produce visible effects.

---

## 🔧 Code Quality Issues

### 10. Mixed Binding Naming Conventions

**Issue**: Most shaders use `videoTex`/`videoSampler`/`depthTex` but older shaders like `spectral-vortex.wgsl` use `readTexture`/`u_sampler`.  
**Fix**: Standardize all shaders to use the same variable names for bindings.

---

### 11. Inconsistent `Uniforms` struct member ordering

**Issue**: Some shaders use `config, zoom_params, zoom_config, ripples` order, others use `config, foam_params, quantum_params, ripples`. The underlying binding is the same, but different semantic names are confusing.  
**Recommendation**: Standardize on `config, params, advanced_params, ripples` or similar.

---

### 12. Hash Function Quality

**Issue**: Several shaders have hash functions that may produce visible patterns on some GPUs:

- `astral-veins.wgsl` - Recently fixed but uses custom hash
- Many shaders use `fract(sin(dot(p, ...)) * 43758.5453)` which has known periodicity issues

**Enhancement**: Consider adopting a consistent, high-quality hash like:

```wgsl
fn pcg_hash(n: u32) -> u32 {
    var h = n * 747796405u + 2891336453u;
    h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
    return (h >> 22u) ^ h;
}
```

---

## Priority Action Items

| Priority | Item | Effort | Status |
|----------|------|--------|--------|
| 🔴 High | Fix `spectral-vortex.wgsl` binding names | 15 min | ✅ Done |
| 🔴 High | Fix `rainbow-cloud.wgsl` persistence parameter | 5 min | ✅ Done |
| 🔴 High | Fix `quantum-wormhole.wgsl` void threshold | 10 min | ✅ Done |
| 🟡 Medium | Fix `chromatic-folds.wgsl` feedback blend | 5 min | ✅ Done |
| 🟡 Medium | Test all new psychedelic shaders | 30 min | ⏳ Pending |
| 🟢 Low | Add `flashIntensity` param to `chromatic-crawler.wgsl` | 15 min | ✅ Done |
| 🟢 Low | Make `quantum-smear.wgsl` void frequency controllable | 10 min | ✅ Done |
| 🟢 Low | Optimize `neural-resonance.wgsl` texture samples | 30 min | ✅ Done (16→4 samples) |
| 🟢 Low | Standardize hash functions across all shaders | 2 hours | ✅ Library created (`_hash_library.wgsl`) |

---

## Notes

- All shaders use the same 13-binding layout (videoSampler, videoTex, outTex, uniforms, depthTex, depthSampler, outDepth, feedbackOut/historyBuf, normalBuf/unusedBuf, feedbackTex/historyTex, extraBuffer, compSampler, plasmaBuffer)
- HDR output is supported (rgba32float) so negative and >1.0 values are valid
- Depth texture provides per-pixel depth for parallax/3D effects
- Feedback textures enable temporal persistence effects
