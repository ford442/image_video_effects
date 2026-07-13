# Phase E Agent Swarm Registry — Evaluator Swarm

**Status:** ✅ COMPLETE  
**Started:** 2026-06-28  
**Goal:** Evaluate a representative sample of 60 shaders using the 100-point Evaluator Swarm rubric and produce a ranked catalog.

---

## Sample Selection

**Sample size:** 60 shaders (saved in `agents/swarm-outputs/phase-e-sample.json`)

**Selection method:**
- 10 largest shaders by file size
- 10 smallest non-template shaders by file size
- 40 randomly selected from category shader-lists (post-processing, distortion, retro-glitch, artistic, visual-effects, generative, hybrid, advanced-hybrid, interactive-mouse, image, simulation, geometric, liquid-effects, lighting-effects)

**Sample spans:**
- Size range: ~3 KB – ~20 KB
- Categories: image, generative, distortion, simulation, hybrid, post-processing, artistic, retro-glitch, visual-effects, liquid-effects
- Pass types: single-pass, multi-pass (aurora-rift, rd-on-video, quantum-foam)

---

## Scoring Rubric (100 points)

### Agent 1e — Visual Quality Evaluator (40 points)
1. **RGBA Compliance (25 points)**
   - `writeTexture` stores `vec4<f32>` with calculated alpha (8)
   - `writeDepthTexture` is written (5)
   - All 13 bindings declared in correct order (5)
   - `Uniforms` struct matches spec (4)
   - Required header comment present (3)
2. **Hybrid / Chunk Quality (15 points)**
   - Hybrid combines ≥2 distinct techniques (5)
   - Chunk attribution comments present (4)
   - Chunk interfaces compatible (3)
   - No duplicate/near-duplicate ID (3)

### Agent 2e — Technical Correctness Evaluator (45 points)
1. **Randomization Safety (25 points)**
   - No division by parameter without epsilon (5)
   - No `log(0)` or `sqrt(negative)` (5)
   - No `pow(0, negative)` (5)
   - Alpha never < 0.1 unless justified generative 1.0 (5)
   - All params produce valid output at 0.0, 1.0, random (5)
2. **Compilation / Performance (20 points)**
   - Valid `@compute @workgroup_size` (5)
   - All loops bounded with fixed iteration counts (5)
   - No redundant texture samples in loops (4)
   - Early exits where applicable (3)
   - No dead/unused code (3)

### Agent 3e — Metadata & Documentation Evaluator (15 points)
1. JSON definition exists at correct path (4)
2. ID matches filename, URL correct (3)
3. Category is valid (2)
4. All params have id, name, default, min, max, step (4)
5. Features array includes accurate flags (2)

### Grade Mapping
| Score | Grade | Action |
|-------|-------|--------|
| 90–100 | A | PASS — no action needed |
| 75–89 | B | PASS — minor suggestions noted |
| 60–74 | C | CONDITIONAL — must fix before next phase |
| 40–59 | D | FAIL — significant rework required |
| 0–39 | F | FAIL — reject and rebuild |

---

## Agent Assignments

### Agent 1e — Visual Quality Evaluator
**Target:** Score all 60 sample shaders on RGBA Compliance and Hybrid/Chunk Quality (40 points max).

Split into 2 batches:
- Batch 1 (shaders 1–30): output `agents/swarm-outputs/phase-e-scores-visual-batch1.json`
- Batch 2 (shaders 31–60): output `agents/swarm-outputs/phase-e-scores-visual-batch2.json`

**Status:** ✅ COMPLETE

### Agent 2e — Technical Correctness Evaluator
**Target:** Score all 60 sample shaders on Randomization Safety and Compilation/Performance (45 points max).

Split into 2 batches:
- Batch 1 (shaders 1–30): output `agents/swarm-outputs/phase-e-scores-technical-batch1.json`
- Batch 2 (shaders 31–60): output `agents/swarm-outputs/phase-e-scores-technical-batch2.json`

**Status:** ✅ COMPLETE

### Agent 3e — Metadata & Documentation Evaluator
**Target:** Score all 60 sample shaders on Documentation/JSON (15 points max).

Split into 2 batches:
- Batch 1 (shaders 1–30): output `agents/swarm-outputs/phase-e-scores-metadata-batch1.json`
- Batch 2 (shaders 31–60): output `agents/swarm-outputs/phase-e-scores-metadata-batch2.json`

**Status:** ✅ COMPLETE

### Agent 4e — Aggregation & Ranking
**Target:** Merge the three score files into a single ranked report.

Output: `agents/swarm-outputs/phase-e-ranked-report.md` + `agents/swarm-outputs/phase-e-scores-combined.json`

**Status:** ✅ COMPLETE

### Agent 5e — QA & Integration
**Target:** Validate all JSON outputs, ensure registry is updated to COMPLETE.

**Status:** ✅ COMPLETE — all JSON files validated, registry finalized.

---

## QA Results

- **Sample size:** 60
- **Grade distribution:** A=53, B=6, C=1, D=0, F=0
- **Mean score:** 93.38 / 100
- **Pass rate (B or higher):** 59 / 60 (98.3%)
- **One C shader:** `gen-quantum-fluorescent-aether-moth-swarm` (72)

---

## Success Criteria

- [x] All 60 sample shaders scored by all three evaluators.
- [x] Combined scores and grades produced.
- [x] Top 10 and bottom 10 shaders identified with reasons.
- [x] No Grade F shaders (D=0, F=0).
- [x] Registry marked ✅ COMPLETE.
