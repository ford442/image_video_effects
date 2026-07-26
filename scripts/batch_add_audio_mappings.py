#!/usr/bin/env python3
"""Add default audio + zoom_params mapping metadata to attract pool shader JSONs."""

from __future__ import annotations

import json
from pathlib import Path

DEF_DIR = Path(__file__).resolve().parent.parent / "shader_definitions" / "generative"

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

AUDIO = ["bass", "mid", "treble", "overall"]
MAPPING = ["zoom_params.x", "zoom_params.y", "zoom_params.z", "zoom_params.w"]
NAMES = ["Parameter 1", "Parameter 2", "Parameter 3", "Parameter 4"]


def ensure_params(data: dict) -> None:
    params = data.get("params")
    if not isinstance(params, list):
        params = []
    while len(params) < 4:
        params.append({})
    for i in range(4):
        p = params[i] if isinstance(params[i], dict) else {}
        p.setdefault("id", f"param{i + 1}")
        p.setdefault("name", NAMES[i])
        p.setdefault("default", 0.5)
        p.setdefault("min", 0)
        p.setdefault("max", 1)
        p.setdefault("step", 0.01)
        p["mapping"] = MAPPING[i]
        p["audio"] = AUDIO[i]
        params[i] = p
    data["params"] = params


def main() -> None:
    updated = 0
    for sid in ATTRACT_IDS:
        path = DEF_DIR / f"{sid}.json"
        if not path.exists():
            print(f"skip missing {sid}")
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        ensure_params(data)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        updated += 1
        print(f"updated {sid}")
    print(f"Done: {updated} files")


if __name__ == "__main__":
    main()
