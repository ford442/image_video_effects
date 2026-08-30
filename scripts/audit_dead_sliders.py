#!/usr/bin/env python3
"""
Dead-slider auditor — swarm guardrail against UI controls no WGSL ever reads.

For every shader definition JSON (shader_definitions/**), extract the slider
params and their uniform mapping (params[].mapping, or params array order ->
zoom_params.x/y/z/w; controls[].uniform / uniformMapping.field). Then check
the shader's WGSL actually READS that field (u.zoom_params.<field>, an alias
`let a = u.zoom_params; a.<field>`, or constant index u.zoom_params[i]).

A param whose mapped field is never read is a DEAD SLIDER: the UI shows a
control that does nothing (e.g. generative-turing-veins had 4, fixed in
Batch 12).

FAILS (exit 1) on dead sliders not recorded in the triage baseline
(reports/dead_sliders_audit_baseline.json) — legacy offenders cataloged
during the initial full-tree triage.

Usage:
  python3 scripts/audit_dead_sliders.py                    # full-tree
  python3 scripts/audit_dead_sliders.py --category generative
  python3 scripts/audit_dead_sliders.py --files id1 id2    # by shader id
  python3 scripts/audit_dead_sliders.py --write-baseline   # re-triage (careful)
  python3 scripts/audit_dead_sliders.py --json

Outputs: reports/dead_sliders_audit.json + .md
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFINITIONS_DIR = PROJECT_ROOT / "shader_definitions"
SHADERS_DIR = PROJECT_ROOT / "public" / "shaders"
REPORT_JSON = PROJECT_ROOT / "reports" / "dead_sliders_audit.json"
REPORT_MD = PROJECT_ROOT / "reports" / "dead_sliders_audit.md"
BASELINE_JSON = PROJECT_ROOT / "reports" / "dead_sliders_audit_baseline.json"

FIELDS = ("x", "y", "z", "w")
_ALIAS_RE = re.compile(r"\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:clamp\()?u\.zoom_params")


def strip_comments(src: str) -> str:
    def _blank(m: re.Match) -> str:
        return "\n" * m.group(0).count("\n")

    src = re.sub(r"/\*.*?\*/", _blank, src, flags=re.DOTALL)
    src = re.sub(r"//[^\n]*", "", src)
    return src


def _rel(p: Path) -> str:
    try:
        return str(p.relative_to(PROJECT_ROOT))
    except ValueError:
        return str(p)


def extract_params(meta: dict) -> list[dict]:
    """Return [{id, name, field}] for all slider params of a definition."""
    out = []
    if isinstance(meta.get("params"), list) and meta["params"]:
        for i, p in enumerate(meta["params"][:4]):
            mapping = p.get("mapping") or f"zoom_params.{FIELDS[i]}"
            field = mapping.rsplit(".", 1)[-1]
            if field in FIELDS:
                out.append({"id": p.get("id", f"param{i+1}"),
                            "name": p.get("name", ""), "field": field})
    elif isinstance(meta.get("parameters"), list) and meta["parameters"]:
        for i, p in enumerate(meta["parameters"][:4]):
            if "uniform" in p:
                field = p["uniform"].rsplit(".", 1)[-1]
            elif str(p.get("name", "")).startswith("zoom_params."):
                field = str(p["name"]).rsplit(".", 1)[-1]
            else:
                field = FIELDS[i]
            if field in FIELDS:
                out.append({"id": p.get("id", p.get("label", f"param{i+1}")),
                            "name": p.get("label", p.get("name", "")), "field": field})
    elif isinstance(meta.get("uniforms"), list) and meta["uniforms"]:
        for i, p in enumerate(meta["uniforms"][:4]):
            mapping = p.get("mapping") or f"zoom_params.{FIELDS[i]}"
            field = mapping.rsplit(".", 1)[-1]
            if field in FIELDS:
                out.append({"id": p.get("id", p.get("name", f"param{i+1}")),
                            "name": p.get("name", ""), "field": field})
    elif isinstance(meta.get("controls"), list):
        for c in meta["controls"]:
            if c.get("type") not in ("slider", "range"):
                continue
            if "uniform" in c:
                field = c["uniform"].rsplit(".", 1)[-1]
            elif "uniformMapping" in c:
                field = c["uniformMapping"].get("field", "")
            else:
                continue
            if field in FIELDS:
                out.append({"id": c.get("id", c.get("name", "")),
                            "name": c.get("name", ""), "field": field})
    return out


def fields_read(wgsl: str) -> set[str]:
    """Which zoom_params fields the WGSL reads (x/y/z/w)."""
    src = strip_comments(wgsl)
    read: set[str] = set()
    for m in re.finditer(r"zoom_params\.([xyzw])", src):
        read.add(m.group(1))
    for m in re.finditer(r"zoom_params\[(\d)u?\]", src):
        read.add(FIELDS[int(m.group(1))])
    for alias in _ALIAS_RE.findall(src):
        for m in re.finditer(rf"\b{re.escape(alias)}\.([xyzw])", src):
            read.add(m.group(1))
    return read


def wgsl_path_for(def_path: Path, meta: dict) -> Path | None:
    url = meta.get("url", "")
    name = url.rsplit("/", 1)[-1] if url else f"{meta.get('id', def_path.stem)}.wgsl"
    p = SHADERS_DIR / name
    if p.exists():
        return p
    p = SHADERS_DIR / f"{def_path.stem}.wgsl"
    return p if p.exists() else None


def scan_definition(def_path: Path) -> dict | None:
    try:
        meta = json.loads(def_path.read_text(encoding="utf-8"))
    except Exception as e:
        return {"id": def_path.stem, "def": _rel(def_path),
                "error": f"json parse: {e}"}
    params = extract_params(meta)
    if not params:
        return None  # no slider params -> nothing to audit
    sid = meta.get("id", def_path.stem)
    
    graph_nodes = meta.get("multipass", {}).get("graph", {}).get("nodes", [])
    if graph_nodes:
        all_read: set[str] = set()
        for node in graph_nodes:
            entry = node.get("entry")
            if entry:
                node_wgsl = SHADERS_DIR / f"{entry}.wgsl"
                if node_wgsl.exists():
                    all_read.update(fields_read(node_wgsl.read_text(encoding="utf-8", errors="replace")))
        dead = [p for p in params if p["field"] not in all_read]
        return {
            "id": sid,
            "def": _rel(def_path),
            "category": def_path.parent.name,
            "params": params,
            "dead": dead,
            "wgsl": _rel(def_path),
        }

    wgsl = wgsl_path_for(def_path, meta)
    if wgsl is None:
        return {"id": sid, "def": _rel(def_path),
                "error": "wgsl missing"}
    read = fields_read(wgsl.read_text(encoding="utf-8", errors="replace"))
    dead = [p for p in params if p["field"] not in read]
    return {
        "id": sid,
        "def": _rel(def_path),
        "category": def_path.parent.name,
        "params": params,
        "dead": dead,
        "wgsl": _rel(wgsl),
    }


def load_baseline() -> dict[str, list[str]]:
    if not BASELINE_JSON.exists():
        return {}
    data = json.loads(BASELINE_JSON.read_text())
    return {e["id"]: list(e["dead_param_ids"]) for e in data.get("entries", [])}


def write_baseline(results: list[dict]) -> None:
    entries = []
    for r in results:
        if r.get("dead"):
            entries.append({
                "id": r["id"],
                "category": r.get("category", ""),
                "dead_param_ids": [p["id"] for p in r["dead"]],
            })
    payload = {
        "generated": datetime.now(timezone.utc).isoformat(),
        "reason": "Triaged legacy dead sliders present at audit introduction "
        "(2026-07-26). Do NOT add new entries; wire the param in WGSL or "
        "remove it from the definition instead.",
        "entries": sorted(entries, key=lambda e: e["id"]),
    }
    BASELINE_JSON.write_text(json.dumps(payload, indent=2) + "\n")


def iter_definition_files(category: str | None) -> list[Path]:
    if category:
        return sorted((DEFINITIONS_DIR / category).glob("*.json"))
    return sorted(DEFINITIONS_DIR.glob("*/*.json"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--category", default=None, help="Only this category dir")
    ap.add_argument("--files", nargs="*", default=None,
                    help="Shader ids to audit (by definition file stem)")
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    def_files = iter_definition_files(args.category)
    if args.files:
        wanted = set(args.files)
        def_files = [p for p in def_files if p.stem in wanted]

    results = []
    for p in def_files:
        r = scan_definition(p)
        if r is not None:
            results.append(r)

    if args.write_baseline:
        write_baseline([r for r in results if not r.get("error")])
        print(f"baseline written: {BASELINE_JSON} "
              f"({sum(1 for r in results if r.get('dead'))} defs with dead sliders)")
        return 0

    baseline = load_baseline()
    new_dead: list[dict] = []
    known_dead: list[dict] = []
    errors = [r for r in results if r.get("error")]

    for r in results:
        if r.get("error"):
            continue
        known_ids = set(baseline.get(r["id"], []))
        for p in r["dead"]:
            rec = {"id": r["id"], "category": r.get("category", ""),
                   "param_id": p["id"], "name": p["name"], "field": p["field"]}
            (known_dead if p["id"] in known_ids else new_dead).append(rec)

    report = {
        "generated": datetime.now(timezone.utc).isoformat(),
        "defs_scanned": len(results),
        "defs_with_params": sum(1 for r in results if not r.get("error")),
        "new_dead_sliders": new_dead,
        "known_dead_sliders": known_dead,
        "errors": errors,
        "baseline": str(BASELINE_JSON.relative_to(PROJECT_ROOT)),
    }

    REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
    REPORT_JSON.write_text(json.dumps(report, indent=2) + "\n")

    md = [
        "# Dead Slider Audit",
        "",
        f"- Definitions scanned: {len(results)}",
        f"- **New dead sliders: {len(new_dead)}**",
        f"- Known (triaged baseline) dead sliders: {len(known_dead)}",
        f"- Def errors (missing WGSL / parse): {len(errors)}",
        "",
    ]
    if new_dead:
        md.append("## New dead sliders\n")
        for d in new_dead:
            md.append(f"- `{d['id']}` ({d['category']}): param `{d['param_id']}` "
                      f"\"{d['name']}\" → zoom_params.{d['field']} never read")
        md.append("")
    REPORT_MD.write_text("\n".join(md) + "\n")

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("\n".join(md[:9]))

    if new_dead:
        print("AUDIT FAIL: new dead sliders detected (wire the WGSL read or "
              "remove the param)", file=sys.stderr)
        return 1
    print("AUDIT PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
