#!/usr/bin/env python3
"""
Full-tree @workgroup_size audit for compute shaders.

Convention (D3): two-arg @workgroup_size(...) is a warning (engine 8×8 / 16×16
convention + parseWorkgroupSize fallback risk). Hard limits are correctness errors:
  - x*y*z <= 256 (maxComputeInvocationsPerWorkgroup)
  - x,y <= 256; z <= 64
  - dispatch axis ceil(max_canvas / wg_dim) <= 65535

Outputs:
  reports/workgroup_audit.json
  reports/workgroup_audit.md

Usage:
  python3 scripts/wgsl_workgroup_detector.py --report
  python3 scripts/wgsl_workgroup_detector.py --gate   # fail on limit violations
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_SCRIPTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS_DIR))

from bindgroup_checker import (  # noqa: E402
    check_workgroup_size_convention,
    strip_wgsl_comments,
    TEMPLATE_FILES,
)

PROJECT_ROOT = _SCRIPTS_DIR.parent
SHADERS_DIR = PROJECT_ROOT / "public" / "shaders"
REPORT_JSON = PROJECT_ROOT / "reports" / "workgroup_audit.json"
REPORT_MD = PROJECT_ROOT / "reports" / "workgroup_audit.md"

MAX_INVOCATIONS = 256
MAX_WG_X = 256
MAX_WG_Y = 256
MAX_WG_Z = 64
MAX_DISPATCH_AXIS = 65535
# Representative max canvas for dispatch limit checks (4K × scale headroom).
MAX_CANVAS_DIM = 8192

COMPUTE_PATTERN = re.compile(r"@compute", re.MULTILINE)
VERTEX_PATTERN = re.compile(r"@vertex", re.MULTILINE)
FRAGMENT_PATTERN = re.compile(r"@fragment", re.MULTILINE)

ENTRY_WG_PATTERN = re.compile(
    r"@compute\s+@workgroup_size\(\s*([^)]*)\)\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)
LITERAL_INT = re.compile(r"^-?\d+$")
WORKGROUP_ATTR = re.compile(r"@workgroup_size\s*\(([^)]*)\)", re.MULTILINE)


def _rel(path: Path) -> str:
    try:
        return str(path.relative_to(PROJECT_ROOT))
    except ValueError:
        return str(path)


def naga_available() -> bool:
    return shutil.which("naga") is not None


def parse_literal_workgroup_args(arg_str: str) -> tuple[int, int, int] | None:
    parts = [p.strip() for p in arg_str.split(",") if p.strip()]
    if not parts:
        return None
    if len(parts) == 2 and all(LITERAL_INT.match(p) for p in parts[:2]):
        return int(parts[0]), int(parts[1]), 1
    if len(parts) >= 3 and all(LITERAL_INT.match(p) for p in parts[:3]):
        return int(parts[0]), int(parts[1]), int(parts[2])
    return None


def resolve_workgroup_dims(content: str, entry_point: str = "main") -> tuple[tuple[int, int, int] | None, str]:
    """
    Resolve [x,y,z] for an entry point. Returns (dims, source) where source is
    'literal-main', 'literal-first', 'unresolved', or 'none'.
    """
    stripped = strip_wgsl_comments(content)
    first_match: tuple[int, int, int] | None = None
    for match in ENTRY_WG_PATTERN.finditer(stripped):
        dims = parse_literal_workgroup_args(match.group(1))
        if dims and first_match is None:
            first_match = dims
        if match.group(2) == entry_point and dims:
            return dims, "literal-main"
    if first_match:
        return first_match, "literal-first"
    # Any @workgroup_size with literals (non-entry-attached)
    for match in WORKGROUP_ATTR.finditer(stripped):
        dims = parse_literal_workgroup_args(match.group(1))
        if dims:
            return dims, "literal-fallback-scan"
    return None, "unresolved"


def parse_workgroup_size_dispatch_xy(content: str, entry_point: str = "main") -> tuple[int, int] | None:
    """Mirror ShaderCompilation.parseWorkgroupSize (x,y only)."""
    stripped = strip_wgsl_comments(content)
    entry_re = re.compile(
        r"@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)[^)]*\)\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)",
        re.MULTILINE,
    )
    first: tuple[int, int] | None = None
    for m in entry_re.finditer(stripped):
        xy = (int(m.group(1)), int(m.group(2)))
        if first is None:
            first = xy
        if m.group(3) == entry_point:
            return xy
    if first:
        return first
    compute_idx = stripped.find("@compute")
    if compute_idx != -1:
        m2 = re.search(
            r"@workgroup_size\(\s*(\d+)\s*,\s*(\d+)",
            stripped[compute_idx:],
        )
        if m2:
            return int(m2.group(1)), int(m2.group(2))
    return None


def check_dispatch_limits(x: int, y: int, z: int) -> list[str]:
    issues: list[str] = []
    product = x * y * z
    if product > MAX_INVOCATIONS:
        issues.append(f"invocation product {product} > {MAX_INVOCATIONS}")
    if x > MAX_WG_X:
        issues.append(f"workgroup x {x} > {MAX_WG_X}")
    if y > MAX_WG_Y:
        issues.append(f"workgroup y {y} > {MAX_WG_Y}")
    if z > MAX_WG_Z:
        issues.append(f"workgroup z {z} > {MAX_WG_Z}")
    dx = (MAX_CANVAS_DIM + x - 1) // x
    dy = (MAX_CANVAS_DIM + y - 1) // y
    if dx > MAX_DISPATCH_AXIS:
        issues.append(f"dispatch x {dx} > {MAX_DISPATCH_AXIS} at canvas {MAX_CANVAS_DIM}")
    if dy > MAX_DISPATCH_AXIS:
        issues.append(f"dispatch y {dy} > {MAX_DISPATCH_AXIS} at canvas {MAX_CANVAS_DIM}")
    return issues


def line_number_for_match(content: str, substring: str) -> int:
    idx = content.find(substring)
    if idx < 0:
        return 1
    return content[:idx].count("\n") + 1


def should_skip(path: Path, content: str) -> tuple[bool, str]:
    if path.name in TEMPLATE_FILES:
        return True, "template"
    if VERTEX_PATTERN.search(content) or FRAGMENT_PATTERN.search(content):
        return True, "render shader"
    if not COMPUTE_PATTERN.search(content):
        return True, "no @compute"
    return False, ""


def audit_file(path: Path) -> dict[str, Any]:
    try:
        content = path.read_text(encoding="utf-8")
    except OSError as e:
        return {
            "file": _rel(path),
            "skipped": True,
            "skip_reason": str(e),
            "convention_warnings": [],
            "dispatch_fallback": False,
            "limit_errors": [],
            "resolved_dims": None,
        }

    skip, reason = should_skip(path, content)
    if skip:
        return {
            "file": _rel(path),
            "skipped": True,
            "skip_reason": reason,
            "convention_warnings": [],
            "dispatch_fallback": False,
            "limit_errors": [],
            "resolved_dims": None,
        }

    stripped = strip_wgsl_comments(content)
    convention_issues = check_workgroup_size_convention(content)
    convention_warnings: list[dict[str, Any]] = []
    for issue in convention_issues:
        line = line_number_for_match(content, issue.get("match", "@workgroup_size"))
        kind = "two-arg-convention" if issue.get("arg_count") == 2 else "non-three-arg-convention"
        convention_warnings.append({
            "kind": kind,
            "line": line,
            "match": issue.get("match"),
            "arg_count": issue.get("arg_count"),
            "args": issue.get("args"),
        })

    dispatch_xy = parse_workgroup_size_dispatch_xy(content, "main")
    dispatch_fallback = dispatch_xy is None

    dims, dim_source = resolve_workgroup_dims(content, "main")
    limit_errors: list[dict[str, Any]] = []
    if dims:
        for msg in check_dispatch_limits(*dims):
            limit_errors.append({
                "line": line_number_for_match(content, "@workgroup_size"),
                "message": msg,
                "dims": list(dims),
                "source": dim_source,
            })
    elif dim_source == "unresolved" and convention_issues:
        # Non-literal workgroup — cannot verify limits without naga
        limit_errors.append({
            "line": line_number_for_match(content, "@workgroup_size"),
            "message": "non-literal @workgroup_size — limits not verified (naga recommended)",
            "dims": None,
            "source": "unresolved",
            "severity": "info",
        })

    return {
        "file": _rel(path),
        "skipped": False,
        "skip_reason": None,
        "convention_warnings": convention_warnings,
        "dispatch_fallback": dispatch_fallback,
        "limit_errors": [e for e in limit_errors if e.get("severity") != "info"],
        "limit_notes": [e for e in limit_errors if e.get("severity") == "info"],
        "resolved_dims": list(dims) if dims else None,
        "dim_source": dim_source,
    }


def audit_tree() -> dict[str, Any]:
    paths = sorted(SHADERS_DIR.glob("*.wgsl")) if SHADERS_DIR.exists() else []
    results: list[dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=16) as pool:
        futures = {pool.submit(audit_file, p): p for p in paths}
        for fut in as_completed(futures):
            results.append(fut.result())
    results.sort(key=lambda r: r["file"])

    convention_count = sum(len(r["convention_warnings"]) for r in results if not r["skipped"])
    fallback_count = sum(1 for r in results if not r["skipped"] and r["dispatch_fallback"])
    limit_error_count = sum(len(r["limit_errors"]) for r in results if not r["skipped"])

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "naga_available": naga_available(),
        "max_canvas_dim": MAX_CANVAS_DIM,
        "limits": {
            "max_invocations_per_workgroup": MAX_INVOCATIONS,
            "max_workgroup_x": MAX_WG_X,
            "max_workgroup_y": MAX_WG_Y,
            "max_workgroup_z": MAX_WG_Z,
            "max_dispatch_axis": MAX_DISPATCH_AXIS,
        },
        "guidance": (
            "Prefer explicit @workgroup_size(x, y, 1) with x*y*z <= 256. "
            "8×8=64 aligns with warp/wavefront width; 16×16=256 is the portable upper bound."
        ),
        "files_scanned": len(paths),
        "files_skipped": sum(1 for r in results if r["skipped"]),
        "convention_warning_count": convention_count,
        "dispatch_fallback_count": fallback_count,
        "limit_error_count": limit_error_count,
        "results": results,
    }


def write_markdown(report: dict, path: Path) -> None:
    lines = [
        "# Workgroup size audit",
        "",
        f"Generated: {report['timestamp']}",
        "",
        report.get("guidance", ""),
        "",
        f"- Files scanned: {report['files_scanned']}",
        f"- Convention warnings (2-arg / non-3-arg): {report['convention_warning_count']}",
        f"- Dispatch parse fallback risk (8×8 default): {report['dispatch_fallback_count']}",
        f"- Hard limit errors: **{report['limit_error_count']}**",
        "",
        "## Convention warnings (first 50)",
        "",
    ]
    shown = 0
    for row in report["results"]:
        if row["skipped"]:
            continue
        for w in row["convention_warnings"]:
            if shown >= 50:
                break
            lines.append(f"- `{row['file']}`:{w['line']} — `{w['match']}` ({w['kind']})")
            shown += 1
    if shown == 0:
        lines.append("_None._")

    lines.extend(["", "## Dispatch fallback sites (first 50)", ""])
    fb = [r for r in report["results"] if not r["skipped"] and r["dispatch_fallback"]]
    for r in fb[:50]:
        lines.append(f"- `{r['file']}` — parseWorkgroupSize would default to 8×8")
    if not fb:
        lines.append("_None._")

    lines.extend(["", "## Limit violations", ""])
    errs = []
    for r in report["results"]:
        for e in r.get("limit_errors") or []:
            errs.append((r["file"], e))
    if not errs:
        lines.append("_None._")
    else:
        for file, e in errs[:50]:
            lines.append(f"- `{file}`:{e.get('line')} — {e['message']} dims={e.get('dims')}")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit WGSL @workgroup_size conventions and limits.")
    parser.add_argument("--report", action="store_true", help="Write reports (default)")
    parser.add_argument("--gate", action="store_true", help="Exit 1 on hard limit violations")
    parser.add_argument("--json", action="store_true", help="Print JSON to stdout")
    args = parser.parse_args()

    report = audit_tree()
    REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
    REPORT_JSON.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    write_markdown(report, REPORT_MD)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(
            f"Workgroup audit: {report['convention_warning_count']} convention warnings, "
            f"{report['dispatch_fallback_count']} dispatch-fallback sites, "
            f"{report['limit_error_count']} limit errors"
        )
        print(f"Wrote {_rel(REPORT_JSON)}")

    if args.gate and report["limit_error_count"] > 0:
        print("GATE FAIL: workgroup hard limit violations present", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
