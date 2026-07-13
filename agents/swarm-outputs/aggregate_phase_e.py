#!/usr/bin/env python3
"""Aggregate Phase E evaluator scores into combined JSON and ranked markdown report."""
import json
from pathlib import Path
from collections import defaultdict

ROOT = Path("/root/image_video_effects/agents/swarm-outputs")

VISUAL_BATCH1 = ROOT / "phase-e-scores-visual-batch1.json"
VISUAL_BATCH2 = ROOT / "phase-e-scores-visual-batch2.json"
TECHNICAL_BATCH1 = ROOT / "phase-e-scores-technical-batch1.json"
TECHNICAL_BATCH2 = ROOT / "phase-e-scores-technical-batch2.json"
METADATA_BATCH1 = ROOT / "phase-e-scores-metadata-batch1.json"
METADATA_BATCH2 = ROOT / "phase-e-scores-metadata-batch2.json"

OUT_JSON = ROOT / "phase-e-scores-combined.json"
OUT_MD = ROOT / "phase-e-ranked-report.md"


def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def get_total(shader):
    """Extract total score from a shader dict, handling both 'total' and 'total_score'."""
    if "total_score" in shader:
        return shader["total_score"]
    return shader["total"]


def get_id(shader):
    """Extract stable shader id across different batch formats."""
    # Some batches (e.g. technical batch2) use numeric 'id' for sample index;
    # prefer 'shader_id' or 'name' in those cases.
    for key in ("shader_id", "name"):
        val = shader.get(key)
        if val and not isinstance(val, (int, float)):
            return val
    val = shader.get("id")
    if isinstance(val, (int, float)):
        # Fall back to name if numeric id has no name match expected
        return str(shader.get("name", val))
    return val


def collect_visual_notes(shader):
    notes = []
    if "rgba_compliance" in shader:
        notes.append(shader["rgba_compliance"].get("notes", ""))
    if "hybrid_chunk_quality" in shader:
        notes.append(shader["hybrid_chunk_quality"].get("notes", ""))
    if "notes" in shader:
        notes.append(shader["notes"])
    return " ".join(n.strip() for n in notes if n).strip()


def collect_technical_notes(shader):
    notes = []
    if "randomization_safety" in shader:
        notes.append(shader["randomization_safety"].get("notes", ""))
    if "compile_performance" in shader:
        notes.append(shader["compile_performance"].get("notes", ""))
    if "compilation_performance" in shader:
        notes.append(shader["compilation_performance"].get("notes", ""))
    if "notes" in shader:
        notes.append(shader["notes"])
    return " ".join(n.strip() for n in notes if n).strip()


def collect_metadata_notes(shader):
    notes = []
    for key in ["json_exists", "id_url_match", "category_valid", "params_complete", "features_accurate"]:
        if key in shader:
            notes.append(shader[key].get("notes", ""))
    if "notes" in shader:
        notes.append(shader["notes"])
    return " ".join(n.strip() for n in notes if n).strip()


def grade(total):
    if total >= 90:
        return "A"
    if total >= 75:
        return "B"
    if total >= 60:
        return "C"
    if total >= 40:
        return "D"
    return "F"


def main():
    data = {
        "visual": load(VISUAL_BATCH1)["shaders"] + load(VISUAL_BATCH2)["shaders"],
        "technical": load(TECHNICAL_BATCH1)["shaders"] + load(TECHNICAL_BATCH2)["shaders"],
        "metadata": load(METADATA_BATCH1)["shaders"] + load(METADATA_BATCH2)["scores"],
    }

    by_id = defaultdict(lambda: {"visual": 0, "technical": 0, "metadata": 0,
                                 "visual_notes": "", "technical_notes": "", "metadata_notes": ""})

    for dim, shaders in data.items():
        for s in shaders:
            sid = get_id(s)
            by_id[sid][dim] = get_total(s)
            if dim == "visual":
                by_id[sid]["visual_notes"] = collect_visual_notes(s)
            elif dim == "technical":
                by_id[sid]["technical_notes"] = collect_technical_notes(s)
            elif dim == "metadata":
                by_id[sid]["metadata_notes"] = collect_metadata_notes(s)

    rows = []
    for sid, scores in by_id.items():
        total = scores["visual"] + scores["technical"] + scores["metadata"]
        rows.append({
            "id": sid,
            "visual": scores["visual"],
            "technical": scores["technical"],
            "metadata": scores["metadata"],
            "total": total,
            "grade": grade(total),
            "visual_notes": scores["visual_notes"],
            "technical_notes": scores["technical_notes"],
            "metadata_notes": scores["metadata_notes"],
        })

    rows.sort(key=lambda x: x["total"], reverse=True)

    grade_counts = {"A": 0, "B": 0, "C": 0, "D": 0, "F": 0}
    totals = [r["total"] for r in rows]
    for r in rows:
        grade_counts[r["grade"]] += 1

    mean = sum(totals) / len(totals)
    sorted_totals = sorted(totals)
    n = len(sorted_totals)
    median = sorted_totals[n // 2] if n % 2 else (sorted_totals[n // 2 - 1] + sorted_totals[n // 2]) / 2

    out = {
        "sample_size": len(rows),
        "shaders": [{"id": r["id"], "visual": r["visual"], "technical": r["technical"],
                     "metadata": r["metadata"], "total": r["total"], "grade": r["grade"]} for r in rows],
        "stats": {**grade_counts, "mean": round(mean, 2), "median": median},
    }

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
        f.write("\n")

    # Build markdown report
    top10 = rows[:10]
    bottom10 = rows[-10:][::-1]

    def brief_strength(r):
        return r["visual_notes"].split(".")[0] if r["visual_notes"] else "High visual quality"

    def brief_issue(r):
        issues = []
        if r["visual"] < 35:
            issues.append("visual/RGBA issues")
        if r["technical"] < 38:
            issues.append("technical/math or perf issues")
        if r["metadata"] < 12:
            issues.append("metadata/JSON incomplete")
        return ", ".join(issues) if issues else "minor deductions"

    md = f"""# Phase E Evaluator Swarm — Ranked Report

**Agent 4e — Aggregation & Ranking**

---

## Executive Summary

- **Sample size:** {len(rows)} shaders
- **Grade distribution:** A={grade_counts['A']}, B={grade_counts['B']}, C={grade_counts['C']}, D={grade_counts['D']}, F={grade_counts['F']}
- **Mean score:** {mean:.2f} / 100
- **Median score:** {median:.1f} / 100
- **Pass rate (≥75 / B or higher):** {grade_counts['A'] + grade_counts['B']} / {len(rows)} ({(grade_counts['A'] + grade_counts['B']) / len(rows) * 100:.1f}%)
- **Conditional/fail rate (<75):** {grade_counts['C'] + grade_counts['D'] + grade_counts['F']} / {len(rows)} ({(grade_counts['C'] + grade_counts['D'] + grade_counts['F']) / len(rows) * 100:.1f}%)

Overall, the sample is strong: the majority of shaders earn A or B grades, driven by high visual and technical scores. The primary drags on total scores are metadata/JSON completeness (missing `step` fields, empty `features` arrays, missing `category` fields) and a small number of visual-RGBA issues such as hardcoded alpha or missing `writeDepthTexture`.

---

## Top 10 Shaders

| Rank | Shader ID | Total | Visual | Technical | Metadata | Grade | Standout Strength |
|------|-----------|-------|--------|-----------|----------|-------|-------------------|
"""
    for i, r in enumerate(top10, 1):
        md += f"| {i} | `{r['id']}` | {r['total']} | {r['visual']} | {r['technical']} | {r['metadata']} | {r['grade']} | {brief_strength(r)} |\n"

    md += f"""
---

## Bottom 10 Shaders

| Rank | Shader ID | Total | Visual | Technical | Metadata | Grade | Top Issues |
|------|-----------|-------|--------|-----------|----------|-------|------------|
"""
    for i, r in enumerate(bottom10, 1):
        rank = len(rows) - 10 + i
        md += f"| {rank} | `{r['id']}` | {r['total']} | {r['visual']} | {r['technical']} | {r['metadata']} | {r['grade']} | {brief_issue(r)} |\n"

    # Common issues summary: derive from notes
    rgba_hardcoded = [r["id"] for r in rows if "hardcode" in r["visual_notes"].lower() or "hard-coded" in r["visual_notes"].lower()]
    missing_depth = [r["id"] for r in rows if "depth" in r["visual_notes"].lower() and ("missing" in r["visual_notes"].lower() or "omit" in r["visual_notes"].lower() or "no header" in r["visual_notes"].lower())]
    metadata_step = [r["id"] for r in rows if "step" in r["metadata_notes"].lower() and ("missing" in r["metadata_notes"].lower() or "lack" in r["metadata_notes"].lower())]
    metadata_features = [r["id"] for r in rows if "features" in r["metadata_notes"].lower() and ("empty" in r["metadata_notes"].lower() or "missing" in r["metadata_notes"].lower() or "overclaim" in r["metadata_notes"].lower())]
    metadata_category = [r["id"] for r in rows if "category" in r["metadata_notes"].lower() and ("missing" in r["metadata_notes"].lower() or "mismatch" in r["metadata_notes"].lower())]
    def has_unsafe_math(notes):
        low = notes.lower()
        return any(
            phrase in low
            for phrase in [
                "division by zero",
                "can be 0",
                "could receive zero",
                "undefined direction",
                "normalize(0)",
                "normalize(0",
                "risky",
                "critical:",
                "receives zero vector",
            ]
        )

    def has_dead_code(notes):
        low = notes.lower()
        has_unused = "unused" in low and "no unused" not in low
        has_dead = "dead code" in low and "no dead code" not in low
        return has_unused or has_dead

    unsafe_math = [r["id"] for r in rows if has_unsafe_math(r["technical_notes"])]
    dead_code = [r["id"] for r in rows if has_dead_code(r["technical_notes"])]

    md += f"""
---

## Common Issues Summary

### Visual Quality (Agent 1e)
- **Hardcoded alpha / non-generative opaque output:** {len(rgba_hardcoded)} shaders — {', '.join(f'`{s}`' for s in rgba_hardcoded[:8])}{'...' if len(rgba_hardcoded) > 8 else ''}
- **Missing or incomplete `writeDepthTexture`:** {len(missing_depth)} shaders — {', '.join(f'`{s}`' for s in missing_depth[:8])}{'...' if len(missing_depth) > 8 else ''}
- A few shaders use extra bindings beyond the canonical 13 (e.g., `chrono-luma-slit-scan` history texture), which is functionally valid but flagged.

### Technical Correctness (Agent 2e)
- **Unsafe math / potential divide-by-zero or undefined normalize:** {len(unsafe_math)} shaders — {', '.join(f'`{s}`' for s in unsafe_math[:8])}{'...' if len(unsafe_math) > 8 else ''}
- **Dead code / unused bindings or helper functions:** widely present ({len(dead_code)} shaders) — {', '.join(f'`{s}`' for s in dead_code[:8])}{'...' if len(dead_code) > 8 else ''}
- Several generative shaders write alpha below the 0.1 floor in empty regions; this is visually acceptable but penalized under the strict rubric.

### Metadata & Documentation (Agent 3e)
- **Missing `step` field in params:** {len(metadata_step)} shaders — {', '.join(f'`{s}`' for s in metadata_step[:8])}{'...' if len(metadata_step) > 8 else ''}
- **Empty or overclaimed `features` array:** {len(metadata_features)} shaders — {', '.join(f'`{s}`' for s in metadata_features[:8])}{'...' if len(metadata_features) > 8 else ''}
- **Missing `category` field or category mismatch:** {len(metadata_category)} shaders — {', '.join(f'`{s}`' for s in metadata_category[:8])}{'...' if len(metadata_category) > 8 else ''}
- Several batch-2 generative shaders use `index` instead of `id` in `updatedParams`, which breaks runtime parameter mapping.

---

## Recommended Next Actions

1. **Metadata hygiene pass (highest ROI):**
   - Add missing `step` values to all params.
   - Ensure every JSON has a `category` field matching its directory.
   - Replace `index` with `id` in `updatedParams` for generative shaders.
   - Populate empty `features` arrays with accurate flags derived from shader headers.
2. **Visual/RGBA fixes for low scorers:**
   - Replace hardcoded `alpha = 1.0` with calculated alpha for post-processing shaders (`crt-tv`, `flip-matrix`, `fractal-kaleidoscope`, `gen-inverse-mandelbrot`, `gen-quantum-fluorescent-aether-moth-swarm`, `neon-poly-grid`).
   - Add `writeDepthTexture` writes where missing (`honey-melt`, `gen-quantum-...`, `neon-poly-grid`).
   - Correct binding order and add shader-specific headers where absent.
3. **Technical hardening:**
   - Guard divisions by runtime parameters with epsilon (e.g., `gen-prismatic-bismuth-lattice` `crystalScale`).
   - Avoid `normalize(zero_vector)` by checking length before normalizing.
   - Remove unused bindings/helpers to reduce dead-code noise.
4. **Regression gate:**
   - Add an automated pre-submit check that validates JSON schema (id, url, category, params with step, features) and catches hardcoded alpha in non-generative shaders.

---

*Report generated by Agent 4e — Aggregation & Ranking.*
"""

    with open(OUT_MD, "w", encoding="utf-8") as f:
        f.write(md)

    print(f"Wrote {OUT_JSON}")
    print(f"Wrote {OUT_MD}")
    print(f"Shaders: {len(rows)}")
    print(f"Grade distribution: {grade_counts}")
    print(f"Mean: {mean:.2f}, Median: {median}")


if __name__ == "__main__":
    main()
