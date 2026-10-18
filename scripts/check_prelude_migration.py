#!/usr/bin/env python3
"""
check_prelude_migration.py — the prelude migration only moves one way.

Catalog shaders get their 13 bindings and `struct Uniforms` from
`#include "_prelude.wgsl"`. The ones that still paste them are listed in
src/contracts/prelude_migration.json `pending`, each with a reason. This gate
keeps that list honest in both directions and lets it only shrink:

  R1  a shader not in `pending` pastes header declarations     → run the fix command
  R2  a pending shader no longer pastes them                   → remove it from pending
  R3  a pending id has no file                                 → remove it from pending
  R4  a shader includes _prelude.wgsl and also pastes some     → delete the pasted copy
  R5  (--base) `pending` gained an id                          → migrate instead of listing
  R6  a pending reason is unknown or not what the classifier says
  R7  (--base) a changed file is pending as `eligible`         → migrate it in the same change
      (blocked reasons only warn: those need a reviewed fix, not the codemod)
  R8  a prompt source still shows binding declarations to paste

Usage:
  python3 scripts/check_prelude_migration.py                    # whole tree
  python3 scripts/check_prelude_migration.py --base origin/main # + R5 / R7 against a base

Stdlib only (the wgsl-precommit-gate CI job has no `npm ci`).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import prelude_header as ph  # noqa: E402

PROJECT_ROOT = ph.PROJECT_ROOT
TRACKER_REL = "src/contracts/prelude_migration.json"
DEFAULT_FIX = "python3 scripts/migrate_to_prelude.py --files {path}"
PASTE_LINE_RE = re.compile(r"^\s*@group\(\s*0\s*\)\s*@binding\(\s*([0-9]|1[0-2])\s*\)\s*var")


def load_tracker(root: Path = PROJECT_ROOT) -> dict | None:
    path = root / TRACKER_REL
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def _rel(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def file_violations(
    path: Path,
    source: str,
    tracker: dict,
    ref: dict,
    *,
    changed: bool,
    root: Path = PROJECT_ROOT,
    cls: ph.Classification | None = None,
) -> list[dict]:
    """
    R1 / R4 / R7 for one catalog shader. Shared with wgsl_precommit_gate.py so
    both gates say the same thing. Returns [{rule, severity, message, fix}].
    """
    sid, rel = path.stem, _rel(path, root)
    pending = tracker.get("pending", {})
    fix = tracker.get("fixCommand", DEFAULT_FIX).format(path=rel)
    cls = cls or ph.classify(source, ref)
    out = []
    if cls.status == "mixed":
        out.append({
            "rule": "R4",
            "severity": "error",
            "message": f"{rel} includes {ph.PRELUDE_NAME} and also {cls.detail.split(' and also ', 1)[-1]} — delete the pasted copy",
            "fix": None,
        })
    elif sid not in pending and cls.status in ("migratable", "refused"):
        message = f"{rel} pastes the binding header — shaders get it from {ph.PRELUDE_NAME}"
        if cls.status == "refused":
            message += (
                f". Its copy also differs from the prelude ({cls.reason}: {cls.detail}); "
                "restore the canonical declarations first — a deviation here is a bug"
            )
        out.append({"rule": "R1", "severity": "error", "message": message, "fix": fix})
    elif changed and sid in pending:
        if pending[sid] == "eligible" and cls.status == "migratable":
            out.append({
                "rule": "R7",
                "severity": "error",
                "message": f"{rel} is edited in this change but still pastes the binding header — migrate it in the same change",
                "fix": fix,
            })
        elif pending[sid] != "eligible":
            out.append({
                "rule": "R7",
                "severity": "warning",
                "message": f"{rel} is edited but still pastes a non-canonical header ({pending[sid]}); see the tracker reason",
                "fix": None,
            })
    return out


def changed_files(base: str, root: Path) -> set[str]:
    """Files added/modified against `base` (merge-base diff) plus uncommitted ones."""
    out: set[str] = set()
    for cmd in (
        ["git", "diff", "--name-only", "--diff-filter=AMR", f"{base}...HEAD"],
        ["git", "diff", "--name-only", "--diff-filter=AMR", "HEAD"],
    ):
        proc = subprocess.run(cmd, cwd=root, capture_output=True, text=True)
        if proc.returncode != 0:
            raise SystemExit(f"❌ could not diff against {base}: {proc.stderr.strip()}")
        out.update(line.strip() for line in proc.stdout.splitlines() if line.strip())
    return out


def base_pending(base: str, root: Path) -> dict | None:
    proc = subprocess.run(["git", "show", f"{base}:{TRACKER_REL}"], cwd=root, capture_output=True, text=True)
    if proc.returncode != 0:
        return None  # the tracker is new in this change
    return json.loads(proc.stdout).get("pending", {})


def check(root: Path = PROJECT_ROOT, base: str | None = None) -> tuple[list[dict], list[dict], dict]:
    tracker = load_tracker(root)
    if tracker is None:
        return [{"rule": "R0", "severity": "error", "message": f"{TRACKER_REL} is missing", "fix": None}], [], {}
    shaders_dir = root / "public" / "shaders"
    ref = ph.prelude_reference((shaders_dir / ph.PRELUDE_NAME).read_text(encoding="utf-8"))
    pending: dict[str, str] = tracker.get("pending", {})
    reasons: dict[str, str] = tracker.get("reasons", {})
    changed = changed_files(base, root) if base else set()

    errors: list[dict] = []
    warnings: list[dict] = []

    def add(v: dict) -> None:
        (errors if v["severity"] == "error" else warnings).append(v)

    files = {p.stem: p for p in sorted(shaders_dir.glob("*.wgsl")) if not p.name.startswith("_")}
    classes: dict[str, ph.Classification] = {}
    for sid, path in files.items():
        source = path.read_text(encoding="utf-8")
        cls = classes[sid] = ph.classify(source, ref)
        for v in file_violations(path, source, tracker, ref, changed=_rel(path, root) in changed, root=root, cls=cls):
            add(v)

    for sid, reason in pending.items():
        if sid not in files:
            add({"rule": "R3", "severity": "error", "message": f"pending id `{sid}` has no public/shaders/{sid}.wgsl — remove it from {TRACKER_REL}", "fix": None})
            continue
        cls = classes[sid]
        if cls.status not in ("migratable", "refused", "mixed"):
            add({"rule": "R2", "severity": "error", "message": f"`{sid}` no longer pastes the header — remove it from {TRACKER_REL} pending", "fix": None})
            continue
        if reason not in reasons:
            add({"rule": "R6", "severity": "error", "message": f"`{sid}` has unknown reason `{reason}` (known: {', '.join(sorted(reasons))})", "fix": None})
            continue
        expected = "eligible" if cls.status == "migratable" else cls.reason
        if cls.status != "mixed" and reason != expected:
            add({"rule": "R6", "severity": "error", "message": f"`{sid}` is pending as `{reason}` but the classifier says `{expected}`" + (f" ({cls.detail})" if cls.detail else ""), "fix": None})

    if base:
        before = base_pending(base, root)
        if before is not None:
            added = sorted(set(pending) - set(before))
            if added:
                add({"rule": "R5", "severity": "error", "message": f"pending may only shrink; added: {', '.join(added)} — migrate them instead", "fix": None})

    for rel in tracker.get("promptSources", []):
        path = root / rel
        if not path.exists():
            add({"rule": "R8", "severity": "error", "message": f"prompt source {rel} is missing — update promptSources", "fix": None})
            continue
        for lineno, line in enumerate(path.read_text(encoding="utf-8").split("\n"), start=1):
            if PASTE_LINE_RE.match(line):
                add({
                    "rule": "R8",
                    "severity": "error",
                    "message": f"{rel}:{lineno} shows a binding declaration to paste — tell agents to `#include \"{ph.PRELUDE_NAME}\"` instead",
                    "fix": None,
                })
                break

    summary = {
        "pending": len(pending),
        "byReason": dict(Counter(pending.values())),
        "includers": sum(1 for c in classes.values() if c.status == "already-includes"),
    }
    return errors, warnings, summary


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", help="git ref to diff against (enables R5 and R7)")
    parser.add_argument("--root", type=Path, default=PROJECT_ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    errors, warnings, summary = check(args.root.resolve(), args.base)
    for v in warnings:
        print(f"⚠️  {v['rule']} {v['message']}")
    for v in errors:
        print(f"❌ {v['rule']} {v['message']}", file=sys.stderr)
        if v.get("fix"):
            print(f"   Fix: {v['fix']}", file=sys.stderr)
    if summary:
        reasons = ", ".join(f"{k} {n}" for k, n in sorted(summary["byReason"].items()))
        print(f"prelude migration: {summary['includers']} shaders include {ph.PRELUDE_NAME}, {summary['pending']} still paste it ({reasons})")
    if errors:
        print(f"❌ prelude migration check failed ({len(errors)} error(s))", file=sys.stderr)
        return 1
    print("✅ prelude migration tracker consistent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
