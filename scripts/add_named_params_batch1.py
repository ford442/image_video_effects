#!/usr/bin/env python3
"""Add named params[] from updatedParams for generative shader batch 1."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEF_DIR = ROOT / "shader_definitions" / "generative"

BATCH_IDS = [
    "gen-3d-sierpinski-chaos",
    "gen-4d-projection-dream-weavers",
    "gen-abyssal-chrono-coral",
    "gen-abyssal-leviathan-scales",
    "gen-abyssal-plasma-void-medusa",
    "gen-abyssal-quantum-leviathan-skeleton",
    "gen-abyssal-silicate-geode-weaver",
    "gen-acid-lissajous",
    "gen-alien-flora",
    "gen-alien-flora-ecosystem",
    "gen-alpha-aurora",
    "gen-aperiodic-monotile",
    "gen-apollonian-gasket",
    "gen-art-deco-sky",
    "gen-astral-silk-chrono-weaver-arachnid",
    "gen-astro-kinetic-chrono-orrery",
    "gen-astro-mechanical-quantum-furnace-engine",
    "gen-audio-spirograph",
    "gen-audiovisual-mandelbulb-raymarcher",
    "gen-aurora-borealis-synthesis",
    "gen-aurora-silk",
    "gen-auroral-ferrofluid-monolith",
    "gen-barnsley-fern",
    "gen-belousov-zhabotinsky",
    "gen-bifurcation-diagram",
    "gen-bio-luminescent-jelly",
    "gen-bioelectric-pulse",
    "gen-bioluminescent-abyss",
    "gen-bioluminescent-aether-jellyfish-swarm",
    "gen-bioluminescent-aether-pulsar",
]

MAPPING = ["zoom_params.x", "zoom_params.y", "zoom_params.z", "zoom_params.w"]

# Override weak updatedParams titles before id synthesis.
NAME_OVERRIDES: dict[str, list[str]] = {
    "gen-alien-flora-ecosystem": [
        "Vegetation Density",
        "Sway Speed",
        "Glow Intensity",
        "Color Shift",
    ],
}

ID_OVERRIDES: dict[str, list[str]] = {
    "gen-acid-lissajous": [
        "animation_speed",
        "harmonic_complexity",
        "glow_mouse_gravity",
        "feedback_decay",
    ],
}


def def_path_for(shader_id: str) -> Path | None:
    direct = DEF_DIR / f"{shader_id}.json"
    if direct.exists():
        return direct
    stripped = DEF_DIR / f"{shader_id.removeprefix('gen-')}.json"
    if stripped.exists():
        return stripped
    return None


def to_snake(name: str) -> str:
    cleaned = re.sub(r"[/]+", " ", name)
    cleaned = re.sub(r"[^a-zA-Z0-9]+", " ", cleaned)
    parts = [p for p in cleaned.strip().lower().split() if p]
    return "_".join(parts)


def build_params(shader_id: str, meta: dict) -> list[dict]:
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
    changed = 0
    for shader_id in BATCH_IDS:
        path = def_path_for(shader_id)
        if path is None:
            print(f"MISSING {shader_id}")
            return 1

        meta = json.loads(path.read_text(encoding="utf-8"))
        params = build_params(shader_id, meta)
        meta["params"] = params
        if shader_id in NAME_OVERRIDES:
            sync_updated_params(meta, params)
        path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
        print(f"OK {shader_id} ({path.name})")
        changed += 1

    print(f"Done: {changed} shaders")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
