#!/usr/bin/env python3
"""
Undo shader-side mouse-Y flips that compensated for WebGPURenderer doing `1.0 - y`.

Run after renderer fix so zoom_config.z matches canvas UV (0=top, 1=bottom).
"""

from __future__ import annotations

import re
from pathlib import Path

SHADERS = Path(__file__).resolve().parent.parent / "public" / "shaders"

# Longest patterns first to avoid partial replacement.
REPLACEMENTS: list[tuple[str, str]] = [
    (r"\(\(1\.0 - u\.zoom_config\.z\) \* 2\.0 - 1\.0\)", "(u.zoom_config.z * 2.0 - 1.0)"),
    (r"\(\(1\.0 - u\.zoom_config\.z\) - 0\.5\)", "(u.zoom_config.z - 0.5)"),
    (r"\(1\.0 - u\.zoom_config\.z \* 2\.0\)", "(u.zoom_config.z * 2.0 - 1.0)"),
    (r"1\.0 - u\.zoom_config\.z \* 2\.0", "u.zoom_config.z * 2.0 - 1.0"),
    (r"vec2<f32>\(u\.zoom_config\.y, 1\.0 - u\.zoom_config\.z\)", "u.zoom_config.yz"),
    (r"vec2<f32>\(u\.zoom_config\.y - 0\.5, 0\.5 - u\.zoom_config\.z\)",
     "vec2<f32>(u.zoom_config.y - 0.5, u.zoom_config.z - 0.5)"),
    (r"vec2<f32>\(u\.zoom_config\.y, 0\.5 - u\.zoom_config\.z\)",
     "vec2<f32>(u.zoom_config.y, u.zoom_config.z - 0.5)"),
    (r"\(0\.5 - u\.zoom_config\.z / u\.config\.w\)", "(u.zoom_config.z / u.config.w - 0.5)"),
    (r"\(0\.5 - u\.zoom_config\.z\)", "(u.zoom_config.z - 0.5)"),
    (r"\(u\.zoom_config\.z \* 2\.0 - 1\.0\) \* -1\.0", "(u.zoom_config.z * 2.0 - 1.0)"),
    (r"-\(u\.zoom_config\.z \* 2\.0 - 1\.0\)", "(u.zoom_config.z * 2.0 - 1.0)"),
    (r"1\.0 - u\.zoom_config\.z", "u.zoom_config.z"),
]


def main() -> None:
    changed = 0
    for path in sorted(SHADERS.glob("*.wgsl")):
        text = path.read_text(encoding="utf-8")
        original = text
        for pattern, repl in REPLACEMENTS:
            text = re.sub(pattern, repl, text)
        if text != original:
            path.write_text(text, encoding="utf-8")
            changed += 1
            print(f"updated {path.name}")
    print(f"Done — {changed} file(s) patched.")


if __name__ == "__main__":
    main()
