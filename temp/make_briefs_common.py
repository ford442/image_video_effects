"""Shared helpers for generative swarm brief generators."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GENERATIVE_DIR = ROOT / "shader_definitions" / "generative"
SHADERS_DIR = ROOT / "public" / "shaders"

EXTRABUFFER_SAFE_ZONE = "[133..255]"
EXTRABUFFER_FFT_WARNING = (
    "[0..4] reserved, [5..132] = engine FFT bins — persistent shader state goes in "
    f"{EXTRABUFFER_SAFE_ZONE} ONLY"
)

REQUIRED_OUTPUT = f"""## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): {EXTRABUFFER_FFT_WARNING}.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.
"""

MANDATORY_BULLETS = [
    "Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.",
    "Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.",
    "Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.",
]

MANDATORY_BULLETS_2PARAM = [
    "Wire the 2 existing slider params via u.zoom_params.x/y using the EXISTING JSON controls (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-1. These param ids/defaults are the saved-preset contract: do not rename or re-default them, and do NOT invent params for z/w.",
    "Make each slider drive meaningful shader-specific constants in the WGSL.",
    "Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.",
]

POOL_EXCLUDE = frozenset({"gen_capabilities", "gen_grid"})
FIELDS = ("x", "y", "z", "w")


def extract_params(meta: dict) -> list[dict]:
    """Return list of {name, default, min, max, step} from any known schema."""
    if isinstance(meta.get("params"), list) and meta["params"]:
        return [
            {
                "name": p["name"],
                "default": p["default"],
                "min": float(p.get("min", 0.0)),
                "max": float(p.get("max", 1.0)),
                "step": p.get("step", 0.01),
            }
            for p in meta["params"][:4]
        ]
    if isinstance(meta.get("parameters"), list) and meta["parameters"]:
        out = []
        for i, p in enumerate(meta["parameters"][:4]):
            if "uniform" in p:
                field = p["uniform"].rsplit(".", 1)[-1]
            elif str(p.get("name", "")).startswith("zoom_params."):
                field = str(p["name"]).rsplit(".", 1)[-1]
            else:
                field = FIELDS[i]
            label = p.get("label") or p.get("name", f"param{i+1}")
            if field in FIELDS:
                out.append({
                    "name": label,
                    "default": p["default"],
                    "min": float(p.get("min", 0.0)),
                    "max": float(p.get("max", 1.0)),
                    "step": p.get("step", 0.01),
                })
        if out:
            return out
    if isinstance(meta.get("uniforms"), list) and meta["uniforms"]:
        return [
            {
                "name": p["name"],
                "default": p["default"],
                "min": float(p.get("min", 0.0)),
                "max": float(p.get("max", 1.0)),
                "step": p.get("step", 0.01),
            }
            for p in meta["uniforms"][:4]
        ]
    controls = [c for c in meta.get("controls", []) if c.get("type") in ("slider", "range")]

    def field_of(c: dict) -> str:
        if "uniform" in c:
            return c["uniform"]
        return f"zoom_params.{c['uniformMapping']['field']}"

    controls.sort(key=field_of)
    return [
        {
            "name": c["name"],
            "default": c["default"],
            "min": float(c.get("min", 0.0)),
            "max": float(c.get("max", 1.0)),
            "step": c.get("step", 0.01),
        }
        for c in controls[:4]
    ]


def wgsl_line_count(wgsl_path: Path) -> int:
    return int(subprocess.check_output(["wc", "-l", str(wgsl_path)]).split()[0])


def scan_empty_updated_params_pool(
    *,
    exclude: frozenset[str] | None = None,
    tracker_path: Path | None = None,
) -> list[dict]:
    """
    Return generative defs missing/empty/partial updatedParams, smallest WGSL first.

    Each entry: {id, wgsl_lines, kind} where kind is missing|empty|partial:N
    """
    exclude = exclude or POOL_EXCLUDE
    tracker_text = ""
    if tracker_path and tracker_path.exists():
        tracker_text = tracker_path.read_text(encoding="utf-8")

    pool: list[dict] = []
    for p in sorted(GENERATIVE_DIR.glob("*.json")):
        if p.stem in exclude:
            continue
        meta = json.loads(p.read_text(encoding="utf-8"))
        up = meta.get("updatedParams")
        if isinstance(up, list) and len(up) >= 4:
            continue
        if up is None:
            kind = "missing"
        elif len(up) == 0:
            kind = "empty"
        else:
            kind = f"partial:{len(up)}"
        wgsl = SHADERS_DIR / f"{p.stem}.wgsl"
        if not wgsl.exists():
            url = meta.get("url", "")
            name = url.rsplit("/", 1)[-1] if url else f"{p.stem}.wgsl"
            wgsl = SHADERS_DIR / name
        lines = wgsl_line_count(wgsl) if wgsl.exists() else 9999
        if p.stem in tracker_text:
            continue  # skip shaders already in weekly tracker batches
        pool.append({"id": p.stem, "wgsl_lines": lines, "kind": kind})
    pool.sort(key=lambda e: (e["wgsl_lines"], e["id"]))
    return pool


def pick_next_batch(n: int = 8, **scan_kw) -> list[str]:
    """Pick the next n smallest never-batched shaders from the pool."""
    pool = scan_empty_updated_params_pool(**scan_kw)
    return [e["id"] for e in pool[:n]]
