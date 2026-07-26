#!/usr/bin/env python3
"""
Shader catalog hygiene auditor — defs ↔ WGSL pairing.

Classifies each shader_definitions JSON entry:
  - local          — public/shaders/<file>.wgsl exists
  - storage-only   — missing locally but id appears in shader_coordinates.json
                     and/or storage_manager/seed_shaders.json (VPS-served)
  - allowlisted    — known dynamic/runtime id (WASM, CDN, capabilities probe)
  - likely-broken  — missing locally and not in any manifest (only_def)

Also reports WGSL files without a catalog entry (only_wgsl), excluding:
  - `_` prefix (templates / hash library)
  - `-sg` subgroup variants when base id is cataloged
  - multipass secondary passes referenced by a primary JSON or multipassRegistry

Outputs:
  reports/orphan_shader_defs.json
  reports/orphan_shader_defs.md

Network-free; safe for CI per-PR gates.

Exit code 1 when:
  - --ci-gate: any full-tree `likely-broken` or `parse-error` not in
    reports/orphan_baseline.json (CI default)
  - --base: any **changed** definition classifies as likely-broken/parse-error
    (forward-only, local pre-commit hook)

Without flags, exits 0 after writing reports (use --fail-all for legacy
only_def + only_wgsl full-tree enforcement).

Manifest sources for storage-only classification:
  - Primary: public/shader_coordinates.json (keys = shader ids used by the app)
  - Secondary: storage_manager/seed_shaders.json (id + filename fields)

Cross-reference: docs/SHADER_TEMPLATES.md, scripts/seed_orphan_shader_defs.py
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFINITIONS_DIR = PROJECT_ROOT / "shader_definitions"
SHADERS_DIR = PROJECT_ROOT / "public" / "shaders"
PUBLIC_DIR = PROJECT_ROOT / "public"
COORDINATES_PATH = PROJECT_ROOT / "public" / "shader_coordinates.json"
SEED_SHADERS_PATH = PROJECT_ROOT / "storage_manager" / "seed_shaders.json"
MULTIPASS_REGISTRY = PROJECT_ROOT / "src" / "renderer" / "multipassRegistry.ts"
REPORT_JSON = PROJECT_ROOT / "reports" / "orphan_shader_defs.json"
REPORT_MD = PROJECT_ROOT / "reports" / "orphan_shader_defs.md"
BASELINE_JSON = PROJECT_ROOT / "reports" / "orphan_baseline.json"

ALLOWLIST_IDS = frozenset({
    "gen_capabilities",
    "wasm-bridge-probe",
    "cdn-placeholder",
})

ALLOWLIST_PREFIXES = (
    "__",
)

WGSL_IGNORE_PREFIXES = ("_",)


def discover_changed_definition_paths(base_ref: str) -> set[Path]:
    """Return shader_definitions JSON paths changed against base_ref (three-dot)."""
    diff_ref = base_ref if "..." in base_ref else f"{base_ref}...HEAD"
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMRT", diff_ref],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    changed: set[Path] = set()
    for line in result.stdout.splitlines():
        p = PROJECT_ROOT / line.strip()
        if (
            p.suffix == ".json"
            and p.exists()
            and DEFINITIONS_DIR in p.parents
        ):
            changed.add(p.resolve())
    return changed


def load_baseline_ids() -> set[str]:
    """Return shader ids grandfathered in reports/orphan_baseline.json."""
    if not BASELINE_JSON.exists():
        return set()
    try:
        data = json.loads(BASELINE_JSON.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return set()
    return {str(i) for i in (data.get("ids") or [])}


def evaluate_ci_gate(report: dict, base_ref: str = "") -> tuple[bool, list[str]]:
    """
    Full-tree CI gate: fail on likely-broken/parse-error defs not in baseline.

    base_ref is accepted for test compatibility but unused (full-tree enforcement).
    """
    _ = base_ref
    baseline = load_baseline_ids()
    failures: list[str] = []
    for row in report.get("entries", []):
        if row.get("classification") not in ("likely-broken", "parse-error"):
            continue
        if row.get("id") in baseline:
            continue
        msg = f"{row['id']} ({row['def_path']}) -> {row.get('expected_wgsl', '')}"
        if row.get("error"):
            msg += f" ({row['error']})"
        failures.append(msg)
    return len(failures) == 0, failures


def enforceable_failures(
    entries: list[dict],
    changed_paths: set[Path] | None,
) -> list[dict]:
    """Return definition rows that should fail the gate."""
    if not changed_paths:
        return []
    failures = []
    for row in entries:
        if row["classification"] not in ("likely-broken", "parse-error"):
            continue
        def_path = (PROJECT_ROOT / row["def_path"]).resolve()
        if def_path in changed_paths:
            failures.append(row)
    return failures


def load_coordinates_ids() -> set[str]:
    if not COORDINATES_PATH.exists():
        return set()
    data = json.loads(COORDINATES_PATH.read_text(encoding="utf-8"))
    return set(data.keys())


def load_seed_manifest_ids() -> tuple[set[str], set[str]]:
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


def load_referenced_wgsl_filenames() -> set[str]:
    """WGSL basenames referenced by defs (url + multipass.passes) and multipass registry."""
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
        text = MULTIPASS_REGISTRY.read_text(encoding="utf-8")
        names |= {
            (m if m.endswith(".wgsl") else f"{m}.wgsl")
            for m in re.findall(r'"([^"]+)"', text)
        }
    return names


def is_allowlisted(shader_id: str) -> bool:
    if shader_id in ALLOWLIST_IDS:
        return True
    return any(shader_id.startswith(p) for p in ALLOWLIST_PREFIXES)


def expected_wgsl_from_def(defn: dict, json_path: Path) -> tuple[str, str]:
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


def build_def_index() -> tuple[set[str], set[str], set[str]]:
    """Return (ids, wgsl_stems_with_def, wgsl_filenames_referenced)."""
    ids: set[str] = set()
    stems: set[str] = set()
    for json_path in DEFINITIONS_DIR.rglob("*.json"):
        try:
            defn = json.loads(json_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        shader_id, wgsl_name = expected_wgsl_from_def(defn, json_path)
        ids.add(shader_id)
        stems.add(Path(wgsl_name).stem)
        stems.add(json_path.stem)
        stems.add(shader_id)
    referenced = load_referenced_wgsl_filenames()
    return ids, stems, referenced


def audit_orphan_wgsl(def_ids: set[str], def_stems: set[str], referenced: set[str]) -> list[dict]:
    rows: list[dict] = []
    for path in sorted(SHADERS_DIR.glob("*.wgsl")):
        stem = path.stem
        name = path.name
        if any(stem.startswith(p) for p in WGSL_IGNORE_PREFIXES):
            rows.append({
                "wgsl": name,
                "stem": stem,
                "classification": "template-prefix",
            })
            continue
        if stem.endswith("-sg") and stem[:-3] in def_stems:
            rows.append({
                "wgsl": name,
                "stem": stem,
                "classification": "subgroup-variant",
            })
            continue
        if stem in def_stems or stem in def_ids:
            rows.append({
                "wgsl": name,
                "stem": stem,
                "classification": "cataloged",
            })
            continue
        if name in referenced:
            rows.append({
                "wgsl": name,
                "stem": stem,
                "classification": "multipass-secondary",
            })
            continue
        rows.append({
            "wgsl": name,
            "stem": stem,
            "classification": "orphan",
        })
    return rows


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

    def_ids, def_stems, referenced = build_def_index()
    wgsl_rows = audit_orphan_wgsl(def_ids, def_stems, referenced)

    summary = {
        "local": sum(1 for r in rows if r["classification"] == "local"),
        "storage-only": sum(1 for r in rows if r["classification"] == "storage-only"),
        "allowlisted": sum(1 for r in rows if r["classification"] == "allowlisted"),
        "likely-broken": sum(1 for r in rows if r["classification"] == "likely-broken"),
        "parse-error": sum(1 for r in rows if r["classification"] == "parse-error"),
    }
    wgsl_summary = {
        "cataloged": sum(1 for r in wgsl_rows if r["classification"] == "cataloged"),
        "template-prefix": sum(1 for r in wgsl_rows if r["classification"] == "template-prefix"),
        "subgroup-variant": sum(1 for r in wgsl_rows if r["classification"] == "subgroup-variant"),
        "multipass-secondary": sum(1 for r in wgsl_rows if r["classification"] == "multipass-secondary"),
        "orphan": sum(1 for r in wgsl_rows if r["classification"] == "orphan"),
    }

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "definitions_scanned": len(rows),
        "wgsl_files_scanned": len(wgsl_rows),
        "manifests": {
            "shader_coordinates": str(COORDINATES_PATH.relative_to(PROJECT_ROOT)),
            "shader_coordinates_count": len(coord_ids),
            "seed_shaders": str(SEED_SHADERS_PATH.relative_to(PROJECT_ROOT)),
            "seed_shaders_count": len(seed_ids),
        },
        "summary": summary,
        "wgsl_summary": wgsl_summary,
        "only_def_count": summary.get("likely-broken", 0) + summary.get("parse-error", 0),
        "only_wgsl_count": wgsl_summary.get("orphan", 0),
        "entries": rows,
        "wgsl_entries": wgsl_rows,
    }


def write_markdown(report: dict, path: Path) -> None:
    lines = [
        "# Shader catalog hygiene audit",
        "",
        f"Generated: {report['timestamp']}",
        "",
        "## Definition → WGSL",
        "",
        "| Classification | Count |",
        "|----------------|------:|",
    ]
    for key, count in report["summary"].items():
        lines.append(f"| `{key}` | {count} |")

    lines.extend([
        "",
        "## WGSL → Definition",
        "",
        "| Classification | Count |",
        "|----------------|------:|",
    ])
    for key, count in report["wgsl_summary"].items():
        lines.append(f"| `{key}` | {count} |")

    lines.extend([
        "",
        f"**only_def** (defs without WGSL): {report['only_def_count']}",
        f"**only_wgsl** (unexpected orphans): {report['only_wgsl_count']}",
        "",
        "## Non-local definitions",
        "",
    ])
    non_local = [r for r in report["entries"] if r["classification"] not in ("local",)]
    if not non_local:
        lines.append("_All definitions have a matching local WGSL file._")
    else:
        lines.extend([
            "| id | def | expected wgsl | classification |",
            "|----|-----|---------------|----------------|",
        ])
        for r in non_local:
            lines.append(
                f"| `{r['id']}` | `{r['def_path']}` | `{r['expected_wgsl']}` | **{r['classification']}** |"
            )

    orphans = [r for r in report["wgsl_entries"] if r["classification"] == "orphan"]
    lines.extend(["", "## Orphan WGSL files", ""])
    if not orphans:
        lines.append("_No unexpected orphan WGSL files._")
    else:
        lines.append(f"_{len(orphans)} files need a shader_definitions JSON or ignore prefix._")
        lines.append("")
        for r in orphans[:50]:
            lines.append(f"- `{r['wgsl']}`")
        if len(orphans) > 50:
            lines.append(f"- … and {len(orphans) - 50} more")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def print_summary(
    report: dict,
    *,
    changed_failures: list[dict] | None = None,
    ci_gate_failures: list[str] | None = None,
) -> None:
    s = report["summary"]
    ws = report["wgsl_summary"]
    print("=" * 60)
    print("SHADER CATALOG HYGIENE AUDIT")
    print("=" * 60)
    print(f"Definitions scanned: {report['definitions_scanned']}")
    print(f"WGSL files scanned:  {report['wgsl_files_scanned']}")
    if report.get("changed_definitions_checked") is not None:
        print(f"Changed definitions (enforced): {report['changed_definitions_checked']}")
    print("\nDefinitions → WGSL:")
    for key, count in s.items():
        marker = " [FAIL]" if key in ("likely-broken", "parse-error") and count else ""
        print(f"  {key}: {count}{marker}")
    print("\nWGSL → definitions:")
    for key, count in ws.items():
        marker = " [FAIL]" if key == "orphan" and count else ""
        print(f"  {key}: {count}{marker}")
    print(f"\nonly_def={report['only_def_count']}  only_wgsl={report['only_wgsl_count']}")
    if ci_gate_failures:
        print("\n[FAIL] Definitions missing valid local WGSL (CI gate):")
        for msg in ci_gate_failures:
            print(f"  • {msg}")
        print(
            "    Grandfather pre-existing orphans in reports/orphan_baseline.json; "
            "fix new ones or add to ALLOWLIST_IDS in audit_orphan_shader_defs.py"
        )
    elif changed_failures:
        print("\n[FAIL] Changed definitions missing valid local WGSL:")
        for r in changed_failures:
            err = f" ({r['error']})" if r.get("error") else ""
            print(f"  • {r['id']} ({r['def_path']}) -> {r['expected_wgsl']}{err}")
            print(
                "    Allowlist intentional data-only defs via ALLOWLIST_IDS in "
                "scripts/audit_orphan_shader_defs.py"
            )
    elif report["only_def_count"]:
        print("\n[INFO] Definitions missing WGSL (full tree; not blocking without --base):")
        for r in report["entries"]:
            if r["classification"] in ("likely-broken", "parse-error"):
                print(f"  • {r['id']} ({r['def_path']}) -> {r['expected_wgsl']}")
    if report["only_wgsl_count"]:
        print("\n[INFO] Orphan WGSL (no catalog entry):")
        for r in report["wgsl_entries"]:
            if r["classification"] == "orphan":
                print(f"  • {r['wgsl']}")
    print("=" * 60)


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit shader_definitions ↔ WGSL catalog pairing.")
    parser.add_argument("--json", action="store_true", help="Print JSON report to stdout")
    parser.add_argument(
        "--ci-gate",
        action="store_true",
        help="CI: fail when any likely-broken/parse-error def is not in orphan_baseline.json",
    )
    parser.add_argument(
        "--base",
        default=None,
        help="Git ref for forward-only enforcement (e.g. origin/main). "
        "Fails only on changed shader_definitions JSON classified likely-broken or parse-error.",
    )
    parser.add_argument(
        "--fail-all",
        action="store_true",
        help="Legacy: exit 1 when any only_def or only_wgsl in the full tree",
    )
    parser.add_argument(
        "--no-fail",
        action="store_true",
        help="Always exit 0 (report only)",
    )
    args = parser.parse_args()

    report = audit_definitions()

    changed_paths: set[Path] | None = None
    changed_failures: list[dict] = []
    ci_gate_failures: list[str] = []
    if args.ci_gate:
        _ok, ci_gate_failures = evaluate_ci_gate(report)
        report["ci_gate_failures"] = len(ci_gate_failures)
    elif args.base:
        try:
            changed_paths = discover_changed_definition_paths(args.base)
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"ERROR: could not list changed definitions against '{args.base}': {e}", file=sys.stderr)
            return 2
        changed_failures = enforceable_failures(report["entries"], changed_paths)
        report["changed_definitions_checked"] = len(changed_paths)
        report["changed_definition_failures"] = len(changed_failures)

    REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
    REPORT_JSON.write_text(json.dumps(report, indent=2), encoding="utf-8")
    write_markdown(report, REPORT_MD)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_summary(
            report,
            changed_failures=changed_failures or None,
            ci_gate_failures=ci_gate_failures or None,
        )
        print(f"Wrote {REPORT_JSON.relative_to(PROJECT_ROOT)}")
        print(f"Wrote {REPORT_MD.relative_to(PROJECT_ROOT)}")

    if args.no_fail:
        return 0

    if args.ci_gate and ci_gate_failures:
        return 1

    if args.base and changed_failures:
        return 1

    if args.fail_all and (report["only_def_count"] > 0 or report["only_wgsl_count"] > 0):
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
