#!/usr/bin/env python3
"""
Offline auditor for shader_definitions JSON entries whose local WGSL is missing.

Classifies each definition:
  - local          — public/shaders/<file>.wgsl exists
  - storage-only   — missing locally but id appears in shader_coordinates.json
                     and/or storage_manager/seed_shaders.json (VPS-served)
  - allowlisted    — known dynamic/runtime id (WASM, CDN, capabilities probe)
  - likely-broken  — missing locally and not in any manifest

Outputs:
  reports/orphan_shader_defs.json
  reports/orphan_shader_defs.md

Network-free; safe for CI per-PR gates.

Manifest sources for storage-only classification:
  - Primary: public/shader_coordinates.json (keys = shader ids used by the app)
  - Secondary: storage_manager/seed_shaders.json (id + filename fields)
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFINITIONS_DIR = PROJECT_ROOT / "shader_definitions"
SHADERS_DIR = PROJECT_ROOT / "public" / "shaders"
COORDINATES_PATH = PROJECT_ROOT / "public" / "shader_coordinates.json"
SEED_SHADERS_PATH = PROJECT_ROOT / "storage_manager" / "seed_shaders.json"
REPORT_JSON = PROJECT_ROOT / "reports" / "orphan_shader_defs.json"
REPORT_MD = PROJECT_ROOT / "reports" / "orphan_shader_defs.md"

# Known runtime / probe ids that intentionally have no committed WGSL body.
ALLOWLIST_IDS = frozenset({
    "gen_capabilities",
    "wasm-bridge-probe",
    "cdn-placeholder",
})

ALLOWLIST_PREFIXES = (
    "__",
)


def load_coordinates_ids() -> set[str]:
    if not COORDINATES_PATH.exists():
        return set()
    data = json.loads(COORDINATES_PATH.read_text(encoding="utf-8"))
    return set(data.keys())


def load_seed_manifest_ids() -> tuple[set[str], set[str]]:
    """Return (ids, wgsl_filenames) from seed_shaders.json."""
    if not SEED_SHADERS_PATH.exists():
        return set(), set()
    entries = json.loads(SEED_SHADERS_PATH.read_text(encoding="utf-8"))
    ids: set[str] = set()
    filenames: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        sid = entry.get("id")
        if sid:
            ids.add(str(sid))
        fn = entry.get("filename")
        if fn:
            filenames.add(str(fn))
            stem = Path(fn).stem
            if stem:
                ids.add(stem)
    return ids, filenames


def is_allowlisted(shader_id: str) -> bool:
    if shader_id in ALLOWLIST_IDS:
        return True
    return any(shader_id.startswith(p) for p in ALLOWLIST_PREFIXES)


def expected_wgsl_from_def(defn: dict, json_path: Path) -> tuple[str, str]:
    """
    Return (shader_id, expected_filename) from a definition record.
    Primary: url field (shaders/foo.wgsl). Fallback: id.wgsl.
    """
    shader_id = str(defn.get("id") or json_path.stem)
    url = defn.get("url") or ""
    if url:
        name = Path(str(url)).name
        if name and not name.endswith(".wgsl"):
            name = f"{name}.wgsl"
        return shader_id, name
    return shader_id, f"{shader_id}.wgsl"


def classify_definition(
    shader_id: str,
    wgsl_name: str,
    def_path: Path,
    coord_ids: set[str],
    seed_ids: set[str],
    seed_filenames: set[str],
) -> dict:
    local_path = SHADERS_DIR / wgsl_name
    exists = local_path.exists()

    if exists:
        classification = "local"
    elif is_allowlisted(shader_id):
        classification = "allowlisted"
    elif shader_id in coord_ids or shader_id in seed_ids or wgsl_name in seed_filenames:
        classification = "storage-only"
    else:
        classification = "likely-broken"

    return {
        "id": shader_id,
        "def_path": str(def_path.relative_to(PROJECT_ROOT)),
        "expected_wgsl": wgsl_name,
        "local_path": str(local_path.relative_to(PROJECT_ROOT)),
        "local_exists": exists,
        "classification": classification,
        "in_shader_coordinates": shader_id in coord_ids,
        "in_seed_shaders": shader_id in seed_ids or wgsl_name in seed_filenames,
    }


def audit_definitions() -> dict:
    coord_ids = load_coordinates_ids()
    seed_ids, seed_filenames = load_seed_manifest_ids()

    rows: list[dict] = []
    for json_path in sorted(DEFINITIONS_DIR.rglob("*.json")):
        try:
            defn = json.loads(json_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            rows.append({
                "id": json_path.stem,
                "def_path": str(json_path.relative_to(PROJECT_ROOT)),
                "expected_wgsl": "",
                "local_path": "",
                "local_exists": False,
                "classification": "parse-error",
                "error": str(e),
                "in_shader_coordinates": False,
                "in_seed_shaders": False,
            })
            continue

        shader_id, wgsl_name = expected_wgsl_from_def(defn, json_path)
        rows.append(
            classify_definition(
                shader_id, wgsl_name, json_path, coord_ids, seed_ids, seed_filenames
            )
        )

    summary = {
        "local": sum(1 for r in rows if r["classification"] == "local"),
        "storage-only": sum(1 for r in rows if r["classification"] == "storage-only"),
        "allowlisted": sum(1 for r in rows if r["classification"] == "allowlisted"),
        "likely-broken": sum(1 for r in rows if r["classification"] == "likely-broken"),
        "parse-error": sum(1 for r in rows if r["classification"] == "parse-error"),
    }

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "definitions_scanned": len(rows),
        "manifests": {
            "shader_coordinates": str(COORDINATES_PATH.relative_to(PROJECT_ROOT)),
            "shader_coordinates_count": len(coord_ids),
            "seed_shaders": str(SEED_SHADERS_PATH.relative_to(PROJECT_ROOT)),
            "seed_shaders_count": len(seed_ids),
        },
        "summary": summary,
        "entries": rows,
    }


def write_markdown(report: dict, path: Path) -> None:
    lines = [
        "# Orphan shader definition audit",
        "",
        f"Generated: {report['timestamp']}",
        "",
        "## Summary",
        "",
        "| Classification | Count |",
        "|----------------|------:|",
    ]
    for key, count in report["summary"].items():
        lines.append(f"| `{key}` | {count} |")

    lines.extend(["", "## Non-local entries", ""])
    non_local = [
        r for r in report["entries"]
        if r["classification"] not in ("local",)
    ]
    if not non_local:
        lines.append("_All definitions have a matching local WGSL file._")
    else:
        lines.extend([
            "| id | def | expected wgsl | classification | in coords | in seed |",
            "|----|-----|---------------|----------------|-----------|---------|",
        ])
        for r in non_local:
            lines.append(
                f"| `{r['id']}` | `{r['def_path']}` | `{r['expected_wgsl']}` | "
                f"**{r['classification']}** | {r.get('in_shader_coordinates', False)} | "
                f"{r.get('in_seed_shaders', False)} |"
            )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def print_summary(report: dict) -> None:
    s = report["summary"]
    print("=" * 60)
    print("ORPHAN SHADER DEF AUDIT")
    print("=" * 60)
    print(f"Definitions scanned: {report['definitions_scanned']}")
    for key, count in s.items():
        marker = " [WARN]" if key == "likely-broken" and count else ""
        print(f"  {key}: {count}{marker}")
    if s.get("likely-broken"):
        print("\n[WARN] likely-broken entries (missing local WGSL, not in manifests):")
        for r in report["entries"]:
            if r["classification"] == "likely-broken":
                print(f"  • {r['id']} ({r['def_path']}) -> {r['expected_wgsl']}")
    print("=" * 60)


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit shader_definitions vs local WGSL files.")
    parser.add_argument("--json", action="store_true", help="Print JSON report to stdout")
    args = parser.parse_args()

    report = audit_definitions()

    REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
    REPORT_JSON.write_text(json.dumps(report, indent=2), encoding="utf-8")
    write_markdown(report, REPORT_MD)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_summary(report)
        print(f"Wrote {REPORT_JSON.relative_to(PROJECT_ROOT)}")
        print(f"Wrote {REPORT_MD.relative_to(PROJECT_ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
