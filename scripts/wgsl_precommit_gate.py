#!/usr/bin/env python3
"""
Pre-commit gate for changed WGSL files.

Runs naga validation + bindgroup compatibility + workgroup-size convention
checks on ONLY the .wgsl files that changed against a base ref (or an explicit
file list). Skips known template files and vertex/fragment render shaders.

Workgroup convention: compute shaders must use @workgroup_size with 3 explicit
dimensions (e.g. 16, 16, 1). Two-arg forms are reported as [WARN] (non-blocking).

Usage:
    python scripts/wgsl_precommit_gate.py
    python scripts/wgsl_precommit_gate.py --base main
    python scripts/wgsl_precommit_gate.py --files foo.wgsl bar.wgsl
    python scripts/wgsl_precommit_gate.py --fix   # local only: literal (int,int)->(int,int,1)
    python scripts/wgsl_precommit_gate.py --json

For local pre-commit hook setup, see scripts/AUTHORING.md.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS_DIR))
from bindgroup_checker import (  # noqa: E402
    TEMPLATE_FILES,
    check_workgroup_size_convention,
    fix_literal_two_arg_workgroup_size,
    parse_shader,
)

PROJECT_ROOT = _SCRIPTS_DIR.parent
_naga_path = shutil.which("naga")
if _naga_path:
    NAGA_BIN = Path(_naga_path)
else:
    NAGA_BIN = Path.home() / ".cargo" / "bin" / "naga"
REPORT_PATH = PROJECT_ROOT / "reports" / "wgsl_precommit_report.json"

VERTEX_PATTERN = re.compile(r"@vertex", re.MULTILINE)
FRAGMENT_PATTERN = re.compile(r"@fragment", re.MULTILINE)
COMPUTE_PATTERN = re.compile(r"@compute", re.MULTILINE)


def naga_available() -> bool:
    return bool(shutil.which("naga")) or NAGA_BIN.exists()


def discover_changed_files(base_ref: str) -> list[Path]:
    """Return .wgsl files changed against base_ref."""
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMRT", base_ref],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    files = []
    for line in result.stdout.splitlines():
        p = PROJECT_ROOT / line.strip()
        if p.suffix == ".wgsl" and p.exists():
            files.append(p)
    return files


def run_naga(wgsl_path: Path) -> dict:
    """Run naga on a single file. Return {'ok': bool, 'error': str}."""
    result = subprocess.run(
        [str(NAGA_BIN), str(wgsl_path)],
        capture_output=True,
        text=True,
    )
    ok = result.returncode == 0
    error = ""
    if not ok:
        error = (result.stdout + result.stderr).strip() or "naga validation failed"
    return {"ok": ok, "error": error}


def should_skip(wgsl_path: Path, content: str) -> tuple[bool, str]:
    """Return (skip, reason) for files that are not compute shader candidates."""
    if wgsl_path.name in TEMPLATE_FILES:
        return True, "template file"
    if VERTEX_PATTERN.search(content) or FRAGMENT_PATTERN.search(content):
        return True, "render shader"
    if not COMPUTE_PATTERN.search(content):
        return True, "no @compute entry point"
    return False, ""


def apply_workgroup_fixes(paths: list[Path]) -> list[dict]:
    """Apply literal (int,int) workgroup auto-fix. Returns list of fix records."""
    fixes = []
    for path in paths:
        try:
            content = path.read_text(encoding="utf-8")
        except OSError as e:
            fixes.append({"file": str(path), "error": str(e), "replacements": 0})
            continue
        skip, _ = should_skip(path, content)
        if skip:
            continue
        new_content, n = fix_literal_two_arg_workgroup_size(content)
        if n > 0:
            path.write_text(new_content, encoding="utf-8")
            try:
                display = str(path.relative_to(PROJECT_ROOT))
            except ValueError:
                display = str(path)
            fixes.append({"file": display, "replacements": n})
    return fixes


def run_gate(paths: list[Path], *, skip_naga: bool = False) -> dict:
    """Run naga + bindgroup + workgroup checks on the given paths."""
    report = {
        "timestamp": datetime.now().isoformat(),
        "naga_bin": str(NAGA_BIN),
        "naga_available": naga_available() and not skip_naga,
        "total": len(paths),
        "passed": 0,
        "failed": 0,
        "skipped": 0,
        "warnings": 0,
        "results": [],
    }

    for path in sorted(paths):
        try:
            display_path = str(path.relative_to(PROJECT_ROOT))
        except ValueError:
            display_path = str(path)
        entry = {
            "file": display_path,
            "skipped": False,
            "skip_reason": None,
            "naga_ok": None,
            "naga_skipped": False,
            "naga_error": None,
            "bindgroup_status": None,
            "bindgroup_errors": [],
            "workgroup_warnings": [],
            "ok": False,
        }

        try:
            content = path.read_text(encoding="utf-8")
        except Exception as e:
            entry["ok"] = False
            entry["naga_error"] = f"could not read file: {e}"
            report["results"].append(entry)
            report["failed"] += 1
            continue

        skip, reason = should_skip(path, content)
        if skip:
            entry["skipped"] = True
            entry["skip_reason"] = reason
            entry["ok"] = True
            report["results"].append(entry)
            report["skipped"] += 1
            continue

        wg_issues = check_workgroup_size_convention(content)
        entry["workgroup_warnings"] = wg_issues
        if wg_issues:
            report["warnings"] += len(wg_issues)

        if skip_naga or not naga_available():
            entry["naga_skipped"] = True
            entry["naga_ok"] = None
            naga_ok = True
        else:
            naga_result = run_naga(path)
            entry["naga_ok"] = naga_result["ok"]
            entry["naga_error"] = naga_result["error"]
            naga_ok = naga_result["ok"]

        try:
            bg = parse_shader(path)
        except Exception as e:
            bg = {"status": "parse_error", "errors": [str(e)]}

        entry["bindgroup_status"] = bg.get("status", "unknown")
        entry["bindgroup_errors"] = bg.get("errors", [])

        if naga_ok and bg.get("status") == "compatible":
            entry["ok"] = True
            report["passed"] += 1
        else:
            entry["ok"] = False
            report["failed"] += 1

        report["results"].append(entry)

    return report


def print_report(report: dict) -> None:
    """Print a concise pass/fail summary."""
    total = report["total"]
    passed = report["passed"]
    failed = report["failed"]
    skipped = report["skipped"]
    warnings = report["warnings"]

    print("=" * 70)
    print("WGSL PRECOMMIT GATE")
    print("=" * 70)
    if not report.get("naga_available"):
        print("[WARN] naga unavailable — skipped naga validation (bindgroup + workgroup still run)")
    print(
        f"Files checked: {total}  |  Passed: {passed}  |  Failed: {failed}  |  "
        f"Skipped: {skipped}  |  Workgroup warnings: {warnings}"
    )

    for entry in report["results"]:
        file = entry["file"]
        if entry["skipped"]:
            print(f"  ⏭  {file} — skipped ({entry['skip_reason']})")
            continue

        for wg in entry.get("workgroup_warnings", []):
            print(
                f"  [WARN] {file} — @workgroup_size has {wg['arg_count']} arg(s) "
                f"(need 3): {wg['match']}"
            )

        if entry["ok"]:
            naga_note = "naga skipped" if entry.get("naga_skipped") else "naga OK"
            print(f"  ✅ {file} — {naga_note}, bindgroup compatible")
            continue

        details = []
        if entry.get("naga_ok") is False:
            details.append("naga failed")
        if entry["bindgroup_status"] != "compatible":
            details.append(f"bindgroup {entry['bindgroup_status']}")
        print(f"  ❌ {file} — {', '.join(details)}")
        if entry["naga_error"]:
            for line in entry["naga_error"].splitlines()[:8]:
                print(f"      {line}")
        for err in entry["bindgroup_errors"][:3]:
            print(f"      • {err}")

    print("=" * 70)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run naga + bindgroup + workgroup checks on changed WGSL files."
    )
    parser.add_argument(
        "--base",
        default="origin/main",
        help="Git ref to diff against (default: origin/main)",
    )
    parser.add_argument(
        "--files",
        nargs="+",
        default=None,
        help="Explicit list of .wgsl paths (relative or absolute)",
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="Local dev: auto-fix literal @workgroup_size(int, int) -> (int, int, 1)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print full JSON report to stdout",
    )
    args = parser.parse_args()

    if args.files:
        paths = []
        for f in args.files:
            p = Path(f)
            if not p.is_absolute():
                p = PROJECT_ROOT / p
            if not p.exists():
                print(f"ERROR: file not found: {f}", file=sys.stderr)
                return 2
            paths.append(p)
    else:
        try:
            paths = discover_changed_files(args.base)
        except subprocess.CalledProcessError as e:
            print(
                f"ERROR: could not list changed files against '{args.base}':\n{e.stderr}",
                file=sys.stderr,
            )
            return 2
        except FileNotFoundError:
            print(
                "ERROR: git is not available or repository is missing.",
                file=sys.stderr,
            )
            return 2

    if not paths:
        print("No changed .wgsl files to check.")
        return 0

    if args.fix:
        fixes = apply_workgroup_fixes(paths)
        for fix in fixes:
            if fix.get("replacements"):
                print(f"[FIX] {fix['file']}: {fix['replacements']} literal (int,int) workgroup fix(es)")

    skip_naga = not naga_available()
    if skip_naga:
        print(
            f"[WARN] naga not found at {NAGA_BIN} — skipping naga step "
            "(install with: cargo install naga-cli)",
            file=sys.stderr,
        )

    report = run_gate(paths, skip_naga=skip_naga)

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_report(report)

    return 1 if report["failed"] > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
