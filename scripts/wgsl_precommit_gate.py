#!/usr/bin/env python3
"""
Pre-commit gate for changed WGSL files.

Runs naga validation + the bindgroup compatibility check on ONLY the .wgsl
files that changed against a base ref (or an explicit file list). Skips known
template files and vertex/fragment render shaders. Exits non-zero if any
changed compute shader fails.

Usage:
    # Against origin/main (default)
    python scripts/wgsl_precommit_gate.py

    # Against a specific base ref
    python scripts/wgsl_precommit_gate.py --base main

    # Explicit files
    python scripts/wgsl_precommit_gate.py --files foo.wgsl bar.wgsl

    # Report JSON (also written to reports/wgsl_precommit_report.json)
    python scripts/wgsl_precommit_gate.py --json

For local pre-commit hook setup, see scripts/AUTHORING.md.
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SCRIPTS_DIR))
from bindgroup_checker import parse_shader, TEMPLATE_FILES  # noqa: E402


PROJECT_ROOT = _SCRIPTS_DIR.parent
NAGA_BIN = Path("/root/.cargo/bin/naga")
REPORT_PATH = PROJECT_ROOT / "reports" / "wgsl_precommit_report.json"

# Patterns that identify non-compute shaders the gate should ignore.
VERTEX_PATTERN = re.compile(r"@vertex", re.MULTILINE)
FRAGMENT_PATTERN = re.compile(r"@fragment", re.MULTILINE)
COMPUTE_PATTERN = re.compile(r"@compute", re.MULTILINE)


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


def run_gate(paths: list[Path]) -> dict:
    """Run naga + bindgroup checks on the given paths."""
    report = {
        "timestamp": datetime.now().isoformat(),
        "naga_bin": str(NAGA_BIN),
        "total": len(paths),
        "passed": 0,
        "failed": 0,
        "skipped": 0,
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
            "naga_error": None,
            "bindgroup_status": None,
            "bindgroup_errors": [],
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

        naga_result = run_naga(path)
        entry["naga_ok"] = naga_result["ok"]
        entry["naga_error"] = naga_result["error"]

        try:
            bg = parse_shader(path)
        except Exception as e:
            bg = {"status": "parse_error", "errors": [str(e)]}

        entry["bindgroup_status"] = bg.get("status", "unknown")
        entry["bindgroup_errors"] = bg.get("errors", [])

        if naga_result["ok"] and bg.get("status") == "compatible":
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

    print("=" * 70)
    print("WGSL PRECOMMIT GATE")
    print("=" * 70)
    print(f"Files checked: {total}  |  Passed: {passed}  |  Failed: {failed}  |  Skipped: {skipped}")

    for entry in report["results"]:
        file = entry["file"]
        if entry["skipped"]:
            print(f"  ⏭  {file} — skipped ({entry['skip_reason']})")
            continue
        if entry["ok"]:
            print(f"  ✅ {file} — naga OK, bindgroup compatible")
            continue

        details = []
        if not entry["naga_ok"]:
            details.append("naga failed")
        if entry["bindgroup_status"] != "compatible":
            details.append(f"bindgroup {entry['bindgroup_status']}")
        print(f"  ❌ {file} — {', '.join(details)}")
        if entry["naga_error"]:
            # Indent naga output for readability
            for line in entry["naga_error"].splitlines()[:8]:
                print(f"      {line}")
        for err in entry["bindgroup_errors"][:3]:
            print(f"      • {err}")

    print("=" * 70)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run naga + bindgroup checks on changed WGSL files."
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

    if not NAGA_BIN.exists():
        print(
            f"ERROR: naga not found at {NAGA_BIN}. Install with: cargo install naga-cli",
            file=sys.stderr,
        )
        return 2

    report = run_gate(paths)

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
