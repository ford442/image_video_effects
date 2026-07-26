#!/usr/bin/env python3
"""Add updatedParams + updated:true to generative JSON from existing params/controls."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "temp"))
from make_briefs_common import extract_params  # noqa: E402


def apply(def_path: Path) -> bool:
    meta = json.loads(def_path.read_text(encoding="utf-8"))
    params = extract_params(meta)
    if not params:
        print(f"SKIP {def_path.stem}: no params")
        return False
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
    meta["updated"] = True
    def_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print(f"OK {def_path.stem}: {len(meta['updatedParams'])} updatedParams")
    return True


if __name__ == "__main__":
    ids = sys.argv[1:] or []
    if not ids:
        print("usage: finalize_updated_params.py id1 id2 ...")
        sys.exit(1)
    for sid in ids:
        p = ROOT / "shader_definitions" / "generative" / f"{sid}.json"
        if not p.exists():
            print(f"MISSING {p}")
            continue
        apply(p)
