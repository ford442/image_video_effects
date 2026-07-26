#!/usr/bin/env python3
"""
extraBuffer index-map auditor — swarm guardrail against FFT-zone state writes.

Index map (agents/WGSL_BUILTINS_GENERATIVE.md, 2026-07-22):
  [0..4]    engine-reserved (CPU-written). Never write from WGSL.
  [5..132]  engine FFT bins (128 bins, bin 0 at [5]). Read-only for shaders;
            anything stored here is stomped every frame audio is active.
  [133..255] safe zone for persistent shader state.

This script FAILS (exit 1) on any WGSL *writing* extraBuffer[i] for i in
0..132, except violations recorded in the triage baseline
(reports/extrabuffer_write_audit_baseline.json) — legacy offenders cataloged
during the initial full-tree triage. Reads are always allowed (reading FFT
bins [5..132] is the documented audio-read pattern).

Resolved statically:
  - literal indices:            extraBuffer[133] = ...
  - const-declared names:       const CLICK_TIME: i32 = 1; extraBuffer[CLICK_TIME] = ...
  - const arithmetic:           extraBuffer[BASE + 2u] = ...

Unresolved dynamic indices (extraBuffer[idx * 4u + 3u], extraBuffer[slot])
are reported as DYNAMIC warnings (cannot prove safety statically) and do not
fail the audit unless --strict is given.

Usage:
  python3 scripts/audit_extrabuffer.py                 # full-tree, baseline-aware
  python3 scripts/audit_extrabuffer.py --files a.wgsl b.wgsl
  python3 scripts/audit_extrabuffer.py --write-baseline # re-triage (careful)
  python3 scripts/audit_extrabuffer.py --strict         # also fail on dynamic
  python3 scripts/audit_extrabuffer.py --json

Outputs: reports/extrabuffer_write_audit.json + .md
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SHADERS_DIR = PROJECT_ROOT / "public" / "shaders"
REPORT_JSON = PROJECT_ROOT / "reports" / "extrabuffer_write_audit.json"
REPORT_MD = PROJECT_ROOT / "reports" / "extrabuffer_write_audit.md"
BASELINE_JSON = PROJECT_ROOT / "reports" / "extrabuffer_write_audit_baseline.json"

RESERVED_MAX = 4        # [0..4] reserved
FFT_MIN, FFT_MAX = 5, 132   # engine FFT bins
SAFE_MIN, SAFE_MAX = 133, 255

WGSL_IGNORE_PREFIXES = ("_",)

_CONST_RE = re.compile(
    r"\bconst\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[iu]32)?\s*=\s*(-?\d+)u?\s*;"
)
_WRITE_RE = re.compile(
    r"extraBuffer\s*\[([^\[\]]+)\]\s*(=|\+=|-=|\*=|/=|%=)(?![=])"
)
_EXPR_SAFE_RE = re.compile(r"^[0-9A-Za-z_+\-*/%() \t]+$")


def strip_comments(src: str) -> str:
    """Remove // line comments and /* */ block comments (line count preserved)."""
    def _blank(m: re.Match) -> str:
        return "\n" * m.group(0).count("\n")

    src = re.sub(r"/\*.*?\*/", _blank, src, flags=re.DOTALL)
    src = re.sub(r"//[^\n]*", "", src)
    return src


def parse_consts(src: str) -> dict[str, int]:
    return {name: int(val) for name, val in _CONST_RE.findall(src)}


def resolve_expr(expr: str, consts: dict[str, int]) -> int | None:
    """Resolve a constant index expression to an int, or None if dynamic."""
    expr = expr.strip()
    if not _EXPR_SAFE_RE.match(expr):
        return None
    # strip u32 literal suffixes (3u -> 3)
    expr = re.sub(r"(\d)u\b", r"\1", expr)
    # substitute known const names (longest first, word boundaries)
    for name in sorted(consts, key=len, reverse=True):
        expr = re.sub(rf"\b{re.escape(name)}\b", str(consts[name]), expr)
    if re.search(r"[A-Za-z_]", expr):
        return None  # still has identifiers -> dynamic
    if not re.match(r"^[0-9+\-*/%() \t]+$", expr):
        return None
    try:
        return int(eval(expr, {"__builtins__": {}}, {}))  # noqa: S307 - sanitized above
    except Exception:
        return None


def classify_index(i: int) -> str:
    if 0 <= i <= RESERVED_MAX:
        return "reserved"
    if FFT_MIN <= i <= FFT_MAX:
        return "fft-zone"
    if SAFE_MIN <= i <= SAFE_MAX:
        return "safe"
    return "out-of-range"


def scan_shader(path: Path) -> dict:
    """Scan one WGSL file. Returns findings dict."""
    src = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
    consts = parse_consts(src)
    lines = src.split("\n")

    violations: list[dict] = []   # writes into [0..132]
    safe_writes: list[dict] = []
    dynamic: list[dict] = []
    out_of_range: list[dict] = []

    for lineno, line in enumerate(lines, start=1):
        for m in _WRITE_RE.finditer(line):
            expr, op = m.group(1), m.group(2)
            idx = resolve_expr(expr, consts)
            entry = {"line": lineno, "expr": expr.strip(), "op": op}
            if idx is None:
                entry["index"] = None
                dynamic.append(entry)
                continue
            entry["index"] = idx
            cls = classify_index(idx)
            entry["class"] = cls
            if cls in ("reserved", "fft-zone"):
                violations.append(entry)
            elif cls == "out-of-range":
                out_of_range.append(entry)
            else:
                safe_writes.append(entry)

    try:
        rel = str(path.relative_to(PROJECT_ROOT))
    except ValueError:
        rel = str(path)
    return {
        "file": rel,
        "violations": violations,
        "dynamic": dynamic,
        "out_of_range": out_of_range,
        "safe_write_count": len(safe_writes),
    }


def load_baseline() -> dict[str, list[int]]:
    """Baseline: {relpath: [indices]} of triaged legacy violations."""
    if not BASELINE_JSON.exists():
        return {}
    data = json.loads(BASELINE_JSON.read_text())
    return {e["file"]: list(e["indices"]) for e in data.get("entries", [])}


def write_baseline(results: list[dict]) -> None:
    entries = []
    for r in results:
        if not r["violations"]:
            continue
        indices = sorted({v["index"] for v in r["violations"]})
        entries.append({"file": r["file"], "indices": indices})
    payload = {
        "generated": datetime.now(timezone.utc).isoformat(),
        "reason": "Triaged legacy extraBuffer[0..132] writes present at audit "
        "introduction (2026-07-26). Do NOT add new entries; fix the shader "
        "or remap state to extraBuffer[133..255] instead.",
        "entries": sorted(entries, key=lambda e: e["file"]),
    }
    BASELINE_JSON.write_text(json.dumps(payload, indent=2) + "\n")


def run_audit(files: list[Path]) -> list[dict]:
    return [scan_shader(p) for p in sorted(files)]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--files", nargs="*", default=None,
                    help="WGSL files to scan (default: all public/shaders/*.wgsl)")
    ap.add_argument("--write-baseline", action="store_true",
                    help="Rewrite the triage baseline from current violations")
    ap.add_argument("--strict", action="store_true",
                    help="Also fail on unresolved dynamic-index writes")
    ap.add_argument("--json", action="store_true", help="Print JSON report to stdout")
    args = ap.parse_args()

    if args.files:
        files = [Path(f) if Path(f).is_absolute() else PROJECT_ROOT / f for f in args.files]
        files = [f for f in files if f.exists()]
    else:
        files = [p for p in SHADERS_DIR.glob("*.wgsl")
                 if not p.name.startswith(WGSL_IGNORE_PREFIXES)]

    results = run_audit(files)

    if args.write_baseline:
        write_baseline(results)
        print(f"baseline written: {BASELINE_JSON} "
              f"({sum(1 for r in results if r['violations'])} files with violations)")
        return 0

    baseline = load_baseline()
    new_violations: list[dict] = []
    known_violations: list[dict] = []
    dynamic_total = 0
    oor_total = 0

    for r in results:
        known_idx = set(baseline.get(r["file"], []))
        for v in r["violations"]:
            rec = {"file": r["file"], **v}
            if v["index"] in known_idx:
                known_violations.append(rec)
            else:
                new_violations.append(rec)
        dynamic_total += len(r["dynamic"])
        oor_total += len(r["out_of_range"])

    report = {
        "generated": datetime.now(timezone.utc).isoformat(),
        "files_scanned": len(results),
        "new_violations": new_violations,
        "known_violations": known_violations,
        "dynamic_writes": dynamic_total,
        "out_of_range_writes": oor_total,
        "baseline": str(BASELINE_JSON.relative_to(PROJECT_ROOT)),
    }

    REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
    REPORT_JSON.write_text(json.dumps(report, indent=2) + "\n")

    md = [
        "# extraBuffer Write Audit",
        "",
        f"- Files scanned: {len(results)}",
        f"- **New violations (writes to [0..132]): {len(new_violations)}**",
        f"- Known (triaged baseline) violations: {len(known_violations)}",
        f"- Dynamic-index writes (unresolved, review): {dynamic_total}",
        f"- Out-of-range writes (>255): {oor_total}",
        "",
    ]
    if new_violations:
        md.append("## New violations\n")
        for v in new_violations:
            md.append(f"- `{v['file']}:{v['line']}` — `extraBuffer[{v['expr']}] {v['op']}` "
                      f"→ index {v['index']} ({v['class']})")
        md.append("")
    REPORT_MD.write_text("\n".join(md) + "\n")

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("\n".join(md[:9]))

    fail = bool(new_violations) or (args.strict and dynamic_total > 0)
    if fail:
        print("AUDIT FAIL: new extraBuffer[0..132] writes detected "
              "(remap persistent state to [133..255])", file=sys.stderr)
        return 1
    print("AUDIT PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
