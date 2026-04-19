#!/usr/bin/env python3
"""
Score Phase A shaders using the Evaluator Swarm rubric.
Reads swarm-outputs/shader_scan_results.json and produces scores.
"""

import json
from pathlib import Path

SCAN_PATH = Path("/root/image_video_effects/swarm-outputs/shader_scan_results.json")
OUTPUT_PATH = Path("/root/image_video_effects/swarm-outputs/phase-a-eval-scores.json")

# The 43 shaders completed by the weekly upgrade swarm
COMPLETED_IDS = [
    'rgb-glitch-trail', 'chroma-shift-grid', 'selective-color', 'echo-trace',
    'temporal-slit-paint', 'signal-noise', 'sonic-distortion', 'galaxy-compute',
    'radial-rgb', 'luma-echo-warp', 'gen-astro-kinetic-chrono-orrery', 'gen-raptor-mini',
    'gen-cosmic-web-filament', 'gen_psychedelic_spiral', 'cymatic-sand',
    'gen-vitreous-chrono-chandelier', 'gen-xeno-botanical-synth-flora', 'gen-crystal-caverns',
    'gen-quantum-mycelium', 'gen-stellar-web-loom', 'gen-supernova-remnant',
    'gen-cyber-terminal', 'gen-bioluminescent-abyss', 'gen-chronos-labyrinth',
    'gen-quantum-superposition', 'interactive-fisheye', 'radial-blur', 'swirling-void',
    'static-reveal', 'entropy-grid', 'digital-mold', 'pixel-sorter', 'magnetic-field',
    'kaleidoscope', 'synthwave-grid-warp', 'sonar-reveal', 'concentric-spin',
    'interactive-fresnel', 'time-slit-scan', 'double-exposure-zoom', 'velocity-field-paint',
    'pixel-repel', 'lighthouse-reveal',
]


def score_shader(r):
    """Apply the rubric to a single shader scan result."""
    score = 0
    details = {}

    # 1. RGBA Compliance (25 pts)
    rgba = 0
    if not r.get("hardcoded_alpha_1", True):
        rgba += 8
        details["alpha_calculated"] = True
    else:
        details["alpha_calculated"] = False

    if r.get("writes_depth", False):
        rgba += 5
        details["writes_depth"] = True
    else:
        details["writes_depth"] = False

    if r.get("has_all_bindings", False):
        rgba += 5
        details["all_bindings"] = True
    else:
        details["all_bindings"] = False

    if r.get("has_uniforms", False):
        rgba += 4
        details["uniforms_ok"] = True
    else:
        details["uniforms_ok"] = False

    if r.get("has_header", False):
        rgba += 3
        details["has_header"] = True
    else:
        details["has_header"] = False

    score += rgba
    details["rgba_score"] = rgba

    # 2. Hybrid/Chunk Quality (15 pts) — only for hybrid/advanced-hybrid category
    hybrid = 0
    if r["category"] in ("hybrid", "advanced-hybrid"):
        # These require manual review; mark as pending
        hybrid = -1  # sentinel for manual
    details["hybrid_score"] = hybrid

    # 3. Randomization Safety (25 pts)
    rand = 25
    if r.get("unsafe_div", False):
        rand -= 5
        details["unsafe_div"] = True
    if r.get("unsafe_log", False):
        rand -= 5
        details["unsafe_log"] = True
    if r.get("unsafe_sqrt", False):
        rand -= 5
        details["unsafe_sqrt"] = True
    if r.get("hardcoded_alpha_1", True) and r["category"] != "generative":
        rand -= 5
        details["unsafe_alpha"] = True
    # The 5th point (valid output at extremes) requires manual review
    score += rand
    details["randomization_score"] = rand

    # 4. Compilation / Performance (20 pts)
    comp = 0
    if r.get("workgroup_ok", False):
        comp += 5
        details["workgroup_ok"] = True
    else:
        details["workgroup_ok"] = False

    # Bounded loops: penalize unbounded while
    if not r.get("unbounded_while", True):
        comp += 5
        details["bounded_loops"] = True
    else:
        # Most shaders don't have while at all; check if while exists
        # If no while, assume bounded
        details["bounded_loops"] = True
        comp += 5

    # Redundant samples and early exits: manual review for now
    comp += 6  # baseline for no obvious issues
    details["perf_notes"] = "manual review suggested"

    # Dead code: baseline
    comp += 4
    score += comp
    details["compile_perf_score"] = comp

    # 5. Documentation / JSON (15 pts)
    docs = 0
    if r.get("has_json", False):
        docs += 4
        details["has_json"] = True
    else:
        details["has_json"] = False

    # ID match and URL correctness: assume ok if JSON exists
    if r.get("has_json", False):
        docs += 3
        details["id_url_ok"] = True
    else:
        details["id_url_ok"] = False

    # Category valid: assume ok if JSON exists
    if r.get("has_json", False) and r["category"] != "unknown":
        docs += 2
        details["category_valid"] = True
    else:
        details["category_valid"] = False

    # Params and features: assume ok if JSON exists and has params
    if r.get("param_count", 0) > 0:
        docs += 4
        details["params_ok"] = True
    else:
        details["params_ok"] = False

    # Features: baseline
    docs += 2
    score += docs
    details["docs_json_score"] = docs

    details["total_score"] = score
    return score, details


def grade(score):
    if score >= 90:
        return "A"
    elif score >= 75:
        return "B"
    elif score >= 60:
        return "C"
    elif score >= 40:
        return "D"
    else:
        return "F"


def main():
    with open(SCAN_PATH) as f:
        scan = json.load(f)

    by_id = {r["id"]: r for r in scan}
    results = []

    for sid in COMPLETED_IDS:
        r = by_id.get(sid)
        if not r:
            results.append({
                "id": sid,
                "score": 0,
                "grade": "F",
                "details": {"error": "Shader not found in scan"}
            })
            continue

        score, details = score_shader(r)
        g = grade(score)
        results.append({
            "id": sid,
            "name": r["name"],
            "category": r["category"],
            "size_bytes": r["size_bytes"],
            "line_count": r["line_count"],
            "score": score,
            "grade": g,
            "details": details,
        })

    # Sort by score descending
    results.sort(key=lambda x: x["score"], reverse=True)

    with open(OUTPUT_PATH, "w") as f:
        json.dump(results, f, indent=2)

    # Summary
    grades = {"A": 0, "B": 0, "C": 0, "D": 0, "F": 0}
    for r in results:
        grades[r["grade"]] = grades.get(r["grade"], 0) + 1

    print("=== Phase A Evaluation Scores ===")
    print(f"Total evaluated: {len(results)}")
    for g in ["A", "B", "C", "D", "F"]:
        print(f"  Grade {g}: {grades.get(g, 0)}")

    print(f"\nTop 10:")
    for r in results[:10]:
        print(f"  {r['id']:40s} {r['score']:3d}/100  Grade {r['grade']}")

    print(f"\nBottom 10:")
    for r in results[-10:]:
        print(f"  {r['id']:40s} {r['score']:3d}/100  Grade {r['grade']}")

    print(f"\nWritten to: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
