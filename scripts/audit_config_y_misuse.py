#!/usr/bin/env python3
"""Audit public/shaders for `u.config.y` read as something other than rippleCount.

`config = [time, rippleCount, resW, resH]` (src/contracts/uniforms_layout.json).
Stale agent briefs claimed `config.y` was delta_time / MouseClickCount / audio, so a
number of shaders read it as such. Those reads are not crashes — they silently produce
a value in 0..50 that is almost always 0 — hence "looks fine" shaders with dead audio
or frozen motion.

Report only (non-blocking). Use it to triage follow-up fix PRs.

    python3 scripts/audit_config_y_misuse.py [--json reports/config_y_misuse.json]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHADER_DIR = ROOT / "public" / "shaders"

CONFIG_Y = re.compile(r"u\.config\.y(?![a-z])")
# Reads of config.yz / config.yzw / config.xy — legacy "audio" and "resolution" swizzles.
CONFIG_SWIZZLE = re.compile(r"u\.config\.(yz|yzw|zyx|xy)\b")

CATEGORIES = [
    ("delta_time", re.compile(r"\b(dt|delta_?t(ime)?|deltaTime|timestep|time_step)\b", re.I)),
    ("audio", re.compile(r"\b(audio|bass|mid|mids|treble|beat|fft|amp|amplitude|volume)\w*\b", re.I)),
    ("click_or_frame_count", re.compile(r"\b(click|frame_?count|frame|parity|seed)\w*\b", re.I)),
    ("resolution", re.compile(r"\b(resolution|res|aspect|dims?)\b", re.I)),
]

# Reads that are consistent with rippleCount semantics.
RIPPLE_OK = re.compile(r"ripple|min\(\s*u32\(|u32\(\s*u\.config\.y", re.I)


def classify(line: str) -> str | None:
    if RIPPLE_OK.search(line):
        return None
    for name, pattern in CATEGORIES:
        if pattern.search(line):
            return name
    return "unclassified"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default="reports/config_y_misuse.json")
    ap.add_argument("--markdown", default="reports/config_y_misuse.md")
    args = ap.parse_args()

    findings: list[dict] = []
    for path in sorted(SHADER_DIR.glob("*.wgsl")):
        for i, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue  # comments (including "was u.config.y" fix notes) are not reads
            if not (CONFIG_Y.search(line) or CONFIG_SWIZZLE.search(line)):
                continue
            category = classify(line)
            if category is None:
                continue
            findings.append(
                {
                    "file": str(path.relative_to(ROOT)),
                    "line": i,
                    "category": category,
                    "code": stripped[:200],
                }
            )

    by_category: dict[str, int] = {}
    for f in findings:
        by_category[f["category"]] = by_category.get(f["category"], 0) + 1

    out_json = ROOT / args.json
    out_md = ROOT / args.markdown
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps({"total": len(findings), "byCategory": by_category, "findings": findings}, indent=2))

    lines = [
        "# `u.config.y` misuse audit",
        "",
        "`config = [time, rippleCount, resW, resH]` — see `src/contracts/uniforms_layout.json`.",
        "Every row below reads `config.y` (or a legacy `config` swizzle) as something else.",
        "",
        f"**Total: {len(findings)} reads across {len({f['file'] for f in findings})} shaders**",
        "",
        "| Category | Count |",
        "|----------|-------|",
    ]
    for cat, count in sorted(by_category.items(), key=lambda kv: -kv[1]):
        lines.append(f"| `{cat}` | {count} |")
    lines += ["", "## Findings", "", "| File | Line | Category | Code |", "|------|------|----------|------|"]
    for f in findings:
        code = f["code"].replace("|", "\\|")
        lines.append(f"| `{f['file']}` | {f['line']} | {f['category']} | `{code}` |")
    out_md.write_text("\n".join(lines) + "\n")

    print(f"config.y misuse audit: {len(findings)} reads in {len({f['file'] for f in findings})} shaders")
    for cat, count in sorted(by_category.items(), key=lambda kv: -kv[1]):
        print(f"  {cat}: {count}")
    print(f"Reports: {args.markdown}, {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
