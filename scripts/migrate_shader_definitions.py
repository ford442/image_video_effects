#!/usr/bin/env python3
"""
Migrate shader_definitions/**/*.json to the schema in src/contracts/shader_definition.schema.json.

Idempotent: a migrated tree is a no-op, so open shader-batch PRs can re-run it after rebasing
onto the schema gate. Files that need no change are never rewritten, and rewritten files keep
their original formatting (indent, ensure_ascii, trailing newline) so diffs stay minimal.

What it does
  * folds `parameters` / `controls` / `advanced_params` / `uniforms` into `params` when `params`
    is missing or empty; when `params` already exists the redundant container moves to
    `x-meta.legacy.<key>` (nothing is deleted)
  * normalizes each params entry: desc→description; param/target/uniform/mappedTo/uniformMapping→
    mapping; value→default; label→name (only if name is absent); drops `type`; strips a `u.`
    prefix from mapping; derives a missing `id`; makes duplicate ids unique; clamps an
    out-of-range default into [min, max]
  * moves `updatedParams` to `x-meta.upgrade.params` (the app never reads it)
  * moves swarm/provenance keys (`_seeded_by`, `chunks_used`, `target_rating`, `performance_target`,
    `wolfram_params`, `created_by`, `created_date`, `author`, `complexity`, `filename`, `passes`)
    under `x-meta`
  * sets `category` to the folder name when it is present and disagrees
  * --rename-files renames each `<stem>.json` to `<id>.json`

Usage
  python3 scripts/migrate_shader_definitions.py             # dry run, prints a summary
  python3 scripts/migrate_shader_definitions.py --check     # exit 1 if any file would change
  python3 scripts/migrate_shader_definitions.py --write [--rename-files]
  python3 scripts/migrate_shader_definitions.py --write --files shader_definitions/x/y.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFINITIONS_DIR = PROJECT_ROOT / "shader_definitions"

META_KEY = "x-meta"
# Top-level keys that are authoring / swarm provenance, not shader behaviour.
META_RENAMES = {"_seeded_by": "seeded_by"}
META_KEYS = (
    "chunks_used", "target_rating", "performance_target", "wolfram_params",
    "created_by", "created_date", "author", "complexity", "filename", "passes",
)
ALT_PARAM_CONTAINERS = ("parameters", "controls", "advanced_params", "uniforms")
MAPPING_ALIASES = ("param", "target", "uniform", "mappedTo", "uniformMapping", "mapping")


def slug(text: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "_", str(text)).strip("_").lower()
    return s or "param"


def normalize_mapping(value):
    if isinstance(value, dict):  # {"struct": "zoom_params", "field": "x"}
        if value.get("struct") and value.get("field"):
            value = f"{value['struct']}.{value['field']}"
        else:
            return None
    if not isinstance(value, str):
        return None
    return re.sub(r"^u\.", "", value.strip())


def normalize_param(p: dict) -> dict:
    """Rewrite one params entry, keeping key order (a renamed key keeps its slot)."""
    out: dict = {}
    mapping = None
    for alias in MAPPING_ALIASES:
        if alias in p:
            mapping = normalize_mapping(p[alias])
            if mapping:
                break
    for key, value in p.items():
        if key in ("type",):
            continue
        if key == "desc":
            if "description" not in p:
                out["description"] = value
            continue
        if key == "value":
            if "default" not in p:
                out["default"] = value
            continue
        if key == "label":
            if "name" not in p:
                out["name"] = value
            continue
        if key in MAPPING_ALIASES:
            if mapping is not None:
                out["mapping"] = mapping
                mapping = None  # first alias slot wins, the rest are dropped
            continue
        out[key] = value
    return out


def entries_from_container(container) -> list[dict]:
    """Turn any legacy params container shape into a list of param dicts."""
    entries: list[dict] = []
    if isinstance(container, list):
        for item in container:
            if isinstance(item, dict):
                entries.append(dict(item))
    elif isinstance(container, dict):
        for key, value in container.items():
            if not isinstance(value, dict):
                continue
            if "." in key:  # {"zoom_params.x": {label, min, ...}}
                entry = dict(value)
                entry.setdefault("mapping", key)
                entries.append(entry)
            else:  # {"zoom_params": {"x": {name, ...}}}
                for sub, leaf in value.items():
                    if isinstance(leaf, dict):
                        entry = dict(leaf)
                        entry.setdefault("mapping", f"{key}.{sub}")
                        entries.append(entry)
    return entries


def finalize_params(entries: list[dict], notes: list[str]) -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for raw in entries:
        p = normalize_param(raw)
        pid = p.get("id")
        if not pid:
            pid = slug(p.get("name", "param"))
            new = {"id": pid}
            new.update(p)
            p = new
            notes.append(f"derived id '{pid}'")
        if pid in seen:
            n = 2
            while f"{pid}_{n}" in seen:
                n += 1
            notes.append(f"duplicate id '{pid}' -> '{pid}_{n}'")
            pid = f"{pid}_{n}"
            p["id"] = pid
        seen.add(pid)
        lo, hi, dv = p.get("min"), p.get("max"), p.get("default")
        if all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in (lo, hi, dv)):
            if dv < lo or dv > hi:
                clamped = min(max(dv, lo), hi)
                notes.append(f"clamped default of '{pid}' {dv} -> {clamped}")
                p["default"] = clamped
        out.append(p)
    return out


def migrate(data: dict, folder: str, notes: list[str]) -> dict:
    d = dict(data)
    meta = dict(d.get(META_KEY) or {})

    # --- params -----------------------------------------------------------------------------
    params = d.get("params")
    have_params = isinstance(params, list) and len(params) > 0
    folded = False
    for key in ALT_PARAM_CONTAINERS:
        if key not in d:
            continue
        container = d.pop(key)
        if not have_params:
            entries = entries_from_container(container)
            if entries:
                d["params"] = entries
                params = entries
                have_params = True
                folded = True
                notes.append(f"folded {key} into params ({len(entries)})")
                continue
        meta.setdefault("legacy", {})[key] = container
        notes.append(f"moved redundant {key} to x-meta.legacy")
    if isinstance(d.get("params"), list):
        before = d["params"]
        after = finalize_params([p for p in before if isinstance(p, dict)], notes)
        if after != before:
            d["params"] = after
    elif "params" in d:
        notes.append("params is not a list")

    # --- updatedParams -> x-meta.upgrade.params ----------------------------------------------
    if "updatedParams" in d:
        meta.setdefault("upgrade", {})["params"] = d.pop("updatedParams")
        notes.append("moved updatedParams to x-meta.upgrade.params")

    # --- provenance keys -> x-meta -----------------------------------------------------------
    for old, new in META_RENAMES.items():
        if old in d:
            meta[new] = d.pop(old)
            notes.append(f"moved {old} to x-meta.{new}")
    for key in META_KEYS:
        if key in d:
            if key == "passes":
                meta.setdefault("legacy", {})["passes"] = d.pop(key)
            else:
                meta[key] = d.pop(key)
            notes.append(f"moved {key} to x-meta")

    # --- category ----------------------------------------------------------------------------
    if "category" in d and d["category"] != folder:
        notes.append(f"category '{d['category']}' -> '{folder}'")
        d["category"] = folder

    if meta:
        d.pop(META_KEY, None)
        d[META_KEY] = meta  # always last
    return d


def detect_style(raw: str) -> tuple[int | str, bool, bool]:
    """Find (indent, ensure_ascii, trailing_newline) that reproduces the original bytes."""
    data = json.loads(raw)
    for indent in (2, 4, "\t"):
        for ensure_ascii in (False, True):
            for newline in (True, False):
                text = json.dumps(data, indent=indent, ensure_ascii=ensure_ascii) + ("\n" if newline else "")
                if text == raw:
                    return indent, ensure_ascii, newline
    return 2, False, raw.endswith("\n")


def definition_paths(explicit: list[str]) -> list[Path]:
    if explicit:
        return [Path(p).resolve() for p in explicit]
    return sorted(DEFINITIONS_DIR.glob("*/*.json"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="rewrite files that change")
    ap.add_argument("--check", action="store_true", help="exit 1 when any file would change")
    ap.add_argument("--rename-files", action="store_true", help="rename <stem>.json to <id>.json")
    ap.add_argument("--files", nargs="*", default=[], help="limit to these definition files")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    changed = 0
    renames: list[tuple[Path, Path]] = []
    counts: Counter[str] = Counter()
    for path in definition_paths(args.files):
        raw = path.read_text(encoding="utf-8")
        data = json.loads(raw)
        if not isinstance(data, dict):
            print(f"SKIP {path}: root is not an object", file=sys.stderr)
            continue
        notes: list[str] = []
        new = migrate(data, path.parent.name, notes)
        if new != data:
            changed += 1
            for n in notes:
                counts[re.sub(r"'[^']*'|[-\d.]+( -> [-\d.]+)?", "…", n)] += 1
            if args.verbose:
                print(f"{path.relative_to(PROJECT_ROOT)}: " + "; ".join(notes))
            if args.write:
                indent, ensure_ascii, newline = detect_style(raw)
                text = json.dumps(new, indent=indent, ensure_ascii=ensure_ascii) + ("\n" if newline else "")
                path.write_text(text, encoding="utf-8")
        target_id = new.get("id")
        if args.rename_files and target_id and path.stem != target_id:
            renames.append((path, path.with_name(f"{target_id}.json")))

    for src, dst in renames:
        if dst.exists():
            print(f"RENAME BLOCKED {src.name} -> {dst.name}: target exists", file=sys.stderr)
            continue
        print(f"rename {src.relative_to(PROJECT_ROOT)} -> {dst.name}")
        if args.write:
            src.rename(dst)

    for label, n in counts.most_common():
        print(f"  {n:5d}  {label}")
    print(f"{changed} definition(s) {'rewritten' if args.write else 'would change'}"
          f"{f', {len(renames)} rename(s)' if args.rename_files else ''}")
    if args.check and (changed or renames):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
