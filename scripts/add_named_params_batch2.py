#!/usr/bin/env python3
"""Add named params[] from updatedParams for generative shader batch 2."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEF_DIR = ROOT / "shader_definitions" / "generative"

BATCH_IDS = [
    "gen-bioluminescent-chrono-plasma-astro-owl",
    "gen-bioluminescent-cyber-aether-void-seahorse",
    "gen-bioluminescent-neural-lattice-weaver",
    "gen-bioluminescent-reaction-diffusion",
    "gen-biomechanical-hive",
    "gen-bioreactor-bloom",
    "gen-bismuth-crystal-citadel",
    "gen-bismuth-singularity-loom-engine",
    "gen-brutalist-monument",
    "gen-buddhabrot-aura",
    "gen-capabilities",
    "gen-celestial-aether-seraphim-wings",
    "gen-celestial-clockwork-plasma-loom",
    "gen-celestial-forge",
    "gen-celestial-glass-tornado",
    "gen-celestial-nanite-swarm-nebula",
    "gen-celestial-prism-orchid",
    "gen-celestial-quantum-glass-dragonfly",
    "gen-celestial-weave",
    "gen-celestial-yggdrasil-matrix",
    "gen-cellular-automata-tapestry",
    "gen-chaos-game-ifs",
    "gen-chromatic-acid-drip",
    "gen-chromatic-glass-lattice",
    "gen-chromatic-metamorphosis",
    "gen-chromatic-oracle-jelly",
    "gen-chromatic-singularity-loom",
    "gen-chromatic-zonohedron",
    "gen-chromodynamic-plasma-collider",
    "gen-chrono-kinetic-fractal-engine",
]

MAPPING = ["zoom_params.x", "zoom_params.y", "zoom_params.z", "zoom_params.w"]

# Replace weak scaffold titles before id synthesis.
NAME_OVERRIDES: dict[str, list[str]] = {
    "gen-bioluminescent-reaction-diffusion": [
        "Intensity",
        "Simulation Speed",
        "Spatial Scale",
        "Mouse Influence",
    ],
    "gen-celestial-yggdrasil-matrix": [
        "Branch Complexity",
        "Plasma Flow",
        "Gravity Warp",
        "Glow Intensity",
    ],
    "gen-chromatic-singularity-loom": [
        "Loom Intensity",
        "Weave Speed",
        "Detail Contrast",
        "Mouse Influence",
    ],
    "gen-capabilities": [
        "HUD Intensity",
        "Scan Speed",
        "Display Contrast",
        "Mouse Influence",
    ],
}

ID_OVERRIDES: dict[str, list[str]] = {
    "gen-capabilities": [
        "hud_intensity",
        "scan_speed",
        "display_contrast",
        "mouse_influence",
    ],
    "gen-chromatic-oracle-jelly": [
        "swarm_density",
        "drift_speed",
        "tentacle_curl",
        "oracle_chroma",
    ],
    "gen-chrono-kinetic-fractal-engine": [
        "complexity",
        "warp_strength",
        "iridescence",
        "kinetic_speed",
    ],
}

# When updatedParams index order != zoom_params axis order, supply full params.
FULL_PARAMS_OVERRIDES: dict[str, list[dict]] = {
    "gen-bioluminescent-cyber-aether-void-seahorse": [
        {
            "id": "bioluminescent_shift",
            "name": "Bioluminescent Shift",
            "default": 0.0,
            "min": -1.0,
            "max": 1.0,
            "step": 0.1,
            "mapping": "zoom_params.x",
        },
        {
            "id": "audio_reactivity",
            "name": "Audio Reactivity",
            "default": 1.0,
            "min": 0.0,
            "max": 3.0,
            "step": 0.1,
            "mapping": "zoom_params.y",
        },
        {
            "id": "void_intensity",
            "name": "Void Intensity",
            "default": 0.5,
            "min": 0.0,
            "max": 1.0,
            "step": 0.05,
            "mapping": "zoom_params.z",
        },
        {
            "id": "evolution_speed",
            "name": "Evolution Speed",
            "default": 1.0,
            "min": 0.1,
            "max": 5.0,
            "step": 0.1,
            "mapping": "zoom_params.w",
        },
    ],
    "gen-chrono-kinetic-fractal-engine": [
        {
            "id": "complexity",
            "name": "Complexity",
            "default": 1.0,
            "min": 0.1,
            "max": 5.0,
            "step": 0.1,
            "mapping": "zoom_params.x",
        },
        {
            "id": "warp_strength",
            "name": "Warp Strength",
            "default": 0.5,
            "min": 0.0,
            "max": 2.0,
            "step": 0.01,
            "mapping": "zoom_params.y",
        },
        {
            "id": "iridescence",
            "name": "Iridescence",
            "default": 1.0,
            "min": 0.0,
            "max": 3.0,
            "step": 0.1,
            "mapping": "zoom_params.z",
        },
        {
            "id": "kinetic_speed",
            "name": "Kinetic Speed",
            "default": 1.0,
            "min": 0.1,
            "max": 3.0,
            "step": 0.1,
            "mapping": "zoom_params.w",
        },
    ],
}


def def_path_for(shader_id: str) -> Path | None:
    candidates = [
        DEF_DIR / f"{shader_id}.json",
        DEF_DIR / f"{shader_id.removeprefix('gen-')}.json",
        DEF_DIR / f"{shader_id.replace('-', '_')}.json",
    ]
    for path in candidates:
        if path.exists():
            return path
    return None


def to_snake(name: str) -> str:
    cleaned = re.sub(r"[/]+", " ", name)
    cleaned = re.sub(r"[^a-zA-Z0-9]+", " ", cleaned)
    parts = [p for p in cleaned.strip().lower().split() if p]
    return "_".join(parts)


def build_params(shader_id: str, meta: dict) -> list[dict]:
    if shader_id in FULL_PARAMS_OVERRIDES:
        return FULL_PARAMS_OVERRIDES[shader_id]

    if shader_id in NAME_OVERRIDES and (
        not isinstance(meta.get("updatedParams"), list) or len(meta["updatedParams"]) < 4
    ):
        names = NAME_OVERRIDES[shader_id]
        ids = ID_OVERRIDES.get(shader_id, [to_snake(n) for n in names])
        return [
            {
                "id": ids[i],
                "name": names[i],
                "default": 0.5,
                "min": 0,
                "max": 1,
                "step": 0.01,
                "mapping": MAPPING[i],
            }
            for i in range(4)
        ]

    updated = meta.get("updatedParams")
    if not isinstance(updated, list) or len(updated) < 4:
        raise ValueError(f"{shader_id}: need 4 updatedParams entries")

    names = NAME_OVERRIDES.get(shader_id, [p["name"] for p in updated[:4]])
    ids = ID_OVERRIDES.get(shader_id, [to_snake(n) for n in names])

    params: list[dict] = []
    for i in range(4):
        src = updated[i]
        params.append(
            {
                "id": ids[i],
                "name": names[i],
                "default": src.get("default", 0.5),
                "min": src.get("min", 0),
                "max": src.get("max", 1),
                "step": src.get("step", 0.01),
                "mapping": MAPPING[i],
            }
        )
    return params


def sync_updated_params(meta: dict, params: list[dict]) -> None:
    meta["updatedParams"] = [
        {
            "index": i,
            "name": p["name"],
            "default": p["default"],
            "min": p["min"],
            "max": p["max"],
            "step": p["step"],
        }
        for i, p in enumerate(params[:4])
    ]


def main() -> int:
    sync_titles = set(NAME_OVERRIDES) | set(FULL_PARAMS_OVERRIDES)
    for shader_id in BATCH_IDS:
        path = def_path_for(shader_id)
        if path is None:
            print(f"MISSING {shader_id}")
            return 1

        meta = json.loads(path.read_text(encoding="utf-8"))
        params = build_params(shader_id, meta)
        meta["params"] = params
        if shader_id in sync_titles:
            sync_updated_params(meta, params)
        path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
        print(f"OK {shader_id} ({path.name})")

    print(f"Done: {len(BATCH_IDS)} shaders")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
