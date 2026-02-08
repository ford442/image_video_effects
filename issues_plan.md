# Mouse-Driven Shader Issues - Action Plan

## Overview
Analysis revealed significant issues with mouse-driven shader functionality. Many shaders marked as `mouse-driven` either don't exist, use wrong shader types, or aren't properly configured to receive mouse data.

---

## Issue Categories

### 🟡 Issue 1: Stale JSON References (2 shaders)

**Status:** LOW PRIORITY - WIP/Incomplete

**Git History Check:** Jules Coding Agent confirmed these shaders were **never committed**.

**Finding:**
- `prism-displacement.wgsl` - No git history
- `pixel-repel.wgsl` - No git history

These are stale JSON definitions for planned/incomplete shaders. The app gracefully handles missing shaders - they simply don't appear in the UI lists.

**Options:**
1. **Create the shaders** from JSON specifications
2. **Remove the JSON files** to clean up stale references
3. **Leave as-is** - harmless, just won't appear in UI

**Recommended Action:** Remove or mark as WIP in JSON

```bash
# To remove stale references:
rm shader_definitions/distortion/prism-displacement.json
rm shader_definitions/interactive-mouse/pixel-repel.json
```

---

### 🔴 Issue 2: Fragment Shaders Using Wrong Pipeline (2 shaders) ✅ FIXED

**Status:** FIXED - Files Updated

**Changes Made:**

Two shaders are marked as `mouse-driven` but use `@fragment` instead of `@compute`. They use a custom uniform structure incompatible with the compute pipeline.

**Affected Shaders:**
1. `radial-hex-lens.wgsl` - Uses custom Uniforms struct, expects render pipeline
2. `sphere-projection.wgsl` - Uses custom Uniforms struct, expects render pipeline

**Problem:**
```wgsl
// Current (WRONG):
struct Uniforms {
    time: f32,
    resolution: vec2<f32>,
    mouse: vec2<f32>,  // Custom field
    ...
};
@fragment fn main(...) -> @location(0) vec4<f32> { ... }
```

**Files Modified:**
- `public/shaders/radial-hex-lens.wgsl` - Converted to compute shader
- `public/shaders/sphere-projection.wgsl` - Converted to compute shader

**Key Changes:**
1. Added standard compute shader header with all 13 required bindings
2. Changed uniform struct to standard format:
   - `config: vec4<f32>` - Time, FrameCount, ResX, ResY
   - `zoom_config: vec4<f32>` - MouseX (y), MouseY (z), MouseDown (w)
   - `zoom_params: vec4<f32>` - Shader-specific parameters
   - `ripples: array<vec4<f32>, 50>` - Ripple data
3. Changed `@fragment` to `@compute @workgroup_size(8, 8, 1)`
4. Changed entry point to use `global_id: vec3<u32>`
5. Added bounds checking: `if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }`
6. Changed `textureSample()` to `textureSampleLevel(..., 0.0)`
7. Changed output from `return vec4<f32>(...)` to `textureStore(writeTexture, global_id.xy, ...)`
8. Added depth texture output

**Action Items:**
- [x] Convert `radial-hex-lens.wgsl` to compute shader
- [x] Convert `sphere-projection.wgsl` to compute shader
- [ ] Test both shaders after conversion

---

### 🟡 Issue 3: Shaders Reading Mouse But Not Marked (95 shaders)

**Status:** MEDIUM PRIORITY

95 shaders read `zoom_config.yz` expecting mouse coordinates but are NOT marked as `mouse-driven`. The renderer sends `farthestPoint` data instead of mouse position.

**Renderer Logic:**
```typescript
if (isMouseDriven || isInfiniteZoom) {
    // Sends mouse position
    uniformArray.set([currentTime, targetX, targetY, zoomConfigW], 4);
} else {
    // Sends farthestPoint data (WRONG for these shaders!)
    uniformArray.set([targetX, targetY, zoomConfigW, 0.0], 4);
}
```

**Affected Shaders (partial list):**
- `ambient-liquid` (artistic)
- `boids` (artistic/simulation)
- `rainbow-cloud` (generative)
- `reaction-diffusion` (simulation)
- `wave-equation` (simulation)
- `magnetic-dipole`
- `multi-turing`
- `navier-stokes-dye`
- `physarum`
- `voronoi-dynamics`
- ...and 85 more

**Action Items:**
- [ ] Add `"features": ["mouse-driven"]` to each affected JSON
- [ ] Verify each shader actually uses mouse meaningfully
- [ ] Test batch of shaders after fixing

---

### 🟡 Issue 4: Filename Mismatch (1 shader)

**Status:** LOW PRIORITY

`interactive-frost.json` references `shaders/frost-reveal.wgsl` which exists, but the ID mismatch may cause confusion.

**Fix Options:**
1. Rename JSON to `frost-reveal.json`
2. Or update URL in JSON to point to correct shader

**Action Items:**
- [ ] Fix filename consistency

---

## Investigation: Finding Missing WGSL Files

### Git History Search
```bash
# Search git history for deleted WGSL files
git log --all --full-history -- "*.wgsl" --oneline

# Show all commits that touched a specific shader
git log --all --full-history -- "public/shaders/prism-displacement.wgsl"

# Check for stashed changes
git stash list

# Check for uncommitted changes
git status
```

### Repository Check
```bash
# Find all WGSL files actually present
find public/shaders -name "*.wgsl" | wc -l

# Compare with JSON definitions
find shader_definitions -name "*.json" | wc -l
```

### Jules Coding Agent Query
Questions for Jules:
1. Were WGSL files generated for the 230+ missing shader definitions?
2. Are there source files or templates we can use to regenerate them?
3. Which shaders were actually completed vs. just defined in JSON?

---

## Fix Priority Order

1. **P0 (Critical):** Fix fragment shaders ✅ DONE
2. **P1 (High):** Add mouse-driven flag to 95 shaders
3. **P2 (Low):** Remove stale JSON refs (optional)

**Note:** The "missing" WGSL files were confirmed to be incomplete work-in-progress shaders that never existed in the repo. No recovery needed.

---

## Quick Stats

| Category | Count |
|----------|-------|
| Total shader JSON definitions | 532 |
| Existing WGSL files | 528 |
| Stale/incomplete JSON refs | 2 |
| Fragment shaders fixed | 2 |
| Shaders needing mouse-driven flag | 95 |

---

## Quick Commands for Investigation

```bash
# Count actual WGSL files vs JSON definitions
find public/shaders -name "*.wgsl" | wc -l
find shader_definitions -name "*.json" | wc -l

# Find all JSON files marked mouse-driven without WGSL files
for f in shader_definitions/*/*.json; do
  id=$(basename "$f" .json)
  [ -f "public/shaders/${id}.wgsl" ] || echo "Missing: $id"
done

# Search git for deleted shader files
git log --all --full-history --diff-filter=D -- "public/shaders/*.wgsl" --oneline

# Check if shaders were moved/renamed
git log --all --full-history --summary -- "public/shaders/*.wgsl" | grep -E "(rename|delete)"
```

---

## Testing Checklist

After each fix batch:
- [ ] Run `npm start` without errors
- [ ] Check browser console for WGSL compilation errors
- [ ] Test 3-5 mouse-driven shaders from each category
- [ ] Verify mouse position updates correctly
- [ ] Test mouse click/hold interactions
