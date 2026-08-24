#!/usr/bin/env python3
"""Add named params[] from updatedParams for generative shader batch 3."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEF_DIR = ROOT / "shader_definitions" / "generative"

BATCH_IDS = [
    "gen-chrono-kitsune-prism-weaver",
    "gen-chrono-mycelial-tapestry",
    "gen-chrono-voronoi-mycelium",
    "gen-chronodynamic-aether-weaver-automata",
    "gen-chronos-biomechanical-void-leviathan",
    "gen-chronos-labyrinth",
    "gen-chronos-monolith-resonator",
    "gen-conway-game-of-life",
    "gen-coral-reef-colony",
    "gen-cosmic-clockwork-dyson-sphere",
    "gen-cosmic-slime-mold",
    "gen-cosmic-velvet-hypnosis",
    "gen-cosmic-web-filament",
    "gen-cryogenic-frost-plasma-matrix",
    "gen-crystal-caverns",
    "gen-crystal-lattice-growth",
    "gen-crystalline-chrono-dyson",
    "gen-crystalline-mandala-bloom",
    "gen-crystalline-nebula-weaver-void-spider",
    "gen-cyber-organic-liquid-neon-pulsar",
    "gen-cyber-terminal",
    "gen-cybernetic-aether-moth-chrysalis",
    "gen-cybernetic-crystalline-neuro-lattice",
    "gen-cybernetic-ferro-coral",
    "gen-cybernetic-liquid-chrome-engine",
    "gen-cybernetic-mycelium-neural-web",
    "gen-cyclic-automaton",
    "gen-cycloid-bloom",
    "gen-cymatic-plasma-mandalas",
    "gen-cymatic-quantum-silk-loom",
]

MAPPING = ["zoom_params.x", "zoom_params.y", "zoom_params.z", "zoom_params.w"]

NAME_OVERRIDES: dict[str, list[str]] = {
    "gen-chronodynamic-aether-weaver-automata": [
        "Thread Count",
        "Loom Rotation Speed",
        "Aether Bloom",
        "Temporal Decay",
    ],
    "gen-cosmic-clockwork-dyson-sphere": [
        "Mechanical Complexity",
        "Clock Speed",
        "Plasma Intensity",
        "Gear Ratio",
    ],
    "gen-cybernetic-aether-moth-chrysalis": [
        "Chrysalis Complexity",
        "Rotation Speed",
        "Shell Thickness",
        "Color Shift",
    ],
}

ID_OVERRIDES: dict[str, list[str]] = {
    "gen-cosmic-velvet-hypnosis": [
        "spiral_arms",
        "spin_rate",
        "velvet_softness",
        "saturation",
    ],
}

FULL_PARAMS_OVERRIDES: dict[str, list[dict]] = {
    "gen-chrono-kitsune-prism-weaver": [
        {
            "id": "prism_hue_shift",
            "name": "Prism Hue Shift",
            "default": 1.0,
            "min": 0.0,
            "max": 5.0,
            "step": 0.1,
            "mapping": "zoom_params.x",
        },
        {
            "id": "tail_count",
            "name": "Tail Count",
            "default": 0.8,
            "min": 0.1,
            "max": 1.0,
            "step": 0.05,
            "mapping": "zoom_params.y",
        },
        {
            "id": "weave_tightness",
            "name": "Weave Tightness",
            "default": 0.5,
            "min": 0.0,
            "max": 2.0,
            "step": 0.1,
            "mapping": "zoom_params.z",
        },
        {
            "id": "chrono_echo",
            "name": "Chrono Echo",
            "default": 0.95,
            "min": 0.0,
            "max": 1.0,
            "step": 0.01,
            "mapping": "zoom_params.w",
        },
    ],
    "gen-chronos-biomechanical-void-leviathan": [
        {
            "id": "time_offset",
            "name": "Time Offset",
            "default": 0.0,
            "min": -5.0,
            "max": 5.0,
            "step": 0.1,
            "mapping": "zoom_params.x",
        },
        {
            "id": "audio_reactivity",
            "name": "Audio Reactivity Multiplier",
            "default": 1.0,
            "min": 0.0,
            "max": 2.0,
            "step": 0.05,
            "mapping": "zoom_params.y",
        },
        {
            "id": "aurora_brightness",
            "name": "Brightness / Aurora Intensity",
            "default": 1.0,
            "min": 0.5,
            "max": 3.0,
            "step": 0.1,
            "mapping": "zoom_params.z",
        },
        {
            "id": "evolution_speed",
            "name": "Evolution Speed Multiplier",
            "default": 1.0,
            "min": 0.1,
            "max": 5.0,
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

    updated = meta.get("updatedParams")
    if not isinstance(updated, list) or len(updated) < 4:
        raise ValueError(f"{shader_id}: need 4 updatedParams entries")
    if not isinstance(updated[0], dict):
        raise ValueError(f"{shader_id}: updatedParams must be objects")

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
