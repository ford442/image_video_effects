# Agent 5A: Quality Assurance & Integration
## Task Specification - Phase A, Agent 5

**Role:** Final Review & Standardization  
**Priority:** CRITICAL (Final Gate)  
**Target:** All Phase A outputs  
**Estimated Duration:** 2-3 days

---

## Mission

Final review of all Phase A shader outputs for consistency, correctness, and compliance with project standards. This is the **final gate** before Phase B begins.

---

## Review Scope

### Shaders to Review

1. **Upgraded Shaders** (from Agent 1A)
   - 9 Tiny shaders with RGBA upgrades
   - 52 Small shaders with RGBA upgrades

2. **Hybrid Shaders** (from Agent 2A)
   - 10 new hybrid shaders

3. **Generative Shaders** (from Agent 4A)
   - 10 new generative shaders

4. **Validation Fixes** (from Agent 3A)
   - All randomization safety fixes

**Total: 81+ shader files to review**

---

## Review Checklist

### 1. Header Compliance

Every shader MUST have:

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  {SHADER_NAME}
//  Category: {CATEGORY}
//  Features: {comma-separated list}
//  {Upgraded/Created}: 2026-03-22
//  By: {Agent X}
// ═══════════════════════════════════════════════════════════════════
```

Check:
- [ ] Header present and properly formatted
- [ ] Category matches actual category
- [ ] Features accurately describe capabilities
- [ ] Date and agent attribution present

### 2. Binding Compliance

Every shader MUST declare exactly these 13 bindings in this order:

```wgsl
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
```

Check:
- [ ] All 13 bindings present
- [ ] Correct order
- [ ] Correct types
- [ ] No missing or extra bindings

### 3. Uniforms Structure

Every shader MUST have:

```wgsl
struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};
```

Check:
- [ ] Exact field names
- [ ] Exact types
- [ ] Array size of 50 for ripples

### 4. Workgroup Size

Every compute shader MUST use:

```wgsl
@compute @workgroup_size(8, 8, 1)
```

Check:
- [ ] Annotation present
- [ ] Exact size (8, 8, 1)

### 5. RGBA Output Compliance

Every shader MUST:

```wgsl
// Write to color texture
let finalColor = vec3<f32>(...); // Your calculated color
let alpha = calculateAlpha(...); // NOT hardcoded 1.0 (except generative)
textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));

// Write to depth texture
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
```

Check:
- [ ] Both writeTexture AND writeDepthTexture written to
- [ ] Alpha calculated (not hardcoded) for non-generative shaders
- [ ] Alpha = 1.0 acceptable for generative shaders
- [ ] Depth value properly passed through or modified

### 6. Randomization Safety

Verify (from Agent 3A's work):

```wgsl
// Check for and verify fixes:
- Division by parameter → Has epsilon guard
- Log of parameter → Has minimum or offset
- Pow with zero base → Base is protected
- Sqrt of negative → Clamped to >= 0
- Alpha negative → Has minimum value
```

Check:
- [ ] No division by zero possible
- [ ] No log(0) possible
- [ ] No sqrt(negative) possible
- [ ] Alpha always >= 0.1 (or generative with alpha=1.0)
- [ ] All parameters produce valid output at extremes

### 7. JSON Definition Compliance

Every shader MUST have a JSON definition:

```json
{
  "id": "kebab-case-name",
  "name": "Display Name",
  "url": "shaders/filename.wgsl",
  "category": "one-of-12-categories",
  "description": "Brief description",
  "tags": ["tag1", "tag2"],
  "features": ["feature1", "feature2"],
  "params": [
    {
      "id": "paramName",
      "name": "Display Name",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ]
}
```

Check:
- [ ] JSON file exists at correct path
- [ ] ID matches filename (without extension)
- [ ] URL points to correct location
- [ ] Category is valid
- [ ] All params have required fields
- [ ] No duplicate IDs across all shaders

### 8. Code Style

Check:
- [ ] Consistent 2-space indentation
- [ ] Descriptive variable names
- [ ] Comments for complex sections
- [ ] No dead/unused code
- [ ] Consistent brace style

### 9. Performance Check

Static analysis for:

```wgsl
// Check for potential performance issues:
- [ ] Unbounded loops → Should have fixed iteration counts
- [ ] Expensive operations in loops → Minimized
- [ ] Redundant texture samples → Cached in variables
- [ ] Excessive branching → Can be mix() instead?
```

### 10. Compilation Test

For each shader:
- [ ] No syntax errors
- [ ] All variables declared before use
- [ ] All functions defined before called
- [ ] Type consistency (no implicit conversions that fail)

---

## Review Process

### Step 1: Automated Checks

Create/use scripts to verify:
1. Header presence
2. Binding count and order
3. Uniforms struct correctness
4. Workgroup size
5. Write to both textures
6. JSON schema compliance
7. ID uniqueness

### Step 2: Manual Review

For each shader:
1. Read through code
2. Verify alpha calculation logic
3. Check parameter safety
4. Review JSON completeness
5. Note any issues

### Step 3: Issue Tracking

For each issue found, record:
- Shader ID
- Issue type (header, bindings, alpha, safety, etc.)
- Severity (critical, warning, suggestion)
- Suggested fix

### Step 4: Fix Verification

After issues are fixed, re-verify:
- Original issue is resolved
- No new issues introduced

---

## Output Deliverables

### 1. QA Report (`swarm-outputs/phase-a-qa-report.md`)

Structure:
```markdown
# Phase A Quality Assurance Report

## Summary
- Total Shaders Reviewed: 81
- Passed: 75
- Issues Found: 12
- Fixed: 12

## Shaders by Agent

### Agent 1A (RGBA Upgrades)
| Shader | Status | Issues | Notes |
|--------|--------|--------|-------|
| texture | ✅ PASS | None | |
| gen_orb | ⚠️ FIXED | Missing depth write | Fixed |
| ... | | | |

### Agent 2A (Hybrids)
| Shader | Status | Issues | Notes |
|--------|--------|--------|-------|
| hybrid-noise-kaleidoscope | ✅ PASS | None | |
| ... | | | |

### Agent 4A (Generative)
| Shader | Status | Issues | Notes |
|--------|--------|--------|-------|
| gen-neural-fractal | ✅ PASS | None | |
| ... | | | |

## Common Issues Found

### Issue Type: Missing Depth Write
Count: 5 shaders
Fix: Add `textureStore(writeDepthTexture, ...)`

### Issue Type: Hardcoded Alpha
Count: 3 shaders
Fix: Implement luminance-based alpha

## Category Distribution

| Category | Count | New | Upgraded |
|----------|-------|-----|----------|
| generative | 20 | 10 | 10 |
| artistic | 15 | 2 | 13 |
| ... | | | |
```

### 2. Fixed Shader Files

Collection of any shader files that needed fixes.

### 3. Integration Summary

```markdown
## Phase A Integration Complete

### New Shaders Added: 20
- 10 Generative
- 10 Hybrids

### Shaders Upgraded: 61
- 9 Tiny
- 52 Small

### All Shaders Pass:
- ✅ Header compliance
- ✅ Binding compliance
- ✅ Uniforms structure
- ✅ Workgroup size
- ✅ RGBA output
- ✅ Randomization safety
- ✅ JSON definitions
- ✅ ID uniqueness

### Ready for Phase B: YES
```

---

## Success Criteria

- All 81+ shaders reviewed
- 100% header compliance
- 100% binding compliance
- 100% RGBA output compliance
- 0 critical issues remaining
- QA report generated
- Phase A marked complete

---

## Gate Criteria for Phase B

Phase B can begin when:

1. All shaders pass automated checks
2. Manual review complete with no critical issues
3. All warnings addressed or documented
4. QA report approved
5. Integration summary confirms readiness

---

## Tools

### WGSL Syntax Check (conceptual)
```bash
# Use tint or naga for validation
tint --format wgsl shader.wgsl
naga shader.wgsl
```

### JSON Validation
```bash
# Schema validation
# Check for duplicate IDs
```

### Text Extraction
```bash
# Extract headers
# Count bindings
# Check uniform struct
```
