# Phase A Shader Upgrade Evaluator — Final Report

> **Agent:** EV-1A (Phase A Shader Upgrade Evaluator Swarm)  
> **Date:** 2026-04-18  
> **Project:** Pixelocity WebGPU Shader Effects  
> **Library Size:** 715 WGSL shaders  
> **Phase A Target:** 84 shaders (61 tiny/small RGBA upgrades + 10 hybrids + 13 generative)  
> **Phase A Completed & Evaluated:** 43 shaders  

---

## 1. Executive Summary

The Phase A upgrade swarm has completed evaluation of **43 shaders** from the original target of **84**. The weekly upgrade swarm (Batch 1) executed 43 upgrades spanning small image effects, generative shaders, and interactive-mouse shaders. All 43 completed shaders were subjected to the full EV-1A rubric.

### Grade Distribution

| Grade | Count | Percentage | Meaning |
|-------|-------|------------|---------|
| **A** (90–100) | 0 | 0.0% | — |
| **B** (75–89) | 41 | 95.3% | PASS — minor suggestions noted |
| **C** (60–74) | 2 | 4.7% | CONDITIONAL — must fix before Phase B |
| **D** (40–59) | 0 | 0.0% | — |
| **F** (0–39) | 0 | 0.0% | — |

### Overall Phase A Health: **PASS with 2 Conditional Fixes Needed**

- **95.3%** of evaluated shaders score Grade B or higher.
- **0** shaders scored Grade D or F.
- **2** shaders scored Grade C and require targeted fixes before Phase B launch:
  1. `echo-trace` — missing bindings, uniforms, and header
  2. `gen_psychedelic_spiral` — missing JSON definition entirely

Once these two issues are resolved, Phase A meets the launch-gate threshold of ≥90% Grade A or B (currently 95.3% already exceeds this).

---

## 2. Detailed Scores Table

All 43 evaluated shaders, sorted by score descending.

| Rank | Shader ID | Name | Category | Size (bytes) | Lines | Score | Grade |
|------|-----------|------|----------|-------------:|------:|------:|-------|
| 1 | `gen-xeno-botanical-synth-flora` | Xeno-Botanical Synth-Flora | generative | 4,030 | 89 | **85** | B |
| 2 | `gen-supernova-remnant` | Supernova Remnant | generative | 7,619 | 207 | **85** | B |
| 3 | `rgb-glitch-trail` | RGB Glitch Trail | image | 2,964 | 82 | **82** | B |
| 4 | `chroma-shift-grid` | Chroma Shift Grid | image | 2,936 | 74 | **82** | B |
| 5 | `selective-color` | Selective Color | image | 3,000 | 70 | **82** | B |
| 6 | `temporal-slit-paint` | Temporal Slit Paint | image | 2,831 | 67 | **82** | B |
| 7 | `signal-noise` | Signal Noise | image | 3,201 | 77 | **82** | B |
| 8 | `sonic-distortion` | Sonic Distortion | image | 3,247 | 76 | **82** | B |
| 9 | `galaxy-compute` | Galaxy Compute | image | 3,253 | 69 | **82** | B |
| 10 | `radial-rgb` | Radial RGB | interactive-mouse | 3,325 | 80 | **82** | B |
| 11 | `luma-echo-warp` | Luma Echo Warp | interactive-mouse | 3,277 | 79 | **82** | B |
| 12 | `gen-astro-kinetic-chrono-orrery` | Astro-Kinetic Chrono-Orrery | generative | 4,202 | 121 | **82** | B |
| 13 | `gen-raptor-mini` | Raptor Mini | generative | 4,057 | 96 | **82** | B |
| 14 | `gen-cosmic-web-filament` | Cosmic Web Filament | generative | 3,998 | 108 | **82** | B |
| 15 | `cymatic-sand` | Cymatic Sand | generative | 4,104 | 103 | **82** | B |
| 16 | `gen-vitreous-chrono-chandelier` | Vitreous Chrono-Chandelier | generative | 4,391 | 121 | **82** | B |
| 17 | `gen-crystal-caverns` | Crystal Caverns | generative | 4,497 | 118 | **82** | B |
| 18 | `gen-quantum-mycelium` | Quantum Mycelium | generative | 7,163 | 214 | **82** | B |
| 19 | `gen-stellar-web-loom` | Stellar Web-Loom | generative | 6,965 | 210 | **82** | B |
| 20 | `gen-cyber-terminal` | Procedural Cyber Terminal (ASCII) | generative | 9,790 | 265 | **82** | B |
| 21 | `gen-bioluminescent-abyss` | Bioluminescent Abyss | generative | 12,270 | 363 | **82** | B |
| 22 | `gen-chronos-labyrinth` | Chronos Labyrinth | generative | 14,430 | 406 | **82** | B |
| 23 | `gen-quantum-superposition` | Quantum Superposition Lattice | generative | 17,911 | 272 | **82** | B |
| 24 | `interactive-fisheye` | Interactive Fisheye | image | 2,734 | 73 | **82** | B |
| 25 | `radial-blur` | Radial Blur | image | 2,787 | 74 | **82** | B |
| 26 | `swirling-void` | Swirling Void | image | 2,853 | 78 | **82** | B |
| 27 | `static-reveal` | Static Reveal | image | 3,241 | 83 | **82** | B |
| 28 | `entropy-grid` | Entropy Grid | image | 2,804 | 76 | **82** | B |
| 29 | `digital-mold` | Digital Mold | image | 3,311 | 85 | **82** | B |
| 30 | `pixel-sorter` | Pixel Sorter | image | 3,067 | 80 | **82** | B |
| 31 | `magnetic-field` | Magnetic Field | image | 3,262 | 82 | **82** | B |
| 32 | `kaleidoscope` | Kaleidoscope | image | 3,460 | 76 | **82** | B |
| 33 | `synthwave-grid-warp` | Synthwave Grid | image | 2,976 | 77 | **82** | B |
| 34 | `sonar-reveal` | Sonar Reveal | interactive-mouse | 3,348 | 83 | **82** | B |
| 35 | `concentric-spin` | Concentric Spin | image | 3,039 | 81 | **82** | B |
| 36 | `interactive-fresnel` | Interactive Fresnel | visual-effects | 3,265 | 80 | **82** | B |
| 37 | `time-slit-scan` | Time Slit Scan | visual-effects | 2,708 | 69 | **82** | B |
| 38 | `double-exposure-zoom` | Double Exposure Zoom | image | 2,873 | 76 | **82** | B |
| 39 | `velocity-field-paint` | Velocity Field Paint | interactive-mouse | 3,047 | 73 | **82** | B |
| 40 | `pixel-repel` | Pixel Repeller | interactive-mouse | 3,226 | 81 | **82** | B |
| 41 | `lighthouse-reveal` | Lighthouse Reveal | image | 3,319 | 88 | **82** | B |
| 42 | `echo-trace` | Echo Trace | artistic | 3,012 | 77 | **73** | C |
| 43 | `gen_psychedelic_spiral` | gen_psychedelic_spiral | unknown | 4,364 | 106 | **69** | C |

### Score Summary Statistics

| Metric | Value |
|--------|-------|
| Mean Score | 81.6 |
| Median Score | 82 |
| Mode Score | 82 |
| Highest Score | 85 |
| Lowest Score | 69 |
| Standard Deviation | ~3.1 |

---

## 3. Findings by Dimension

### 3.1 RGBA Compliance (25 points max)

**Overall Pass Rate:** 100% of evaluated shaders write calculated alpha and store to `writeDepthTexture`.

| Sub-check | Pass / Total | Pass Rate |
|-----------|-------------:|----------:|
| `alpha_calculated` | 43 / 43 | 100% |
| `writes_depth` | 43 / 43 | 100% |
| `all_bindings` | 42 / 43 | 97.7% |
| `uniforms_ok` | 42 / 43 | 97.7% |
| `has_header` | 2 / 43 | 4.7% |

**Common Failures:**

1. **Missing Standard Header (41/43 = 95.3%)** — The vast majority of completed shaders lack the required standard header comment block (`// ═══════════════════════════════════════════════════════════════════` with shader name, category, features, date, agent). This is the single most prevalent deduction in Phase A. Each missing header costs 3 points, capping the RGBA score at 22 for otherwise-perfect shaders.

2. **Missing Bindings / Uniforms (1/43 = 2.3%)** — `echo-trace` is missing `all_bindings` and `uniforms_ok`, dropping its RGBA score to 13.

**RGBA Score Breakdown:**

| RGBA Score | Count | Notes |
|-----------:|------:|-------|
| 25 | 2 | Perfect RGBA compliance (both have header) |
| 22 | 40 | Missing header only (-3 pts) |
| 13 | 1 | `echo-trace` — missing bindings, uniforms, and header |

### 3.2 Randomization Safety (25 points max)

**Overall Pass Rate:** 100% of evaluated shaders pass all randomization safety checks.

| Sub-check | Pass / Total | Pass Rate |
|-----------|-------------:|----------:|
| No unsafe division | 43 / 43 | 100% |
| No unsafe `log(0)` | 43 / 43 | 100% |
| No unsafe `sqrt(negative)` | 43 / 43 | 100% |
| Alpha clamped ≥ 0.1 | 43 / 43 | 100% |
| Params valid at extremes | 43 / 43 | 100% |

**Full-Library Context:**

Out of the **715** shaders in the entire library:
- 6 shaders contain unsafe division patterns (0.8%)
- 0 shaders contain unsafe `log(0)`
- 0 shaders contain unsafe `sqrt(negative)`
- 1 shader contains an unbounded `while` loop (0.1%)

Phase A shaders are **cleaner than the library baseline**; none of the 43 exhibit any unsafe randomization patterns.

### 3.3 Compilation / Performance (20 points max)

**Overall Pass Rate:** 100% of Phase A shaders pass all compilation and performance checks.

| Sub-check | Pass / Total | Pass Rate |
|-----------|-------------:|----------:|
| `@workgroup_size(8, 8, 1)` exact | 43 / 43 | 100% |
| Bounded loops only | 43 / 43 | 100% |
| No redundant texture samples | 43 / 43 | 100% |
| Early exits present | 43 / 43 | 100% |
| No dead code | 43 / 43 | 100% |

**Critical Full-Library Finding:**

Only **43 out of 715 shaders (6.0%)** have the correct `@workgroup_size(8, 8, 1)`. The remaining 672 shaders (94.0%) use non-standard workgroup sizes. This is a **systemic issue** across the legacy library. The Phase A upgrade swarm successfully corrected workgroup sizes for all 43 shaders it touched, but the broader library remains non-compliant.

> ⚠️ **Recommendation:** Add a global workgroup-size normalization pass to the pre-build pipeline or schedule it as a fast-follow batch after Phase B.

### 3.4 Documentation / JSON (15 points max)

**Overall Pass Rate:** 97.7% for JSON existence and validity; 4.7% for standard header presence.

| Sub-check | Pass / Total | Pass Rate |
|-----------|-------------:|----------:|
| JSON definition exists | 42 / 43 | 97.7% |
| ID matches filename & URL | 42 / 43 | 97.7% |
| Category valid | 42 / 43 | 97.7% |
| Params fully specified | 42 / 43 | 97.7% |
| Features array accurate | 43 / 43 | 100% |

**Missing JSONs:**

| Shader ID | Issue | Impact |
|-----------|-------|--------|
| `gen_psychedelic_spiral` | No JSON definition at all | Cannot be loaded by the app; invisible in UI |

Additionally, `gen_psychedelic_spiral` has `category: "unknown"` in the scan because no JSON exists to declare its proper category.

---

## 4. Critical Issues

### 4.1 Grade C Shaders — Must Fix Before Phase B

#### `echo-trace` (Score: 73 | Grade: C)

| Dimension | Score | Max | Issue |
|-----------|------:|----:|-------|
| RGBA Compliance | 13 | 25 | Missing `all_bindings`, `uniforms_ok`, and `has_header` |
| Hybrid / Chunk | 0 | 15 | N/A (not a hybrid) |
| Randomization | 25 | 25 | ✅ Pass |
| Compile / Perf | 20 | 20 | ✅ Pass |
| Documentation | 15 | 15 | ✅ Pass |
| **Total** | **73** | **100** | **Grade C** |

**Specific Fixes Required:**
1. **Add missing bindings** — Ensure all 13 standard `@group(0) @binding(N)` declarations are present in correct order.
2. **Add missing `Uniforms` struct** — Must match the exact spec: `config`, `zoom_config`, `zoom_params`, `ripples: array<vec4<f32>, 50>`.
3. **Add standard header comment block** with shader name, category (`artistic`), features, creation date, and agent attribution.

#### `gen_psychedelic_spiral` (Score: 69 | Grade: C)

| Dimension | Score | Max | Issue |
|-----------|------:|----:|-------|
| RGBA Compliance | 22 | 25 | Missing `has_header` (-3 pts) |
| Hybrid / Chunk | 0 | 15 | N/A |
| Randomization | 25 | 25 | ✅ Pass |
| Compile / Perf | 20 | 20 | ✅ Pass |
| Documentation | 2 | 15 | Missing JSON definition entirely |
| **Total** | **69** | **100** | **Grade C** |

**Specific Fixes Required:**
1. **Create JSON definition** at `shader_definitions/generative/gen_psychedelic_spiral.json` (or correct category path) with:
   - `id`: `"gen_psychedelic_spiral"`
   - `name`: Display name
   - `url`: `"shaders/gen_psychedelic_spiral.wgsl"`
   - `category`: `"generative"` (or appropriate category)
   - `params`: Up to 4 slider parameters with `id`, `name`, `default`, `min`, `max`, `step`
   - `features`: Array with accurate flags (e.g., `["generative", "audio-reactive"]`)
2. **Add standard header comment block** to the WGSL file.

---

## 5. Remaining Phase A Work

### 5.1 Completion Status

| Metric | Value |
|--------|-------|
| Original Phase A Target | 84 shaders |
| Completed & Evaluated | 43 shaders |
| **Remaining** | **41 shaders** |
| Completion Rate | 51.2% |

### 5.2 Priority Targets — 9 Tiny Shaders (< 2 KB)

Per `swarm-tasks/phase-a/README.md`, the following 9 tiny shaders are the highest-priority remaining Phase A targets. They are the smallest in the library and represent the fastest ROI for RGBA upgrades.

| # | Shader ID | Size | Estimated Effort |
|---|-----------|------|-----------------|
| 1 | `texture` | 719 B | 15 min |
| 2 | `gen_orb` | 1,402 B | 20 min |
| 3 | `gen_grokcf_interference` | 1,535 B | 20 min |
| 4 | `gen_grid` | 1,594 B | 20 min |
| 5 | `gen_grokcf_voronoi` | 1,630 B | 20 min |
| 6 | `gen_grok41_plasma` | 1,648 B | 20 min |
| 7 | `galaxy` | 1,682 B | 20 min |
| 8 | `gen_trails` | 1,878 B | 25 min |
| 9 | `gen_grok41_mandelbrot` | 1,883 B | 25 min |

**Recommendation:** Schedule these 9 tiny shaders as a single fast-track batch. Each is small enough that an automated or semi-automated pass (using `scripts/apply-wgsl-fixes.py` patterns) could complete all 9 in under one swarm session.

### 5.3 Other Remaining Buckets (32 shaders)

The remaining 32 shaders span:
- **Small RGBA upgrades** from the image / interactive-mouse / visual-effects categories
- **Hybrid shaders** yet to be created (target: 10)
- **Generative / temporal shaders** yet to be created (target: 13)

See `swarm-tasks/phase-a/README.md` and `agents/EVALUATOR_SWARM.md` for the full target registry.

---

## 6. Phase B Readiness Gate

### 6.1 Gate Criteria Checklist

| Criterion | Threshold | Actual | Status |
|-----------|-----------|--------|--------|
| Grade A or B rate | ≥ 90% | 95.3% (41/43) | ✅ **PASS** |
| Grade D or F count | 0 without fix plan | 0 | ✅ **PASS** |
| Grade C count | ≤ 2 with fix plan | 2 | ⚠️ **CONDITIONAL** |
| Critical issues resolved | All | 0 of 2 resolved | ⚠️ **PENDING** |

### 6.2 Recommendation: CONDITIONAL PASS

**Phase B may proceed once the following two fixes are applied:**

1. **`echo-trace`** — Add missing standard bindings, `Uniforms` struct, and header comment block. Expected score after fix: 82–85 (Grade B).
2. **`gen_psychedelic_spiral`** — Create missing JSON definition and add header comment block. Expected score after fix: 82–85 (Grade B).

Both fixes are **low-effort, high-impact** documentation/infrastructure corrections. No algorithmic or visual rework is required. Estimated total fix time: < 30 minutes.

### 6.3 Post-Fix Projection

After resolving the 2 Grade C shaders:

| Metric | Projected Value |
|--------|----------------|
| Grade A or B rate | **100%** (43/43) |
| Mean Score | **~82.5** |
| Phase A completion | 43/84 (51.2%) — remaining 41 continue in parallel with Phase B |

---

## 7. Appendices

### A. Rubric Reference (from `agents/EVALUATOR_SWARM.md`)

```
Score = RGBA(25) + Hybrid(15) + Randomization(25) + CompilePerf(20) + DocsJSON(15)
      = 100 max

Grade Mapping:
  90–100 = A  (PASS — no action needed)
  75–89  = B  (PASS — minor suggestions noted)
  60–74  = C  (CONDITIONAL — must fix before Phase B)
  40–59  = D  (FAIL — significant rework required)
  0–39   = F  (FAIL — reject and rebuild)
```

### B. Data Sources

| File | Description |
|------|-------------|
| `swarm-outputs/phase-a-eval-scores.json` | Automated scores for 43 completed shaders |
| `swarm-outputs/shader_scan_results.json` | Full library scan (715 shaders) with binding, mouse, audio, depth-write, alpha, workgroup stats |
| `agents/EVALUATOR_SWARM.md` | Phase A audit rubric and Phase B curation criteria |
| `agents/weekly_upgrade_swarm.md` | Batch 1 completion details and code suggestions |
| `swarm-tasks/phase-a/README.md` | Phase A launch spec with target lists and agent assignments |

### C. Full-Library Health Snapshot

| Metric | Value | Notes |
|--------|-------|-------|
| Total WGSL shaders | 715 | — |
| Shaders with correct workgroup size | 43 (6.0%) | All 43 are Phase A completed |
| Shaders with unsafe division | 6 (0.8%) | Not in Phase A set |
| Shaders with unbounded `while` | 1 (0.1%) | Not in Phase A set |
| Shaders with JSON definition | 675 (94.4%) | 40 missing across library |
| Shaders with standard header | 184 (25.7%) | Includes templates and non-shader files |

---

*Report generated by Agent EV-1A*  
*Last updated: 2026-04-18*
