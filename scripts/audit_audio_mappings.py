#!/usr/bin/env python3
"""Audit generative shader JSONs for audio mapping metadata on attract pool members."""

from __future__ import annotations

import json
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEF_DIR = PROJECT_ROOT / "shader_definitions" / "generative"
REPORT_PATH = PROJECT_ROOT / "reports" / "audio_mapping_audit.json"

# Keep in sync with src/app/constants/attractShowcasePool.ts
ATTRACT_IDS = [
    "gen-showcase-nebula-core",
    "gen-showcase-kinetic-bloom",
    "gen-showcase-crystalline-pulse",
    "stellar-plasma",
    "quantum-foam-lattice",
    "audio_geometric_pulse",
    "crystalline-veins",
    "chromatic-ghost-tunnel",
    "cosmic-web",
    "gen_kimi_crystal",
    "gen_fluffy_raincloud",
    "gen_grokcf_interference",
    "bioluminescent-bloom",
    "cosmic-jellyfish",
    "liquid_magnetic_ferro",
    "lava-lamp-blobs",
    "kimi_quantum_field",
    "kimi_fractal_dreams",
    "supernova-core",
    "molten-gold",
    "gen-ethereal-cyber-chrono-nebula-phoenix",
    "chrono-voronoi-mycelium",
    "spec-quaternion-julia",
    "bio_lenia_continuous",
]

AUDIO_BANDS = ["bass", "mid", "treble", "overall"]
MAPPINGS = ["zoom_params.x", "zoom_params.y", "zoom_params.z", "zoom_params.w"]


def audit_shader(shader_id: str) -> dict:
    path = DEF_DIR / f"{shader_id}.json"
    if not path.exists():
        return {"id": shader_id, "ok": False, "error": "missing_json"}

    data = json.loads(path.read_text(encoding="utf-8"))
    params = data.get("params") or []
    issues = []

    if len(params) < 4:
        issues.append("fewer_than_4_params")

    for i in range(min(4, len(params))):
        p = params[i] if isinstance(params[i], dict) else {}
        if p.get("mapping") != MAPPINGS[i]:
            issues.append(f"param{i}_mapping")
        if p.get("audio") not in AUDIO_BANDS:
            issues.append(f"param{i}_audio")

    return {
        "id": shader_id,
        "ok": len(issues) == 0,
        "issues": issues,
        "param_count": len(params),
    }


def main() -> int:
    results = [audit_shader(sid) for sid in ATTRACT_IDS]
    ok_count = sum(1 for r in results if r["ok"])
    report = {
        "pool_size": len(ATTRACT_IDS),
        "verified": ok_count,
        "results": results,
    }
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(f"Audio mapping audit: {ok_count}/{len(ATTRACT_IDS)} verified")
    for r in results:
        if not r["ok"]:
            print(f"  FAIL {r['id']}: {r.get('issues', r.get('error'))}")

    return 0 if ok_count >= 20 else 1


if __name__ == "__main__":
    sys.exit(main())
