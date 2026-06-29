#!/usr/bin/env python3
"""Agent 2f — Depth Write Fix Specialist. Adds missing writeDepthTexture stores."""
import re
import subprocess
import sys
from pathlib import Path

SHADERS = [
    "gen-polar-rainbow-explosion.wgsl",
    "gen-prismatic-cyber-auroral-manta-swarm.wgsl",
    "gen-prismatic-fractal-dunes.wgsl",
    "gen-prismatic-void-weaver-ouroboros.wgsl",
    "gen-quantum-chrome-serpent-ouroboros.wgsl",
    "gen-quantum-entangled-ferrofluid-engine.wgsl",
    "gen-quantum-fluorescent-aether-moth-swarm.wgsl",
    "gen-quantum-fluorescent-nebula-anemone.wgsl",
    "gen-radiant-cyber-chrono-void-stag.wgsl",
    "gen-sentient-aether-flora-biosphere.wgsl",
    "gen-sentient-cyber-aurora-void-owl.wgsl",
    "gen-sentient-ferro-silicate-swarm.wgsl",
    "gen-sentient-liquid-neon-fractal-heart.wgsl",
    "gen-sentient-quantum-chrono-leviathan-moth.wgsl",
    "gen-sonoluminescent-chrono-geode-matrix.wgsl",
    "glass-wipes.wgsl",
    "honey-melt.wgsl",
    "kimi_flock_symphony.wgsl",
    "liquid-v1.wgsl",
    "molten-gold.wgsl",
    "neon-edge-diffusion.wgsl",
    "neon-poly-grid.wgsl",
    "physarum-gemini.wgsl",
    "physarum-grokcf1.wgsl",
    "physarum.wgsl",
    "pyramid-bandprocess-pass2.wgsl",
    "pyramid-downsample-pass1.wgsl",
    "raindrop-ripples.wgsl",
    "spec-bicubic-crystal.wgsl",
    "spec-blue-noise-stipple.wgsl",
    "spec-cooperative-edge-linking.wgsl",
    "spec-distance-field-text.wgsl",
    "spec-hypercube-projection.wgsl",
    "spec-importance-sampled-bokeh.wgsl",
    "spec-iridescence-engine.wgsl",
    "spec-prismatic-dispersion.wgsl",
    "spec-quaternion-julia.wgsl",
    "spec-runge-kutta-advection.wgsl",
    "spec-spherical-harmonics-light.wgsl",
    "spec-temporal-path-tracer.wgsl",
    "stella-orbit.wgsl",
    "temporal-rift.wgsl",
    "viscous-drag.wgsl",
]

SHADER_DIR = Path("/root/image_video_effects/public/shaders")


def is_generative(content: str, filename: str) -> bool:
    if filename.startswith("gen-"):
        return True
    # Treat any actual use of readTexture (sample/load/function argument) as image/video.
    # textureDimensions(readTexture) alone is considered generative (just querying size).
    uses_read_texture = False
    for line in content.split("\n"):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if "readTexture" not in line:
            continue
        # Binding declaration is not usage
        if "@binding(1) var readTexture" in line:
            continue
        # textureDimensions is not sampling
        if re.search(r"textureDimensions\s*\(\s*readTexture", line):
            continue
        uses_read_texture = True
        break
    return not uses_read_texture


def get_global_id_param(content: str) -> str:
    # Only look inside fn main, not helper compute entry points
    main_start = content.find("fn main(")
    if main_start == -1:
        raise ValueError("Could not find main function")
    # Search from main start for the first global_invocation_id parameter
    m = re.search(
        r"@builtin\s*\(\s*global_invocation_id\s*\)\s+(\w+)\s*:\s*vec3<u32>",
        content[main_start:],
    )
    if not m:
        raise ValueError("Could not find global_invocation_id parameter in main")
    return m.group(1)


def has_write_depth_store(content: str) -> bool:
    return "textureStore(writeDepthTexture" in content


def has_write_depth_binding(content: str) -> bool:
    return "@binding(6) var writeDepthTexture" in content


def cleanup_duplicate_binding6(content: str) -> str:
    """Remove any binding-6 declarations that are not named writeDepthTexture."""
    lines = content.split("\n")
    result = []
    for line in lines:
        if "@binding(6)" in line and "var" in line and "writeDepthTexture" not in line:
            continue
        result.append(line)
    return "\n".join(result)


def add_write_depth_binding(content: str) -> str:
    lines = content.split("\n")
    for i, line in enumerate(lines):
        if "@binding(5)" in line and "var" in line:
            indent = len(line) - len(line.lstrip())
            new_line = (
                " " * indent
                + "@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;"
            )
            lines.insert(i + 1, new_line)
            return "\n".join(lines)
    raise ValueError("Could not find binding 5 to insert binding 6 after")


def find_main_end(content: str) -> int:
    main_start = content.find("fn main(")
    if main_start == -1:
        raise ValueError("Could not find main function")
    # Find the opening brace of fn main, skipping balanced parens in the param list
    paren_count = 1
    i = main_start + len("fn main(")
    while i < len(content) and paren_count > 0:
        if content[i] == "(":
            paren_count += 1
        elif content[i] == ")":
            paren_count -= 1
        i += 1
    # Skip whitespace/comments until opening brace
    while i < len(content) and content[i] not in "{":
        i += 1
    if i >= len(content) or content[i] != "{":
        raise ValueError("Could not find opening brace for main")
    start = i + 1
    brace_count = 1
    while i < len(content) and brace_count > 0:
        i += 1
        if content[i] == "{":
            brace_count += 1
        elif content[i] == "}":
            brace_count -= 1
    if brace_count != 0:
        raise ValueError("Could not find matching closing brace for main")
    return i


def find_uv_variable(content: str) -> str | None:
    main_start = content.find("fn main(")
    if main_start == -1:
        return None
    main_end = find_main_end(content)
    main_body = content[main_start : main_end + 1]
    # Prefer exact 'uv' then common alternatives
    for pattern in [r"\b(let|var)\s+(uv)\s*[:=]", r"\b(let|var)\s+(UV|uv_coords|texCoord|vUv|st)\s*[:=]"]:
        m = re.search(pattern, main_body)
        if m:
            return m.group(2)
    return None


def process_file(filename: str, dry_run: bool = False) -> dict:
    path = SHADER_DIR / filename
    result = {
        "file": filename,
        "ok": False,
        "generative": None,
        "error": None,
        "naga": None,
    }
    try:
        content = path.read_text()

        if has_write_depth_store(content):
            # Already fixed; just validate.
            naga = subprocess.run(
                ["naga", str(path), "/tmp/out.wgsl"],
                capture_output=True,
                text=True,
            )
            result["naga"] = naga.returncode
            result["generative"] = is_generative(content, filename)
            result["ok"] = naga.returncode == 0
            if naga.returncode != 0:
                result["error"] = naga.stderr.strip()
            return result

        generative = is_generative(content, filename)
        result["generative"] = generative
        param = get_global_id_param(content)

        content = cleanup_duplicate_binding6(content)

        if not has_write_depth_binding(content):
            content = add_write_depth_binding(content)

        main_end = find_main_end(content)

        if generative:
            insert = f"    textureStore(writeDepthTexture, {param}.xy, vec4<f32>(0.0, 0.0, 0.0, 0.0));\n"
        else:
            uv = find_uv_variable(content)
            if uv:
                insert = (
                    f"    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, {uv}, 0.0).r;\n"
                    f"    textureStore(writeDepthTexture, {param}.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));\n"
                )
            else:
                insert = (
                    f"    let uv = vec2<f32>({param}.xy) / vec2<f32>(textureDimensions(readTexture));\n"
                    f"    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;\n"
                    f"    textureStore(writeDepthTexture, {param}.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));\n"
                )

        new_content = content[:main_end] + insert + content[main_end:]

        if dry_run:
            result["ok"] = True
            result["dry_run"] = True
            return result

        path.write_text(new_content)

        naga = subprocess.run(
            ["naga", str(path), "/tmp/out.wgsl"],
            capture_output=True,
            text=True,
        )
        result["naga"] = naga.returncode
        if naga.returncode != 0:
            result["error"] = naga.stderr.strip()
        else:
            result["ok"] = True
    except Exception as e:
        result["error"] = str(e)
    return result


def main():
    dry_run = "--dry-run" in sys.argv
    results = []
    for shader in SHADERS:
        results.append(process_file(shader, dry_run=dry_run))

    generative_count = sum(1 for r in results if r.get("generative"))
    image_count = len(results) - generative_count
    ok_count = sum(1 for r in results if r["ok"])
    failures = [r for r in results if not r["ok"]]

    print(f"Processed: {len(results)}")
    print(f"Generative: {generative_count}")
    print(f"Image/video: {image_count}")
    print(f"OK: {ok_count}")
    print(f"Failures: {len(failures)}")
    for r in failures:
        print(f"  - {r['file']}: {r.get('error', 'unknown error')}")

    if dry_run:
        print("\n(DRY RUN — no files modified)")

    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
