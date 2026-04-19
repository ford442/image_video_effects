# Evaluator Swarm Operating Manual

> **Role:** Unified Phase A Shader Upgrade Evaluator  
> **Scope:** Audit Phase A outputs, curate Phase B targets, maintain living registry  
> **Authority:** Final gatekeeper for shader quality before Phase B launch  

---

## 1. Evaluation Philosophy

- **Objective scoring:** Every shader receives a numeric score (0–100) based on a fixed rubric.
- **Minimal subjectivity:** Checklist items are binary pass/fail. Where judgment is required, document the reasoning.
- **Mouse over audio:** For Phase B curation, mouse-driven interactivity (`zoom_config.yz/w`) is prioritized over audio reactivity (`plasmaBuffer`).
- **Living documents:** All target lists are updated in-place as work progresses.

---

## 2. Phase A Audit Rubric

### 2.1 RGBA Compliance (25 points)

| # | Check | Points | How to Verify |
|---|-------|--------|---------------|
| 1 | `writeTexture` stores `vec4<f32>` with calculated alpha | 8 | Search for `textureStore(writeTexture` — must be `vec4<f32>(..., alpha)` not `vec4<f32>(..., 1.0)` unless generative and justified |
| 2 | `writeDepthTexture` is written to | 5 | Search for `textureStore(writeDepthTexture` — must exist |
| 3 | All 13 bindings declared in correct order | 5 | Match against standard header template |
| 4 | `Uniforms` struct matches spec exactly | 4 | `config: vec4<f32>`, `zoom_config: vec4<f32>`, `zoom_params: vec4<f32>`, `ripples: array<vec4<f32>, 50>` |
| 5 | Required header comment present | 3 | `// ═══════════════════════════════════════════════════════════════════` with shader name, category, features, date, agent |

**Alpha Calculation Patterns (valid):**
- `luminance-based`: `let alpha = mix(0.7, 1.0, luma)`
- `depth-aware`: `let alpha = mix(0.6, 1.0, depth)`
- `effect-intensity`: `let alpha = mix(0.5, 1.0, effectStrength)`
- `procedural/generative`: `let alpha = 1.0` (only for generative shaders where justified)
- `edge-fade`: `alpha *= smoothstep(0.0, 0.05, edgeDist)`

**Common Failures:**
- Hardcoded `alpha = 1.0` on non-generative shaders
- Missing `writeDepthTexture` store
- Swapped binding order or missing bindings
- `ripples` array size ≠ 50

### 2.2 Hybrid / Chunk Quality (15 points)

| # | Check | Points | How to Verify |
|---|-------|--------|---------------|
| 1 | Hybrid combines ≥2 distinct techniques | 5 | Code review: noise + SDF, kaleidoscope + chromatic, etc. |
| 2 | Chunk attribution comments present | 4 | `// ═══ CHUNK: <name> (from <source>.wgsl) ═══` |
| 3 | Chunk interfaces compatible | 3 | UV types match, output types match |
| 4 | No duplicate/near-duplicate ID | 3 | Cross-check against all existing JSON IDs |

### 2.3 Randomization Safety (25 points)

| # | Check | Points | How to Verify |
|---|-------|--------|---------------|
| 1 | No division by parameter without epsilon | 5 | `1.0 / (param + 0.001)` or equivalent |
| 2 | No `log(0)` or `sqrt(negative)` | 5 | `log(param + 0.001)`, `sqrt(max(val, 0.0))` |
| 3 | No `pow(0, negative)` | 5 | Base clamped > 0 when exponent can be negative |
| 4 | Alpha never < 0.1 (or justified generative 1.0) | 5 | `max(alpha, 0.1)` or equivalent |
| 5 | All params produce valid visual output at 0.0, 1.0, random | 5 | Static analysis + spot-check logic |

### 2.4 Compilation / Performance (20 points)

| # | Check | Points | How to Verify |
|---|-------|--------|---------------|
| 1 | `@compute @workgroup_size(8, 8, 1)` exact | 5 | Regex search |
| 2 | All loops bounded with fixed iteration counts | 5 | No `while` with dynamic exit only |
| 3 | No redundant texture samples in loops | 4 | Sample cached in variable before loop if reused |
| 4 | Early exits where applicable | 3 | `if (condition) { textureStore(...); return; }` |
| 5 | No dead/unused code | 3 | Variables declared but never read, functions never called |

### 2.5 Documentation / JSON (15 points)

| # | Check | Points | How to Verify |
|---|-------|--------|---------------|
| 1 | JSON definition exists at correct path | 4 | `shader_definitions/{category}/{id}.json` |
| 2 | ID matches filename, URL is correct | 3 | `url` field points to `shaders/{filename}.wgsl` |
| 3 | Category is valid (one of 15) | 2 | Against allowed category list |
| 4 | All params have id, name, default, min, max, step | 4 | Schema check |
| 5 | Features array includes accurate flags | 2 | `mouse-driven`, `depth-aware`, `audio-reactive`, etc. |

**Allowed Categories:**
`image`, `generative`, `interactive-mouse`, `distortion`, `simulation`, `artistic`, `visual-effects`, `hybrid`, `advanced-hybrid`, `retro-glitch`, `lighting-effects`, `geometric`, `liquid-effects`, `post-processing`

---

## 3. Scoring Formula

```
Score = RGBA(25) + Hybrid(15) + Randomization(25) + CompilePerf(20) + DocsJSON(15)
      = 100 max
```

**Grade Mapping:**
| Score | Grade | Action |
|-------|-------|--------|
| 90–100 | A | PASS — no action needed |
| 75–89 | B | PASS — minor suggestions noted |
| 60–74 | C | CONDITIONAL — must fix before Phase B |
| 40–59 | D | FAIL — significant rework required |
| 0–39 | F | FAIL — reject and rebuild |

---

## 4. Phase B Target Curation Criteria

### 4.1 Selection Dimensions

For each candidate shader, evaluate:

| Dimension | Weight | Measurement |
|-----------|--------|-------------|
| **Size** | 20% | 5–8 KB = optimal; >15 KB = huge refactor; <3 KB = Phase A scope |
| **Mouse Gap** | 25% | Does NOT currently read `zoom_config.yz` or `zoom_config.w` |
| **Visual Impact** | 20% | User-facing, popular, or flagship shader |
| **Category Diversity** | 15% | Under-represented categories get bonus |
| **Upgrade Potential** | 20% | Clear path to add mouse response without breaking existing logic |

### 4.2 Mouse-Response Upgrade Patterns

When curating or upgrading for mouse, prefer these patterns:

**Displacement / Distortion:**
```wgsl
let mousePos = u.zoom_config.yz;
let mouseStrength = u.zoom_params.x;
let displacement = (uv - mousePos) * mouseStrength * 0.1;
```

**Focal Point:**
```wgsl
let center = u.zoom_config.yz; // or mix(vec2(0.5), u.zoom_config.yz, u.zoom_params.x)
```

**Interactive Reveal:**
```wgsl
let mouseDown = u.zoom_config.w > 0.5;
let revealRadius = select(0.0, u.zoom_params.y, mouseDown);
```

**Spring / Physics Following:**
```wgsl
let targetPos = u.zoom_config.yz;
let currentPos = ...; // from storage or param
let velocity = (targetPos - currentPos) * springStrength;
```

### 4.3 Phase B Buckets

| Bucket | Count | Criteria | Example Targets |
|--------|-------|----------|-----------------|
| **Complex Upgrades** | 50 | 5–8 KB, mouse-gap, high impact | tensor-flow-sculpting, hyperbolic-dreamweaver, stellar-plasma, liquid-metal |
| **Huge Refactors** | 3 | >15 KB, split to multi-pass | quantum-foam, aurora-rift, aurora-rift-2 |
| **Advanced Hybrids** | 10 | Novel multi-technique, mouse-driven | hyper-tensor-fluid, neural-raymarcher, gravitational-lensing |
| **Mouse-Interactive** | 50+ | <5 KB, no mouse usage yet, easy win | distortion, reveal, generative patterns |

---

## 5. Living Registry Schema

### 5.1 Markdown Registry (`upgrade-target-registry.md`)

Track every candidate with these columns:

```markdown
| Shader ID | Category | Size | Phase | Bucket | Status | Score | Notes |
|-----------|----------|------|-------|--------|--------|-------|-------|
| texture | image | 719 B | A | RGBA | completed | 95 | Upgraded by Agent 1A |
| quantum-foam | simulation | 20.5 KB | B | huge | pending | — | Multi-pass refactor needed |
```

**Status values:** `pending | in-progress | completed | skipped | deferred`

### 5.2 JSON Registry (`upgrade-target-registry.json`)

Machine-readable version for scripts:

```json
{
  "version": "1.0",
  "last_updated": "2026-04-18",
  "phases": {
    "a": { "total": 84, "completed": 25, "in_progress": 0, "pending": 59 },
    "b": { "total": 113, "completed": 0, "in_progress": 0, "pending": 113 },
    "c": { "total": 60, "completed": 0, "in_progress": 0, "pending": 60 }
  },
  "shaders": [
    {
      "id": "quantum-foam",
      "category": "simulation",
      "size_bytes": 20542,
      "phase": "b",
      "bucket": "huge",
      "status": "pending",
      "priority": 1,
      "mouse_gap": true,
      "notes": "Multi-pass refactor into 3 passes"
    }
  ]
}
```

---

## 6. Weekly Delta Report Template

After each Phase B/C wave, produce:

```markdown
# Registry Delta — Week of YYYY-MM-DD

## Changes Since Last Update

### Completed
| Shader ID | Phase | Bucket | Completed By |
|-----------|-------|--------|--------------|

### Newly Discovered
| Shader ID | Category | Size | Why Added |
|-----------|----------|------|-----------|

### Reprioritized
| Shader ID | Old Priority | New Priority | Reason |
|-----------|--------------|--------------|--------|

## Stats
- Phase A: X/Y completed (Z%)
- Phase B: X/Y completed (Z%)
- Phase C: X/Y completed (Z%)
```

---

## 7. Automation Helpers

### 7.1 Quick Scan Commands

```bash
# List all WGSL files by size
ls -lS public/shaders/*.wgsl | awk '{print $5, $NF}'

# Find shaders without mouse usage
grep -L "zoom_config.yz\|zoom_config.w" public/shaders/*.wgsl

# Find shaders with audio reactivity
grep -l "plasmaBuffer" public/shaders/*.wgsl

# Find shaders missing depth write
grep -L "writeDepthTexture" public/shaders/*.wgsl

# Find shaders with hardcoded alpha
grep -n "vec4<f32>(.*, 1.0)" public/shaders/*.wgsl
```

### 7.2 JSON Validation

```bash
# Check for duplicate IDs across all definitions
node scripts/check_duplicates.js

# Regenerate shader lists and catch errors
node scripts/generate_shader_lists.js
```

---

## 8. Success Gates

### Phase A Audit Gate
- [ ] All 84 Phase A targets scored
- [ ] 0 shaders with Grade D or F without a fix plan
- [ ] `phase-a-eval-scores.json` generated

### Phase B Target Gate
- [ ] `phase-b-upgrade-targets.md` contains ≥50 complex + 3 huge + 10 hybrids + 50 mouse-interactive
- [ ] All targets ranked by priority (1 = highest)
- [ ] `phase-b-upgrade-targets.json` validated

### Phase B Launch Gate
- [ ] Phase A audit shows ≥90% Grade A or B
- [ ] All critical issues from Phase A resolved
- [ ] Living registry initialized and checked in

---

*Maintained by: Evaluator Swarm*  
*Last updated: 2026-04-18*
