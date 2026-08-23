#!/usr/bin/env python3
"""
Tri-source shader catalog drift audit (definitions ↔ WGSL ↔ multipass registry ↔ lists).

Source of truth (D1): shader_definitions/** for shader id and declared WGSL path.
WGSL on-disk filenames must match the definition url; multipass registry entries
must be derivable from definitions (buildMultipassRegistry.js output).

Outputs:
  reports/catalog_drift.json
  reports/catalog_drift.md

Baseline (D2): reports/catalog_drift_baseline.json — gate fails only on violations
not present in the baseline (or when total count rises above baseline count).

Usage:
  python3 scripts/audit_catalog_consistency.py --report
  python3 scripts/audit_catalog_consistency.py --gate
  python3 scripts/audit_catalog_consistency.py --write-baseline
  python3 scripts/audit_catalog_consistency.py --ensure-lists   # run generate_shader_lists.js first
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFINITIONS_DIR = PROJECT_ROOT / "shader_definitions"
SHADERS_DIR = PROJECT_ROOT / "public" / "shaders"
SHADER_LISTS_DIR = PROJECT_ROOT / "public" / "shader-lists"
MULTIPASS_REGISTRY_TS = PROJECT_ROOT / "src" / "renderer" / "multipassRegistry.ts"
REPORT_JSON = PROJECT_ROOT / "reports" / "catalog_drift.json"
REPORT_MD = PROJECT_ROOT / "reports" / "catalog_drift.md"
BASELINE_JSON = PROJECT_ROOT / "reports" / "catalog_drift_baseline.json"
GENERATE_LISTS = PROJECT_ROOT / "scripts" / "generate_shader_lists.js"

WGSL_IGNORE_PREFIXES = ("_",)
ALLOWLIST_IDS = frozenset({"gen_capabilities", "wasm-bridge-probe", "cdn-placeholder"})


def _rel(path: Path) -> str:
    try:
        return str(path.relative_to(PROJECT_ROOT))
    except ValueError:
        return str(path)


def violation_key(vtype: str, shader_id: str, detail: str = "") -> str:
    detail_norm = re.sub(r"\s+", " ", detail.strip())
    return f"{vtype}|{shader_id}|{detail_norm}"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def read_definition(path: Path) -> dict | None:
    try:
        data = load_json(path)
        if isinstance(data, list):
            data = data[0] if data else None
        return data if isinstance(data, dict) else None
    except (json.JSONDecodeError, OSError):
        return None


def discover_definition_paths() -> list[Path]:
    if not DEFINITIONS_DIR.exists():
        return []
    return sorted(DEFINITIONS_DIR.rglob("*.json"))


def load_definitions_parallel(paths: list[Path]) -> list[tuple[Path, dict | None]]:
    rows: list[tuple[Path, dict | None]] = []
    with ThreadPoolExecutor(max_workers=16) as pool:
        futures = {pool.submit(read_definition, p): p for p in paths}
        for fut in as_completed(futures):
            path = futures[fut]
            rows.append((path, fut.result()))
    return sorted(rows, key=lambda x: str(x[0]))


def collect_multipass_secondary_ids(definitions: list[tuple[Path, dict]]) -> set[str]:
  """Mirror scripts/generate_shader_lists.js secondary-id skip set."""
  secondary: set[str] = set()
  primaries: list[dict] = []
  for _, data in definitions:
      if not data or not data.get("id"):
          continue
      primaries.append(data)
  for shader_def in primaries:
      primary_id = shader_def["id"]
      multipass = shader_def.get("multipass") or {}
      if multipass.get("nextShader"):
          secondary.add(str(multipass["nextShader"]))
      for pass_entry in multipass.get("passes") or []:
          if isinstance(pass_entry, dict) and pass_entry.get("file"):
              stem = str(pass_entry["file"]).replace(".wgsl", "")
              if stem and stem != primary_id:
                  secondary.add(stem)
      for node in (multipass.get("graph") or {}).get("nodes") or []:
          if isinstance(node, dict) and node.get("entry") and node["entry"] != primary_id:
              secondary.add(str(node["entry"]))
  return secondary


def url_to_wgsl_path(url: str) -> Path:
    rel = str(url).replace("\\", "/").lstrip("./")
    if rel.startswith("shaders/"):
        rel = f"public/{rel}"
    elif not rel.startswith("public/"):
        rel = f"public/shaders/{Path(rel).name}"
    return PROJECT_ROOT / rel


def expected_wgsl_name(defn: dict, json_path: Path) -> str:
    url = defn.get("url") or ""
    if url:
        name = Path(str(url)).name
        return name if name.endswith(".wgsl") else f"{name}.wgsl"
    return f"{json_path.stem}.wgsl"


def build_expected_multipass(definitions: list[tuple[Path, dict]]) -> tuple[dict, dict]:
    registry: dict[str, dict] = {}
    graph_registry: dict[str, dict] = {}
    for _, data in definitions:
        if not data or not data.get("id"):
            continue
        sid = str(data["id"])
        mp = data.get("multipass") or {}
        if mp.get("graph"):
            graph_registry[sid] = mp["graph"]
        if mp.get("pass") is not None:
            registry[sid] = {
                "pass": mp.get("pass"),
                "totalPasses": mp.get("totalPasses"),
                "nextShader": mp.get("nextShader") or None,
            }
    return registry, graph_registry


def parse_ts_export_json(ts_path: Path, export_name: str) -> dict:
    if not ts_path.exists():
        return {}
    text = ts_path.read_text(encoding="utf-8")
    pattern = rf"export const {export_name}[^=]*=\s*(\{{[\s\S]*?\n\}});"
    match = re.search(pattern, text)
    if not match:
        return {}
    try:
        return json.loads(match.group(1))
    except json.JSONDecodeError:
        return {}


def referenced_wgsl_filenames(definitions: list[tuple[Path, dict]]) -> set[str]:
    names: set[str] = set()
    for _, data in definitions:
        if not data:
            continue
        url = data.get("url")
        if url:
            names.add(expected_wgsl_name(data, Path("x.json")))
        mp = data.get("multipass") or {}
        for entry in mp.get("passes") or []:
            if isinstance(entry, dict) and entry.get("file"):
                fn = str(entry["file"])
                names.add(fn if fn.endswith(".wgsl") else f"{fn}.wgsl")
    return names


def run_generate_shader_lists() -> tuple[bool, str]:
    if not GENERATE_LISTS.exists():
        return False, "missing generate_shader_lists.js"
    result = subprocess.run(
        ["node", str(GENERATE_LISTS)],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
    )
    ok = result.returncode == 0
    msg = (result.stdout + result.stderr).strip()
    return ok, msg


def load_shader_list_ids() -> set[str]:
    ids: set[str] = set()
    if not SHADER_LISTS_DIR.exists():
        return ids
    for list_path in SHADER_LISTS_DIR.glob("*.json"):
        try:
            entries = load_json(list_path)
        except (json.JSONDecodeError, OSError):
            continue
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if isinstance(entry, dict) and entry.get("id"):
                ids.add(str(entry["id"]))
    return ids


def audit_catalog(
    definitions: list[tuple[Path, dict | None]],
    *,
    lists_regenerated: bool,
) -> dict[str, Any]:
    valid_defs: list[tuple[Path, dict]] = [(p, d) for p, d in definitions if d and d.get("id")]
    secondary_ids = collect_multipass_secondary_ids(valid_defs)
    expected_mp, expected_graph = build_expected_multipass(valid_defs)
    actual_mp = parse_ts_export_json(MULTIPASS_REGISTRY_TS, "MULTIPASS_REGISTRY")
    actual_graph = parse_ts_export_json(MULTIPASS_REGISTRY_TS, "GRAPH_REGISTRY")

    def_ids = {str(d["id"]) for _, d in valid_defs}
    def_by_id = {str(d["id"]): (p, d) for p, d in valid_defs}
    referenced_wgsl = referenced_wgsl_filenames(valid_defs)

    violations: list[dict[str, Any]] = []

    # --- definitions ↔ WGSL ---
    for path, data in valid_defs:
        sid = str(data["id"])
        wgsl_name = expected_wgsl_name(data, path)
        wgsl_stem = Path(wgsl_name).stem
        wgsl_path = url_to_wgsl_path(data.get("url") or f"shaders/{wgsl_name}")

        if sid in ALLOWLIST_IDS:
            continue

        if wgsl_stem != sid and sid not in secondary_ids:
            violations.append({
                "type": "id-filename-mismatch",
                "id": sid,
                "def_path": _rel(path),
                "detail": f"definition id '{sid}' vs url stem '{wgsl_stem}'",
                "key": violation_key("id-filename-mismatch", sid, wgsl_stem),
            })

        if not wgsl_path.exists():
            violations.append({
                "type": "definition-without-wgsl",
                "id": sid,
                "def_path": _rel(path),
                "detail": f"missing {_rel(wgsl_path)}",
                "key": violation_key("definition-without-wgsl", sid, _rel(wgsl_path)),
            })

    # parse errors
    for path, data in definitions:
        if data is None:
            violations.append({
                "type": "definition-parse-error",
                "id": path.stem,
                "def_path": _rel(path),
                "detail": "invalid JSON",
                "key": violation_key("definition-parse-error", path.stem, _rel(path)),
            })

    # --- WGSL without definition ---
    if SHADERS_DIR.exists():
        def_stems = {Path(expected_wgsl_name(d, p)).stem for p, d in valid_defs}
        def_stems |= def_ids
        for wgsl_path in sorted(SHADERS_DIR.glob("*.wgsl")):
            stem = wgsl_path.stem
            name = wgsl_path.name
            if any(stem.startswith(p) for p in WGSL_IGNORE_PREFIXES):
                continue
            if stem.endswith("-sg") and stem[:-3] in def_stems:
                continue
            if stem in def_stems or stem in def_ids or name in referenced_wgsl:
                continue
            violations.append({
                "type": "wgsl-without-definition",
                "id": stem,
                "def_path": "",
                "detail": _rel(wgsl_path),
                "key": violation_key("wgsl-without-definition", stem, name),
            })

    # --- multipass registry drift (definitions SoT) ---
    for sid in sorted(set(expected_mp) | set(actual_mp)):
        if sid not in actual_mp:
            def_path = _rel(def_by_id[sid][0]) if sid in def_by_id else ""
            violations.append({
                "type": "missing-graph-entry",
                "id": sid,
                "def_path": def_path,
                "detail": "MULTIPASS_REGISTRY missing entry (stale multipassRegistry.ts)",
                "key": violation_key("missing-graph-entry", sid, "MULTIPASS_REGISTRY"),
            })
        elif sid in expected_mp and expected_mp[sid] != actual_mp[sid]:
            violations.append({
                "type": "registry-entry-mismatch",
                "id": sid,
                "def_path": _rel(def_by_id[sid][0]) if sid in def_by_id else "",
                "detail": "MULTIPASS_REGISTRY entry differs from shader_definitions",
                "key": violation_key("registry-entry-mismatch", sid, "MULTIPASS_REGISTRY"),
            })

    for sid in sorted(set(expected_graph) | set(actual_graph)):
        if sid not in actual_graph:
            def_path = _rel(def_by_id[sid][0]) if sid in def_by_id else ""
            violations.append({
                "type": "missing-graph-entry",
                "id": sid,
                "def_path": def_path,
                "detail": "GRAPH_REGISTRY missing entry (stale multipassRegistry.ts)",
                "key": violation_key("missing-graph-entry", sid, "GRAPH_REGISTRY"),
            })
        elif sid in expected_graph and expected_graph[sid] != actual_graph[sid]:
            violations.append({
                "type": "registry-entry-mismatch",
                "id": sid,
                "def_path": _rel(def_by_id[sid][0]) if sid in def_by_id else "",
                "detail": "GRAPH_REGISTRY entry differs from shader_definitions",
                "key": violation_key("registry-entry-mismatch", sid, "GRAPH_REGISTRY"),
            })

    for sid in sorted(actual_mp):
        if sid not in def_ids:
            violations.append({
                "type": "orphan-graph-entry",
                "id": sid,
                "def_path": "",
                "detail": "MULTIPASS_REGISTRY id not in shader_definitions",
                "key": violation_key("orphan-graph-entry", sid, "MULTIPASS_REGISTRY"),
            })

    for sid in sorted(actual_graph):
        if sid not in def_ids:
            violations.append({
                "type": "orphan-graph-entry",
                "id": sid,
                "def_path": "",
                "detail": "GRAPH_REGISTRY id not in shader_definitions",
                "key": violation_key("orphan-graph-entry", sid, "GRAPH_REGISTRY"),
            })

    # graph node entry ids
    for sid, graph in expected_graph.items():
        for node in graph.get("nodes") or []:
            if not isinstance(node, dict):
                continue
            entry = node.get("entry")
            if entry and str(entry) not in def_ids:
                violations.append({
                    "type": "orphan-graph-entry",
                    "id": str(entry),
                    "def_path": _rel(def_by_id[sid][0]) if sid in def_by_id else "",
                    "detail": f"graph node entry referenced by '{sid}'",
                    "key": violation_key("orphan-graph-entry", str(entry), f"from-graph:{sid}"),
                })

    # nextShader chain integrity
    for sid, info in expected_mp.items():
        nxt = info.get("nextShader")
        if nxt and str(nxt) not in def_ids:
            violations.append({
                "type": "orphan-graph-entry",
                "id": str(nxt),
                "def_path": _rel(def_by_id[sid][0]) if sid in def_by_id else "",
                "detail": f"nextShader from '{sid}'",
                "key": violation_key("orphan-graph-entry", str(nxt), f"nextShader:{sid}"),
            })

    # --- shader lists (after optional regen) ---
    list_ids = load_shader_list_ids()
    catalog_ids = {sid for sid in def_ids if sid not in secondary_ids}

    for sid in sorted(catalog_ids):
        if sid not in list_ids:
            path = def_by_id[sid][0]
            violations.append({
                "type": "missing-list-entry",
                "id": sid,
                "def_path": _rel(path),
                "detail": "id absent from public/shader-lists after generate_shader_lists",
                "key": violation_key("missing-list-entry", sid, "shader-lists"),
            })

    for sid in sorted(list_ids):
        if sid not in def_ids:
            violations.append({
                "type": "orphan-list-entry",
                "id": sid,
                "def_path": "",
                "detail": "shader-lists id not in shader_definitions",
                "key": violation_key("orphan-list-entry", sid, "shader-lists"),
            })

    by_type: dict[str, int] = {}
    for v in violations:
        by_type[v["type"]] = by_type.get(v["type"], 0) + 1

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source_of_truth": "shader_definitions/** (id + url path)",
        "lists_regenerated": lists_regenerated,
        "definitions_scanned": len(definitions),
        "definitions_valid": len(valid_defs),
        "wgsl_files": len(list(SHADERS_DIR.glob("*.wgsl"))) if SHADERS_DIR.exists() else 0,
        "shader_list_ids": len(list_ids),
        "multipass_registry_entries": len(actual_mp),
        "graph_registry_entries": len(actual_graph),
        "violation_count": len(violations),
        "violations_by_type": by_type,
        "violations": violations,
    }


def load_baseline_keys() -> set[str]:
    if not BASELINE_JSON.exists():
        return set()
    try:
        data = load_json(BASELINE_JSON)
    except (json.JSONDecodeError, OSError):
        return set()
    keys = data.get("violation_keys")
    if isinstance(keys, list):
        return {str(k) for k in keys}
    # legacy: full violation objects
    violations = data.get("violations") or []
    out: set[str] = set()
    for v in violations:
        if isinstance(v, dict) and v.get("key"):
            out.add(str(v["key"]))
    return out


def evaluate_gate(report: dict, baseline_keys: set[str]) -> tuple[bool, list[dict]]:
    new_violations: list[dict] = []
    for v in report.get("violations") or []:
        key = v.get("key") or violation_key(v["type"], v.get("id", ""), v.get("detail", ""))
        if key not in baseline_keys:
            new_violations.append(v)
    baseline_count = len(baseline_keys)
    current_count = report.get("violation_count", 0)
    ok = len(new_violations) == 0 and current_count <= baseline_count
    return ok, new_violations


def write_markdown(report: dict, path: Path) -> None:
    lines = [
        "# Catalog drift audit",
        "",
        f"Generated: {report['timestamp']}",
        "",
        f"Source of truth: `{report.get('source_of_truth', '')}`",
        f"Lists regenerated this run: {report.get('lists_regenerated')}",
        "",
        "## Summary",
        "",
        f"- Definitions scanned: {report['definitions_scanned']}",
        f"- Valid definitions: {report['definitions_valid']}",
        f"- WGSL files on disk: {report['wgsl_files']}",
        f"- Shader list ids: {report['shader_list_ids']}",
        f"- Violations: **{report['violation_count']}**",
        "",
        "| Type | Count |",
        "|------|------:|",
    ]
    for k, n in sorted(report.get("violations_by_type", {}).items()):
        lines.append(f"| `{k}` | {n} |")

    lines.extend(["", "## Violations (first 100)", ""])
    for v in (report.get("violations") or [])[:100]:
        lines.append(
            f"- `{v['type']}` **{v['id']}** — {v.get('detail', '')}"
            + (f" (`{v['def_path']}`)" if v.get("def_path") else "")
        )
    if report["violation_count"] > 100:
        lines.append(f"- … and {report['violation_count'] - 100} more (see JSON)")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_baseline(report: dict) -> None:
    keys = sorted({v["key"] for v in report.get("violations") or []})
    payload = {
        "description": (
            "Accepted catalog drift violation keys. CI gate fails when the audit "
            "finds keys not listed here. Shrink this file as drift is fixed; never "
            "grow it silently in CI — only via --write-baseline after intentional triage."
        ),
        "generated": datetime.now(timezone.utc).isoformat(),
        "violation_count": len(keys),
        "violation_keys": keys,
    }
    BASELINE_JSON.parent.mkdir(parents=True, exist_ok=True)
    BASELINE_JSON.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit shader catalog tri-source consistency.")
    parser.add_argument("--report", action="store_true", help="Write reports only (exit 0)")
    parser.add_argument("--gate", action="store_true", help="Fail on non-baseline violations")
    parser.add_argument("--write-baseline", action="store_true", help="Write baseline from current scan")
    parser.add_argument(
        "--ensure-lists",
        action="store_true",
        help="Run node scripts/generate_shader_lists.js before auditing lists",
    )
    parser.add_argument("--json", action="store_true", help="Print JSON report to stdout")
    args = parser.parse_args()

    lists_regenerated = False
    if args.ensure_lists:
        ok, msg = run_generate_shader_lists()
        lists_regenerated = ok
        if not ok:
            print(f"WARNING: generate_shader_lists failed: {msg}", file=sys.stderr)

    paths = discover_definition_paths()
    definitions = load_definitions_parallel(paths)
    report = audit_catalog(definitions, lists_regenerated=lists_regenerated)

    REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
    REPORT_JSON.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    write_markdown(report, REPORT_MD)

    if args.write_baseline:
        write_baseline(report)
        print(f"Wrote baseline with {report['violation_count']} keys to {_rel(BASELINE_JSON)}")

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"Catalog drift: {report['violation_count']} violations")
        for k, n in sorted(report.get("violations_by_type", {}).items()):
            print(f"  {k}: {n}")
        print(f"Wrote {_rel(REPORT_JSON)}")

    if args.report or args.write_baseline:
        return 0

    if args.gate:
        baseline_keys = load_baseline_keys()
        ok, new_v = evaluate_gate(report, baseline_keys)
        if not ok:
            print(f"GATE FAIL: {len(new_v)} new violation(s) not in baseline", file=sys.stderr)
            for v in new_v[:30]:
                print(f"  • {v['key']}: {v.get('detail')}", file=sys.stderr)
            if len(new_v) > 30:
                print(f"  … and {len(new_v) - 30} more", file=sys.stderr)
            return 1
        print("GATE PASS: no new catalog drift beyond baseline")
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
