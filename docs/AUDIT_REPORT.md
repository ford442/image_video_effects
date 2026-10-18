# WGSL Shader Repository Audit Report

**Audit Date:** 2026-05-31
**Repository:** `/root/image_video_effects`
**Total Shader Definitions:** 1,116
**Duplicate IDs:** 0 ✅

---

## 1. Shader Counts Per Category

| Category | Count | Avg Lines | Notes |
|----------|------:|----------:|-------|
| `generative` | 310 | 185 | Largest category; many legacy shaders missing ACES |
| `interactive-mouse` | 238 | 132 | Shortest on average; mostly mouse-driven effects |
| `artistic` | 101 | 179 | Creative filters; moderate complexity |
| `image` | 89 | 148 | Image/video processing; good upgrade candidates |
| `advanced-hybrid` | 87 | 199 | Most complex; highest average line count |
| `simulation` | 47 | 177 | Physics sims; often use non-standard workgroups |
| `visual-effects` | 46 | 138 | Visual/glitch; relatively short |
| `distortion` | 61 | 152 | Spatial warps; moderate length |
| `retro-glitch` | 35 | 165 | Retro aesthetics; mixed upgrade status |
| `post-processing` | 28 | 132 | Final-pass effects; mostly modern |
| `liquid-effects` | 30 | 159 | Fluid simulations; some use (8,8,1) |
| `lighting-effects` | 17 | 184 | Plasma/glow; complex |
| `geometric` | 16 | 153 | Patterns/tessellations; moderate |
| `hybrid` | 11 | 172 | Combined techniques; small but dense |

**Total WGSL files in `public/shaders/`:** ~1,200 (including templates and non-shader utilities)
**Valid shader definitions tracked:** 1,116

---

## 2. Estimated Upgrade Difficulty Per Category

| Category | Difficulty | Rationale |
|----------|-----------|-----------|
| `generative` | **Easy → Medium** | 263/310 lack ACES, but most are short (avg 185). Many already have chromatic + dataTextureC. |
| `interactive-mouse` | **Easy** | Shortest avg (132 lines). Most have standard structure. Low-hanging fruit. |
| `image` | **Easy → Medium** | Avg 148 lines. Many missing ACES + chromatic + dataTextureC, but structure is clean. |
| `post-processing` | **Easy** | Short (132 avg). Usually final passes with simple logic. |
| `visual-effects` | **Easy** | Short (138 avg). Glitch/chromatic effects naturally fit upgrades. |
| `distortion` | **Medium** | Spatial math can be tricky to augment with chromatic/depth. |
| `retro-glitch` | **Medium** | Retro aesthetic sometimes conflicts with "modern" HDR/ACES look. |
| `artistic` | **Medium** | Creative filters often have complex color logic that needs careful ACES integration. |
| `simulation` | **Hard** | Physics sims often use non-standard workgroups and shared memory. Fragile to modify. |
| `liquid-effects` | **Hard** | Many use (8,8,1) workgroup size. Fluid sim logic is sensitive to changes. |
| `lighting-effects` | **Medium → Hard** | Complex plasma/glow math. Long shaders (184 avg). |
| `advanced-hybrid` | **Hard** | Longest avg (199 lines). Multi-technique combinations are brittle. |
| `geometric` | **Medium** | Pattern math is often tightly coupled; chromatic can interfere. |
| `hybrid` | **Medium** | Small category but dense logic. |

---

## 3. The 5 Most Common Legacy Patterns

### Pattern 1: Hardcoded Alpha = 1.0
- **Prevalence:** 382 shaders (34% of repository)
- **Impact:** Prevents proper alpha blending in multi-slot chains
- **Fix:** Replace `vec4<f32>(color, 1.0)` with semantic alpha (e.g., `intensity * depth`)

### Pattern 2: Missing ACES Tone Mapping
- **Prevalence:** ~1,017 shaders (91% of repository)
- **Impact:** Colors clip at 1.0; no HDR handling; flat-looking output
- **Fix:** Add `acesToneMap()` function and apply before final output

### Pattern 3: Non-Standard Workgroup Sizes
- **Prevalence:** 104 shaders use `(8, 8, 1)`; 4 use other sizes
- **Impact:** Suboptimal GPU occupancy; potential dispatch mismatches
- **Fix:** Migrate to `(16, 16, 1)` unless shared memory or atomic ops require otherwise

### Pattern 4: if-else Chains Instead of Branchless select()/mix()
- **Prevalence:** ~400+ shaders use 3+ `if` statements; ~200 use 5+
- **Impact:** Shader divergence on GPU; slower execution
- **Fix:** Replace palette lookups and conditional logic with `select()`, `mix()`, `step()`

### Pattern 5: Missing Chromatic Aberration
- **Prevalence:** ~900+ shaders (81% of repository)
- **Impact:** Visual flatness; no RGB channel separation for realism/artistic effect
- **Fix:** Add per-channel UV offsets based on intensity/bass/depth

---

## 4. The 5 Most "Modern" Shaders (Use as Templates)

These shaders have **all 5 modern features**: ACES tone mapping, chromatic aberration, `plasmaBuffer` audio reactivity, `readDepthTexture` depth awareness, and `dataTextureC` temporal feedback.

| Rank | Shader | Lines | Category | Why It's a Good Template |
|------|--------|------:|----------|-------------------------|
| 1 | `predator-camouflage` | 126 | image | Shortest all-feature shader. Clean structure. Easy to read. |
| 2 | `digital-lens` | 130 | image | Elegant chromatic + depth parallax. Well-commented. |
| 3 | `tilt-shift` | 130 | image | Classic effect with all upgrades integrated naturally. |
| 4 | `rotoscope-ink` | 131 | image | Artistic filter with proper HDR handling and depth edge boost. |
| 5 | `cyber-physical-portal` | 132 | image | Complex effect kept readable. Good example of semantic alpha. |

**Honorable mentions (generative):**
- `gen-conway-game-of-life` (136 lines) — cellular automaton with all features
- `gen-langton-ant` (136 lines) — emergent pattern with heat-map + temporal trails
- `gen-turing-morphogenesis` (145 lines) — reaction-diffusion with depth-aware pattern scale

---

## 5. Repository Health Metrics

| Metric | Value | Status |
|--------|------:|--------|
| Total shader definitions | 1,116 | ✅ Healthy |
| Duplicate IDs | 0 | ✅ Clean |
| Shaders with standard header | ~1,100 (99%) | ✅ Excellent |
| Shaders with plasmaBuffer | ~1,115 (99.9%) | ✅ Excellent |
| Shaders with readDepthTexture | ~1,108 (99.3%) | ✅ Excellent |
| Shaders with ACES | 99 (8.9%) | ⚠️ Needs work |
| Shaders with chromatic aberration | ~216 (19.4%) | ⚠️ Needs work |
| Shaders with dataTextureC usage | ~350 (31.4%) | ⚠️ Needs work |
| Shaders with hardcoded alpha | 382 (34.2%) | ⚠️ Needs work |
| Shaders with standard workgroup | 1,105 (99%) | ✅ Excellent |
| Non-standard workgroups | 104 (9.3% use 8,8,1) | ⚠️ Minor issue |

---

## 6. Upgrade Batch Files Created

### `upgrade_batches/batch_1_image.json`
- **10 image shaders** selected as easiest upgrade targets
- All have: standard workgroup, plasmaBuffer, readDepthTexture
- All missing: ACES + chromatic + dataTextureC
- All have: hardcoded alpha = 1.0
- Average length: 138 lines
- Estimated upgrade time: ~15 min per shader

### `upgrade_batches/batch_1_generative.json`
- **10 generative shaders** selected as easiest upgrade targets
- All have: standard workgroup, plasmaBuffer, readDepthTexture, chromatic, dataTextureC
- All missing: **only ACES** (single-feature upgrade)
- All have: hardcoded alpha = 1.0
- Average length: 96 lines
- Estimated upgrade time: ~10 min per shader

---

## 7. Special Cases

### Shaders Without readDepthTexture (8 total)
These are multi-pass shaders where depth is handled in a different pass:
- `astral-kaleidoscope-morph`
- `aurora-rift-2-pass1`, `aurora-rift-2-pass2`
- `aurora-rift-pass1`, `aurora-rift-pass2`
- `quantum-foam-pass1`, `quantum-foam-pass2`, `quantum-foam-pass3`

### Shaders Without plasmaBuffer (1 total)
- `_hash_library.wgsl` — utility library, not a render shader

### Workgroup Size Breakdown
| Size | Count | Notes |
|------|------:|-------|
| `(16, 16, 1)` | 1,105 | Standard |
| `(8, 8, 1)` | 100 | Legacy; should migrate |
| `(64, 1, 1)` | 2 | 1D particle systems (boids) |
| `(256, 1, 1)` | 1 | Histogram/atomic template |
| `(16, 16, 4)` | 1 | Rare; verify compatibility |

---

## 8. Recommended Upgrade Priority

1. **Batch 1 (Immediate):** 20 easiest shaders (10 image + 10 generative) — low risk, high visual impact
2. **Batch 2 (Next):** `interactive-mouse` category — 238 short shaders, many missing ACES only
3. **Batch 3 (After):** `visual-effects` + `post-processing` — short, self-contained
4. **Batch 4 (Later):** `distortion` + `retro-glitch` — moderate complexity
5. **Batch 5 (Future):** `artistic` + `simulation` — complex, needs careful testing
6. **Batch 6 (Last):** `advanced-hybrid` + `liquid-effects` — highest risk, longest shaders

---

*Report generated by automated audit pipeline.*
