"""Generate briefs for the 2026-08-03 geometric-complexity generative swarm (b31 + b32)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "shader_definitions" / "generative"
SH = ROOT / "public" / "shaders"
TASKS = ROOT / "agents" / "swarm-tasks"

B31 = {
    "algorithmist": ["gen-quantum-acoustic-bioluminescent-void-urchin", "gen-ethereal-cyber-plasma-void-dragon",
                     "gen-prismatic-cyber-aether-void-kitsune", "gen-sentient-cyber-chrono-void-serpent"],
    "visualist": ["gen-ethereal-bismuth-resonance-void-owl", "gen-radiant-cyber-plasma-astro-griffin",
                  "gen-vitreous-quantum-lotus-singularity"],
    "interactivist": ["gen-bioluminescent-chrono-plasma-astro-owl", "gen-luminescent-aether-plasma-astro-axolotl",
                      "gen-resonant-quantum-obsidian-astro-manta"],
    "optimizer": ["gen-luminescent-quantum-flora-symphony", "gen-radiant-cyber-bismuth-nebula-colossus",
                  "gen-prismatic-cyber-chrono-void-tortoise"],
}
B32 = {
    "algorithmist": ["gen-chaos-game-ifs", "gen-aperiodic-monotile"],
    "visualist": ["gen-glacial-aether-quantum-cavern", "gen-depth-refracted-liquid-stained-glass"],
    "interactivist": ["gen-navier-stokes-ink", "gen-lorenz-attractor-flow"],
    "optimizer": ["gen-de-jong-attractor", "gen-lorenz-attractor"],
}

ROLE_GEO = {
    "algorithmist": (
        "Geometry mandate (primary): add a 3D SDF library (sdSphere/sdBox/sdTorus/sdOctahedron/sdCapsule + smin smooth "
        "unions) and raymarch at least one geometric form (map() -> vec2(dist, matID), adaptive steps). Layer 2D "
        "geometric complexity: polygon SDFs, hex/Voronoi tessellation, truchet tiles, kaleidoscopic symmetry folds, "
        "and/or a Julia/orbit-trap pass. Fuse the new geometry with the shader's existing soul — do not rewrite it."
    ),
    "visualist": (
        "Geometry mandate (primary): give the forms real 3D presence — surface normals from the SDF/heightfield, "
        "3-point lighting + Fresnel rim, ACES tonemap, material-ID driven palettes, per-facet/per-cell color "
        "variation, thin-film iridescence on geometric shells. Add 2D geometric patterning (tessellated inlays, "
        "symmetry-folded ornament) where it serves the creature/theme."
    ),
    "interactivist": (
        "Geometry mandate (primary): make the geometry reactive — mouse orbit camera built from u.zoom_config.yz "
        "(already normalized 0-1, y=0 top: do NOT re-normalize or flip), click ripples that deform/displace the "
        "geometric forms, and REAL audio reactivity (plasmaBuffer[0].xyz bass/mids/treble; extraBuffer[5..132] FFT "
        "bins read-only) driving scale/twist/fold of the 3D and 2D geometry."
    ),
    "optimizer": (
        "Geometry mandate (primary): integrate geometric complexity at budget — adaptive raymarch step counts, LOD "
        "on FBM/tessellation detail, early exits, named constants, select/mix over branches. Ensure every declared "
        "slider is LIVE in the WGSL and every declared feature is real (no dead sliders, no fake FFT, no mask-as-color)."
    ),
}

CONTRACT = """## Non-negotiable contract

- Canonical 13-binding header verbatim (see agents/WGSL_BUILTINS_GENERATIVE.md §0); Uniforms struct EXACTLY:
  `config, zoom_config, zoom_params, ripples` — no extra/reordered fields.
- `@compute @workgroup_size(16, 16, 1)` (3 explicit dims) + resolution bounds guard on global_invocation_id.
- Write `writeTexture`, `writeDepthTexture`, and `dataTextureA` EVERY frame.
- Only `textureSampleLevel`/`textureLoad`/`textureStore`. NO `tan`, `textureSample`, `dpdx`, `dpdy`. No WGSL reserved words as identifiers.
- Uniform truth: config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY(top-down), mouseDown].
  Guard ripple loops with `min(u32(u.config.y), 50u)`.
- extraBuffer: [0..4] engine-reserved, [5..132] engine FFT bins (read-only); persistent state ONLY in [133..255],
  single-writer guard (gid.x==0u && gid.y==0u) + arrayLength check.
- Audio ONLY from plasmaBuffer[0].xyz (bass/mids/treble) and FFT bins — no hash-based fake spectrum.
- Semantic alpha — never hardcode 1.0 unless opaque by design. No flat-0.0 depth clobber: write real depth (or passthrough).
- Prefer select/mix over per-pixel branches. No inverted smoothstep falloffs.
"""

B31_EXTRA = """## CRITICAL BUG FIX (do this FIRST)

This shader currently declares a NON-CANONICAL extended Uniforms struct (resolution/time/frame/view_matrix/
proj_matrix/camera_pos fields). It misaligns against the engine's 848-byte uniform buffer at runtime.
Replace it with the canonical struct and remap all references:
- u.time -> u.config.x
- u.resolution -> u.config.zw
- u.frame -> derive from time if needed (u.config.x * 60.0)
- u.mouse (if any) -> u.zoom_config.yz (0-1, y=0 TOP, no flip)
- view_matrix/proj_matrix/camera_pos -> DELETE; rebuild any camera in-code from u.zoom_config.yz + u.config.x
"""


def brief(batch: str, role: str, sid: str) -> str:
    meta = json.loads((GEN / f"{sid}.json").read_text())
    wgsl = SH / f"{sid}.wgsl"
    if not wgsl.exists():
        wgsl = SH / meta.get("url", "").rsplit("/", 1)[-1]
    lines = len(wgsl.read_text().splitlines())
    up = meta.get("updatedParams", [])
    params_md = "\n".join(
        f"  - index {p.get('index', i)}: \"{p.get('name', f'param{i}')}\" default={p.get('default', 0.5)} min={p.get('min', 0.0)} max={p.get('max', 1.0)} step={p.get('step', 0.01)}"
        for i, p in enumerate(up)
    ) or "  - (none — define exactly 4)"
    parts = [
        f"# Swarm Brief — {sid} (batch {batch}, role: {role})",
        "",
        f"- **ID**: {sid}",
        f"- **Name**: {meta.get('name', sid)}",
        "- **Category**: generative",
        f"- **Description**: {meta.get('description', '')}",
        f"- **Current lines**: {lines}  |  **Target**: {lines + 60}–{lines + 90} (+60 to +90)",
        "",
        "## Existing updatedParams (preset contract — keep names/defaults EXACTLY, indices 0-3)",
        params_md,
        "",
        "## Role instructions",
        ROLE_GEO[role],
        "",
        "Wire all 4 sliders to MEANINGFUL shader-specific constants (geometry scale/fold/twist, light, reactivity, "
        "palette...). Every slider must be live. Preserve the shader's soul — upgrade, don't rewrite.",
    ]
    if batch == "b31":
        parts += ["", B31_EXTRA.strip(),
                  "",
                  "JSON deliverable: keep id/name/url/category/tags; keep the 4 updatedParams above; set "
                  "`\"updated\": true`; add `\"supportsDepth\": true` if you write real depth; you may extend tags "
                  "with geometry tags (e.g. \"sdf\", \"raymarched\", \"tessellation\") and refresh the description."]
    else:
        parts += ["",
                  "JSON deliverable: keep id/name/url/category and the 4 updatedParams above EXACTLY; keep "
                  "`\"updated\": true`; add `\"supportsDepth\": true` if you write real depth; you may extend tags "
                  "with geometry tags and refresh the description."]
    parts += ["", CONTRACT.strip(),
              "",
              "## Deliverables (write to the batch output dir given in your task prompt)",
              f"1. `{sid}.wgsl` — complete, self-contained upgraded shader (canonical header).",
              f"2. `{sid}.json` — complete upgraded metadata.",
              f"3. `{sid}.md` — changelog: what changed & why, loop budget/perf estimate, rating prediction.",
              "",
              "Reference pattern: public/shaders/gen-audiovisual-mandelbulb-raymarcher.wgsl",
              ]
    return "\n".join(parts) + "\n"


for batch, table in (("b31", B31), ("b32", B32)):
    outdir = TASKS / f"kimi-generative-briefs-2026-08-03-{batch}"
    outdir.mkdir(parents=True, exist_ok=True)
    for role, ids in table.items():
        for sid in ids:
            assert (GEN / f"{sid}.json").exists(), sid
            (outdir / f"{sid}.md").write_text(brief(batch, role, sid))
    print(batch, "->", outdir, sum(len(v) for v in table.values()), "briefs")
