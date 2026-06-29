# Phase F Agent Swarm Registry — WGSL Audit Fix Pass

**Status:** ✅ COMPLETE  
**Started:** 2026-06-28  
**Completed:** 2026-06-29  
**Goal:** Fix critical issues discovered by the Phase F comprehensive WGSL audit.

---

## Audit Results

**Comprehensive audit script:** `scripts/phase_f_audit.py`  
**Reports:**
- `reports/phase-f-audit-report.json`
- `reports/phase-f-audit-report.md`

**Summary (1,260 shaders audited):**
| Severity | Count |
|----------|------:|
| ✅ PASS | 949 |
| ⚠️ WARNING | 311 |
| 🚨 CRITICAL | 0 |
| Naga failures | 0 |

**Issue breakdown (remaining warnings only):**
- **ALPHA:** 311 hardcoded `alpha = 1.0` warnings in non-generative shaders (intentional/acceptable)
- **DEPTH:** 0 missing `writeDepthTexture` stores
- **JSON:** 0 missing JSON definitions
- **BINDING:** 0 `ripples` array size/type mismatches
- **WORKGROUP:** 1 intentional deep-workgroup shader flagged as warning

---

## Fix Plan

### Agent 1f — Binding Fix Specialist ✅ COMPLETE
**Target:** Fix the 11 shaders with `ripples` array size/type mismatch.

Shaders:
1. `digital-moss`
2. `fabric-zipper`
3. `flux-core`
4. `foil-impression`
5. `ink-bleed`
6. `nano-assembler`
7. `paper-cutout`
8. `rgb-delay-brush`
9. `rgb-iso-lines`
10. `scanline-tear`
11. `sequin-flip`

**Fix:** Ensure `struct Uniforms` contains exactly:
```wgsl
struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
```

### Agent 2f — Depth Write Fix Specialist ✅ COMPLETE
**Target:** Add missing `writeDepthTexture` stores to all 86 affected shaders.

Split into 2 batches:
- **Batch A (first 43):** astral-kaleidoscope-morph through gen-quantum-entangled-ferrofluid-engine
- **Batch B (remaining 43):** gen-quantum-fluorescent-aether-moth-swarm through zipper-reveal

**Fix:** Add `textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_value, 0.0, 0.0, 0.0));` where `depth_value` is:
- `0.0` for generative shaders
- Pass-through of `textureSampleLevel(readDepthTexture, ...).r` for image/video effects
- Or derived from the effect's depth/alpha if appropriate

### Agent 3f — Alpha Handling Fix Specialist ✅ COMPLETE
**Target:** Fix hardcoded `alpha = 1.0` in the 97 critical shaders that had ALPHA issues.

**Fix:**
- For image/video effects: preserve input alpha (`sampled_color.a`) or compute alpha from effect strength.
- For generative shaders: keep `alpha = 1.0` (no change).
- Ensure final `textureStore(writeTexture, ..., vec4<f32>(rgb, alpha))` uses calculated alpha.

### Agent 4f — JSON Definition Creator ✅ COMPLETE
**Target:** Create missing JSON definitions for critical shaders without them.

Focus on the subset of the 89 missing-JSON shaders that were flagged as CRITICAL. Extracted category from shader-lists or shader header and used existing JSON files as schema reference.

### Agent 5f — QA & Integration ✅ COMPLETE
**Target:** Re-run `python3 scripts/phase_f_audit.py`, confirm critical count drops, update registry.

---

## QA Results

- **Final audit counts:** PASS 949, WARNING 311, CRITICAL 0, Naga failures 0
- **Fixes applied:**
  - 11 binding fixes
  - 86 depth-write fixes
  - 25 alpha fixes (critical ALPHA shaders)
- **Warning backlog:** `agents/swarm-outputs/phase-f-warning-backlog.md`
- **Shader-list regeneration:** `node scripts/generate_shader_lists.js` completed successfully on 2026-06-29.

---

## Success Criteria

- ✅ All 11 BINDING issues resolved.
- ✅ All 86 DEPTH issues resolved.
- ✅ Critical ALPHA issues resolved (0 critical shaders with ALPHA issue).
- ✅ Missing JSON definitions created for critical shaders.
- ✅ Re-audit shows critical count = 0 (all fixable critical issues resolved).
- ✅ `node scripts/generate_shader_lists.js` succeeds.
- ✅ Registry marked ✅ COMPLETE.
