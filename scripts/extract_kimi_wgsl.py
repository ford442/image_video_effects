#!/usr/bin/env python3
"""Extract and validate a WGSL block from kimi-cli stdout."""
import re
import subprocess
import sys
import os

BANNED = [
    "textureSample(",
    "dpdx(",
    "dpdy(",
    "tan(",
    "outputTex",
    "videoSampler",
    "iTime",
    "outTex",
    "// --- COPY PASTE THIS HEADER",  # stub header marker
]

REQUIRED_BINDINGS = [
    "@group(0) @binding(0) var u_sampler",
    "@group(0) @binding(1) var readTexture",
    "@group(0) @binding(2) var writeTexture",
    "@group(0) @binding(3) var<uniform> u: Uniforms",
    "@group(0) @binding(4) var readDepthTexture",
    "@group(0) @binding(12) var<storage, read> plasmaBuffer",
]

def extract_wgsl(text: str) -> str | None:
    # Find first fenced wgsl block
    m = re.search(r"```wgsl\n(.*?)```", text, re.DOTALL)
    if not m:
        # Try generic code fence
        m = re.search(r"```\n(.*?)```", text, re.DOTALL)
        if not m:
            return None
    return m.group(1).strip()

def validate(code: str) -> list[str]:
    errs = []
    for tok in BANNED:
        if tok in code:
            errs.append(f"banned token: {tok}")
    for req in REQUIRED_BINDINGS:
        if req not in code:
            errs.append(f"missing required binding: {req}")
    if "plasmaBuffer[0]" not in code:
        errs.append("does not read plasmaBuffer[0]")
    return errs

def naga_check(code: str, shader_id: str) -> list[str]:
    errs = []
    tmp_path = f"/tmp/{shader_id}_kimi_raw.wgsl"
    with open(tmp_path, "w") as f:
        f.write(code)
    try:
        result = subprocess.run(
            ["naga", tmp_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            errs.append(f"naga error: {result.stderr or result.stdout}")
    except FileNotFoundError:
        errs.append("naga not found in PATH")
    except subprocess.TimeoutExpired:
        errs.append("naga validation timed out")
    return errs

def main():
    if len(sys.argv) < 2:
        print("usage: extract_kimi_wgsl.py <shader_id> [raw_output_path]", file=sys.stderr)
        sys.exit(1)
    shader_id = sys.argv[1]
    if len(sys.argv) >= 3:
        with open(sys.argv[2]) as f:
            raw = f.read()
    else:
        raw = sys.stdin.read()

    code = extract_wgsl(raw)
    if code is None:
        print("NO_WGSL_BLOCK")
        # Write raw to reject for inspection
        os.makedirs("swarm-outputs/kimi-rejects", exist_ok=True)
        with open(f"swarm-outputs/kimi-rejects/{shader_id}_no_block.md", "w") as f:
            f.write(raw)
        sys.exit(2)

    errs = validate(code)
    if not errs:
        errs.extend(naga_check(code, shader_id))

    if errs:
        print("FAILED")
        for e in errs:
            print(f"  - {e}")
        os.makedirs("swarm-outputs/kimi-rejects", exist_ok=True)
        with open(f"swarm-outputs/kimi-rejects/{shader_id}_reject.md", "w") as f:
            f.write(f"# Reject: {shader_id}\n\nErrors:\n")
            for e in errs:
                f.write(f"- {e}\n")
            f.write("\n## Raw output\n\n```\n")
            f.write(raw)
            f.write("\n```\n\n## Extracted WGSL\n\n```wgsl\n")
            f.write(code)
            f.write("\n```\n")
        sys.exit(3)

    # Success
    out_path = f"public/shaders/{shader_id}.wgsl"
    with open(out_path, "w") as f:
        f.write(code)
    print(f"OK: {out_path}")
    sys.exit(0)

if __name__ == "__main__":
    main()
