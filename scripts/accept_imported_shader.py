#!/usr/bin/env python3
"""
Write an imported shader to the local catalog and run wgsl_precommit_gate.

Usage:
    python3 scripts/accept_imported_shader.py --id my-shader --name "My Shader" \\
        --wgsl /tmp/shader.wgsl [--json /tmp/shader.json]

Or pipe WGSL on stdin:
    python3 scripts/accept_imported_shader.py --id my-shader --name "My Shader" --stdin
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
WGSL_DIR = PROJECT_ROOT / "public" / "shaders"
DEF_DIR = PROJECT_ROOT / "shader_definitions" / "generative"
GATE = PROJECT_ROOT / "scripts" / "wgsl_precommit_gate.py"
GENERATE_LISTS = PROJECT_ROOT / "scripts" / "generate_shader_lists.js"


def default_json(shader_id: str, name: str) -> dict:
    return {
        "id": shader_id,
        "name": name,
        "category": "generative",
        "url": f"shaders/{shader_id}.wgsl",
        "description": "Imported from Shadertoy",
        "tags": ["generative", "shadertoy", "imported"],
        "features": ["mouse-control", "audio-reactive"],
        "params": [
            {
                "id": "param1",
                "name": "Parameter 1",
                "default": 0.5,
                "min": 0,
                "max": 1,
                "step": 0.01,
                "mapping": "zoom_params.x",
                "audio": "bass",
            },
            {
                "id": "param2",
                "name": "Parameter 2",
                "default": 0.5,
                "min": 0,
                "max": 1,
                "step": 0.01,
                "mapping": "zoom_params.y",
                "audio": "mid",
            },
            {
                "id": "param3",
                "name": "Parameter 3",
                "default": 0.5,
                "min": 0,
                "max": 1,
                "step": 0.01,
                "mapping": "zoom_params.z",
                "audio": "treble",
            },
            {
                "id": "param4",
                "name": "Parameter 4",
                "default": 0.5,
                "min": 0,
                "max": 1,
                "step": 0.01,
                "mapping": "zoom_params.w",
                "audio": "overall",
            },
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Accept imported shader into catalog")
    parser.add_argument("--id", required=True, help="Shader id (slug)")
    parser.add_argument("--name", required=True, help="Display name")
    parser.add_argument("--wgsl", type=Path, help="Path to WGSL source file")
    parser.add_argument("--json", type=Path, help="Path to JSON definition (optional)")
    parser.add_argument("--stdin", action="store_true", help="Read WGSL from stdin")
    parser.add_argument("--skip-lists", action="store_true", help="Skip generate_shader_lists.js")
    args = parser.parse_args()

    shader_id = args.id.strip().lower().replace(" ", "-")
    if not shader_id.replace("-", "").replace("_", "").isalnum():
        print(f"Invalid shader id: {shader_id}", file=sys.stderr)
        return 1

    if args.stdin:
        wgsl_content = sys.stdin.read()
    elif args.wgsl:
        wgsl_content = args.wgsl.read_text(encoding="utf-8")
    else:
        print("Provide --wgsl or --stdin", file=sys.stderr)
        return 1

    if args.json:
        json_content = json.loads(args.json.read_text(encoding="utf-8"))
    else:
        json_content = default_json(shader_id, args.name)

    json_content["id"] = shader_id
    json_content["name"] = args.name
    json_content["url"] = f"shaders/{shader_id}.wgsl"

    WGSL_DIR.mkdir(parents=True, exist_ok=True)
    DEF_DIR.mkdir(parents=True, exist_ok=True)

    wgsl_path = WGSL_DIR / f"{shader_id}.wgsl"
    json_path = DEF_DIR / f"{shader_id}.json"

    wgsl_path.write_text(wgsl_content, encoding="utf-8")
    json_path.write_text(json.dumps(json_content, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {wgsl_path.relative_to(PROJECT_ROOT)}")
    print(f"Wrote {json_path.relative_to(PROJECT_ROOT)}")

    gate_result = subprocess.run(
        [sys.executable, str(GATE), "--files", str(wgsl_path)],
        cwd=PROJECT_ROOT,
    )
    if gate_result.returncode != 0:
        print("wgsl_precommit_gate FAILED — files written but not accepted", file=sys.stderr)
        return gate_result.returncode

    if not args.skip_lists and GENERATE_LISTS.exists():
        node = subprocess.run(["node", str(GENERATE_LISTS)], cwd=PROJECT_ROOT)
        if node.returncode != 0:
            return node.returncode

    print(f"Accepted {shader_id} — gate passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
