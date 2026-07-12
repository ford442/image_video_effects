#!/usr/bin/env python3
"""
Create shader_definitions/*.json for WGSL files that lack a catalog entry.

Reads WGSL headers for Category / Features when present; otherwise infers
category from id prefix. Safe to re-run (skips existing JSON for the same id).

Usage:
  python3 scripts/seed_orphan_shader_defs.py          # dry-run summary
  python3 scripts/seed_orphan_shader_defs.py --write  # create missing JSON files
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFINITIONS_DIR = PROJECT_ROOT / "shader_definitions"
SHADERS_DIR = PROJECT_ROOT / "public" / "shaders"
PUBLIC_DIR = PROJECT_ROOT / "public"
MULTIPASS_REGISTRY = PROJECT_ROOT / "src" / "renderer" / "multipassRegistry.ts"

DEFAULT_PARAMS = [
    {
        "id": "param1",
        "name": "Param 1",
        "default": 0.5,
        "min": 0,
        "max": 1,
        "step": 0.01,
        "mapping": "zoom_params.x",
    },
    {
        "id": "param2",
        "name": "Param 2",
        "default": 0.5,
        "min": 0,
        "max": 1,
        "step": 0.01,
        "mapping": "zoom_params.y",
    },
    {
        "id": "param3",
        "name": "Param 3",
        "default": 0.5,
        "min": 0,
        "max": 1,
        "step": 0.01,
        "mapping": "zoom_params.z",
    },
    {
        "id": "param4",
        "name": "Param 4",
        "default": 0.5,
        "min": 0,
        "max": 1,
        "step": 0.01,
        "mapping": "zoom_params.w",
    },
]

PREFIX_CATEGORY = {
    "gen-": "generative",
    "sim-": "simulation",
    "interactive-": "interactive-mouse",
    "pp-": "post-processing",
    "retro-": "retro-glitch",
    "liquid-": "liquid-effects",
    "cyber-": "retro-glitch",
}


def title_from_id(shader_id: str) -> str:
    return " ".join(word.capitalize() for word in shader_id.split("-"))


def parse_header_field(text: str, field: str) -> str | None:
    m = re.search(rf"^\s*//\s*{re.escape(field)}:\s*(.+)$", text, re.MULTILINE)
    return m.group(1).strip() if m else None


def parse_features(text: str) -> list[str]:
    raw = parse_header_field(text, "Features")
    if not raw:
        return []
    return [t.strip() for t in raw.split(",") if t.strip()]


def infer_category(shader_id: str, header_text: str) -> str:
    cat = parse_header_field(header_text, "Category")
    if cat:
        cat = cat.split("|")[0].strip().lower().replace(" ", "-")
        if (DEFINITIONS_DIR / cat).is_dir():
            return cat
    for prefix, category in PREFIX_CATEGORY.items():
        if shader_id.startswith(prefix):
            return category
    return "advanced-hybrid"


def load_referenced_wgsl_names() -> set[str]:
    names: set[str] = set()
    for json_path in DEFINITIONS_DIR.rglob("*.json"):
        try:
            data = json.loads(json_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        url = data.get("url") or ""
        if url:
            names.add(Path(str(url)).name)
        multipass = data.get("multipass") or {}
        for entry in multipass.get("passes") or []:
            fn = entry.get("file")
            if fn:
                names.add(fn)
    if MULTIPASS_REGISTRY.exists():
        reg = MULTIPASS_REGISTRY.read_text(encoding="utf-8")
        names |= set(re.findall(r'"([^"]+)"', reg))
    return names


def load_defined_ids_and_urls() -> tuple[set[str], set[str]]:
    ids: set[str] = set()
    wgsl_stems: set[str] = set()
    for json_path in DEFINITIONS_DIR.rglob("*.json"):
        try:
            data = json.loads(json_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        sid = str(data.get("id") or json_path.stem)
        ids.add(sid)
        url = data.get("url") or ""
        if url:
            wgsl_stems.add(Path(str(url)).stem)
        wgsl_stems.add(json_path.stem)
        wgsl_stems.add(sid)
    return ids, wgsl_stems


def find_orphan_stems() -> list[str]:
    _, def_stems = load_defined_ids_and_urls()
    referenced = load_referenced_wgsl_names()
    orphans: list[str] = []
    for path in sorted(SHADERS_DIR.glob("*.wgsl")):
        stem = path.stem
        if stem.startswith("_"):
            continue
        if stem.endswith("-sg") and stem[:-3] in def_stems:
            continue
        if stem in def_stems:
            continue
        if f"{stem}.wgsl" in referenced:
            continue
        orphans.append(stem)
    return orphans


def build_definition(shader_id: str, wgsl_path: Path) -> dict:
    header = wgsl_path.read_text(encoding="utf-8")[:1200]
    category = infer_category(shader_id, header)
    features = parse_features(header)
    desc_line = parse_header_field(header, shader_id) or ""
    if not desc_line:
        # grab first prose comment block after header banner
        m = re.search(r"//\s*═+\n(//\s*.+\n)+", header)
        desc_line = title_from_id(shader_id)
    return {
        "id": shader_id,
        "name": title_from_id(shader_id),
        "url": f"shaders/{shader_id}.wgsl",
        "description": desc_line if len(desc_line) > 20 else f"Catalog entry for {title_from_id(shader_id)}.",
        "tags": features[:6] if features else [category.replace("-", " ")],
        "features": features if features else ["mouse-driven"],
        "params": DEFAULT_PARAMS,
        "_seeded_by": "scripts/seed_orphan_shader_defs.py",
        "_category_folder": category,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed shader_definitions for orphan WGSL files.")
    parser.add_argument("--write", action="store_true", help="Write JSON files (default: dry-run)")
    args = parser.parse_args()

    existing_ids, _ = load_defined_ids_and_urls()
    orphans = find_orphan_stems()
    to_create: list[tuple[Path, dict]] = []

    for stem in orphans:
        if stem in existing_ids:
            continue
        wgsl_path = SHADERS_DIR / f"{stem}.wgsl"
        defn = build_definition(stem, wgsl_path)
        category = defn.pop("_category_folder")
        out_path = DEFINITIONS_DIR / category / f"{stem}.json"
        if out_path.exists():
            continue
        to_create.append((out_path, defn))

    print(f"Orphan WGSL stems (excl. _ prefix, -sg, multipass refs): {len(orphans)}")
    print(f"JSON files to create: {len(to_create)}")

    if not to_create:
        return 0

    if not args.write:
        for path, defn in to_create[:10]:
            print(f"  would write {path.relative_to(PROJECT_ROOT)} ({defn['id']})")
        if len(to_create) > 10:
            print(f"  ... and {len(to_create) - 10} more")
        print("Re-run with --write to create files.")
        return 0

    for path, defn in to_create:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(defn, indent=2) + "\n", encoding="utf-8")
        print(f"Created {path.relative_to(PROJECT_ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
