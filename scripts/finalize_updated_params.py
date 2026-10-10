#!/usr/bin/env python3
"""Add x-meta.upgrade.params + updated:true to generative JSON from existing params.

(`x-meta.upgrade.params` was the top-level `updatedParams` key before the definition schema;
the app never read it.)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def extract_params(meta: dict) -> list[dict]:
    """Sliders in zoom_params slot order; definitions carry them in the canonical `params` key."""
    return [p for p in meta.get("params") or [] if isinstance(p, dict)]


def apply(def_path: Path) -> bool:
    meta = json.loads(def_path.read_text(encoding="utf-8"))
    params = extract_params(meta)
    if not params:
        print(f"SKIP {def_path.stem}: no params")
        return False
    meta.setdefault("x-meta", {}).setdefault("upgrade", {})["params"] = [
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
    print(f"OK {def_path.stem}: {len(meta['x-meta']['upgrade']['params'])} x-meta.upgrade.params")
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
