#!/usr/bin/env python3
"""Finalize updatedParams for all generative defs missing them (gate + audit first)."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "temp"))

from audit_dead_sliders import scan_definition, wgsl_path_for  # noqa: E402
from audit_extrabuffer import load_baseline, scan_shader  # noqa: E402
from make_briefs_common import POOL_EXCLUDE, extract_params  # noqa: E402

DEF_DIR = ROOT / "shader_definitions" / "generative"
SHADERS_DIR = ROOT / "public" / "shaders"


def needs_update(meta: dict) -> bool:
    params = extract_params(meta)
    up = meta.get("updatedParams")
    if not params:
        return up is None or not isinstance(up, list) or len(up) < 4
    need = min(4, len(params))
    return up is None or not isinstance(up, list) or len(up) < need


def pool_ids() -> list[str]:
    out = []
    for p in sorted(DEF_DIR.glob("*.json")):
        if p.stem in POOL_EXCLUDE:
            continue
        meta = json.loads(p.read_text(encoding="utf-8"))
        if needs_update(meta):
            out.append(p.stem)
    return out


def gate_ok(wgsl: Path) -> bool:
    r = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "wgsl_precommit_gate.py"),
         "--files", str(wgsl)],
        capture_output=True,
        text=True,
    )
    return r.returncode == 0


def extrabuffer_ok(wgsl: Path, baseline: dict) -> bool:
    scan = scan_shader(wgsl)
    known = set(baseline.get(scan["file"], []))
    return all(v["index"] in known for v in scan["violations"])


def finalize(def_path: Path) -> None:
    meta = json.loads(def_path.read_text(encoding="utf-8"))
    params = extract_params(meta)
    meta["updatedParams"] = [
        {
            "index": i,
            "name": p["name"],
            "default": p["default"],
            "min": p["min"],
            "max": p["max"],
            "step": p["step"],
        }
        for i, p in enumerate(params[:4])
    ]
    meta["updated"] = True
    def_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    baseline = load_baseline()
    ok, skip, fail = [], [], []

    for sid in pool_ids():
        def_path = DEF_DIR / f"{sid}.json"
        meta = json.loads(def_path.read_text(encoding="utf-8"))
        wgsl = wgsl_path_for(def_path, meta)
        if wgsl is None:
            skip.append((sid, "missing wgsl"))
            continue

        if not gate_ok(wgsl):
            fail.append((sid, "gate"))
            continue
        if not extrabuffer_ok(wgsl, baseline):
            fail.append((sid, "extrabuffer"))
            continue

        dead = scan_definition(def_path)
        if dead and dead.get("dead"):
            fail.append((sid, f"dead sliders: {[p['id'] for p in dead['dead']]}"))
            continue

        finalize(def_path)
        ok.append(sid)

    print(f"Finalized: {len(ok)}")
    for s in ok:
        print(f"  OK {s}")
    if skip:
        print(f"Skipped: {len(skip)}")
        for s, why in skip:
            print(f"  SKIP {s}: {why}")
    if fail:
        print(f"Failed: {len(fail)}")
        for s, why in fail:
            print(f"  FAIL {s}: {why}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
