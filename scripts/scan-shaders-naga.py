#!/usr/bin/env python3
"""
Proper naga-based WGSL scanner.
Runs the real `naga` CLI on every .wgsl file and captures full error output.
Then optionally pipes failures to kimi-cli for fixes + visual improvements.
"""

import os
import re
import subprocess
import json
import sys
from pathlib import Path
from datetime import datetime, timezone
import tempfile

from wgsl_include import WgslIncludeError, expand_wgsl_includes, has_wgsl_include

SHADERS_DIR = Path("public/shaders").resolve()
REPORT_FILE = Path("reports/naga-scan-report.json")
USE_KIMI = "--kimi" in sys.argv

# Ensure cargo bin is on PATH so naga can be found
CARGO_BIN = Path.home() / ".cargo" / "bin"
if str(CARGO_BIN) not in os.environ.get("PATH", ""):
    os.environ["PATH"] = f"{CARGO_BIN}{os.pathsep}{os.environ.get('PATH', '')}"

# Catalog shaders get their 13 bindings and struct Uniforms from the prelude
# (#1313); kimi-cli must keep the include and never paste them back.
BINDING_HEADER = """\
#include "_prelude.wgsl"
// Declares bindings 0-12 (u_sampler, readTexture, writeTexture, u, readDepthTexture,
// non_filtering_sampler, writeDepthTexture, dataTextureA, dataTextureB, dataTextureC,
// extraBuffer, comparison_sampler, plasmaBuffer) and struct Uniforms
// (config, zoom_config, zoom_params, ripples). Never paste them into the shader.\
"""


def run_naga(wgsl_file: Path) -> dict:
    """
    Run naga CLI on a single .wgsl file. Returns full result dict.

    The naga CLI has no preprocessor, so `#include` is expanded into a temp file
    first (npm run verify:naga-wasm does the same in-process and is the gate).
    """
    try:
        source = wgsl_file.read_text(encoding="utf-8")
        target = wgsl_file
        if has_wgsl_include(source):
            try:
                expanded = expand_wgsl_includes(source, entry=wgsl_file.name)
            except WgslIncludeError as exc:
                return {"valid": False, "errors": [{"line": None, "col": None, "message": str(exc)}], "raw": str(exc)}
            tmp = tempfile.NamedTemporaryFile("w", suffix=".wgsl", delete=False, encoding="utf-8")
            tmp.write(expanded)
            tmp.close()
            target = Path(tmp.name)
        try:
            result = subprocess.run(
                ["naga", str(target)],
                capture_output=True,
                text=True,
                timeout=15,
            )
        finally:
            if target != wgsl_file:
                target.unlink(missing_ok=True)
        if result.returncode == 0:
            return {"valid": True, "errors": [], "raw": ""}
        else:
            raw_error = result.stderr.strip() or result.stdout.strip()
            errors = parse_naga_errors(raw_error)
            return {"valid": False, "errors": errors, "raw": raw_error}
    except FileNotFoundError:
        print("ERROR: `naga` not found. Install with: cargo install naga-cli")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        return {
            "valid": False,
            "errors": [{"line": None, "col": None, "message": "Timeout"}],
            "raw": "timeout",
        }


def parse_naga_errors(raw: str) -> list:
    """Parse naga error output into structured list."""
    errors = []
    current = None
    for line in raw.splitlines():
        line_stripped = line.strip()
        if not line_stripped:
            continue
        # naga typically outputs:
        #   error: <message>
        #     --> <file>:<line>:<col>
        if line_stripped.startswith("error:") or line_stripped.startswith("Error"):
            if current:
                errors.append(current)
            current = {"line": None, "col": None, "message": line_stripped}
        elif line_stripped.startswith("-->") and current:
            parts = line_stripped.split(":")
            if len(parts) >= 2:
                try:
                    current["line"] = int(parts[-2])
                    current["col"] = int(parts[-1])
                except ValueError:
                    pass
        elif current and (line_stripped.startswith("|") or line_stripped.startswith("^")):
            current["message"] += f"\n  {line}"
    if current:
        errors.append(current)
    if not errors and raw:
        errors.append({"line": None, "col": None, "message": raw})
    return errors


def find_shader_json(wgsl_path: Path) -> dict:
    """Try to locate the JSON shader definition and return its parsed contents."""
    stem = wgsl_path.stem
    definitions_dir = Path("shader_definitions").resolve()
    if not definitions_dir.exists():
        return {}
    for cat_dir in definitions_dir.iterdir():
        if not cat_dir.is_dir():
            continue
        # Legacy underscore WGSL stems map to definition files named after the hyphen id.
        json_file = next(
            (p for p in (cat_dir / f"{stem}.json", cat_dir / f"{stem.replace('_', '-')}.json") if p.exists()),
            cat_dir / f"{stem}.json",
        )
        if json_file.exists():
            try:
                return json.loads(json_file.read_text(encoding="utf-8"))
            except Exception:
                return {}
    return {}


def _extract_first_wgsl_block(text: str) -> str:
    """Return the first ```wgsl … ``` block from text, trimming trailing prose.

    Uses a non-greedy match which is safe here because valid WGSL source
    never contains triple-backtick sequences.
    """
    match = re.search(r"```wgsl\s*\n(.*?)```", text, re.DOTALL)
    if match:
        return f"```wgsl\n{match.group(1)}```"
    return text


def ask_kimi(wgsl_path: Path, raw_error: str) -> str:
    """Send failing shader + error to kimi-cli for fix + visual improvement."""
    try:
        wgsl_code = wgsl_path.read_text(encoding="utf-8")
    except Exception as e:
        return f"Could not read file: {e}"

    current_lines = len(wgsl_code.splitlines())
    line_cap = current_lines + 40

    # Build a one-sentence theme from the JSON definition when available
    shader_def = find_shader_json(wgsl_path)
    shader_name = shader_def.get("name", wgsl_path.stem)
    shader_desc = shader_def.get("description", "")
    if shader_desc:
        theme_sentence = f'This shader is "{shader_name}" — {shader_desc}.'
    else:
        theme_sentence = f'This shader is "{shader_name}".'

    prompt = f"""You are a WebGPU WGSL expert. This shader failed naga validation.

Shader theme: {theme_sentence}

File: {wgsl_path}

## Bindings (keep this include as the first code line — do NOT paste, rename or reorder bindings)
```wgsl
{BINDING_HEADER}
```

## NAGA ERROR OUTPUT
{raw_error}

## SHADER CODE
```wgsl
{wgsl_code}
```

## Instructions
1. FIX all compile errors shown above.
2. IMPROVE the visual output — apply richer colors, better noise/math, glow, \
or more dynamic animation consistent with the shader theme.
3. Keep output to <= {line_cap} lines (prefer math density over comments).

**Return exactly one ```wgsl fenced block, no prose before or after.**"""

    try:
        result = subprocess.run(
            ["kimi-cli", "--no-stream"],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=120,
        )
        raw_output = result.stdout.strip() or result.stderr.strip()
        return _extract_first_wgsl_block(raw_output)
    except Exception as e:
        return f"kimi-cli failed: {e}"


def main():
    print("\n🔷 Naga WGSL Scanner\n")

    wgsl_files = sorted(SHADERS_DIR.rglob("*.wgsl"))
    print(f"Found {len(wgsl_files)} WGSL files in {SHADERS_DIR}\n")

    results = []
    valid_count = 0
    invalid_count = 0
    kimi_results = []

    for idx, wgsl_file in enumerate(wgsl_files, 1):
        relative = wgsl_file.relative_to(Path.cwd())
        result = run_naga(wgsl_file)

        entry = {
            "file": str(relative),
            "valid": result["valid"],
            "errors": result["errors"],
        }
        results.append(entry)

        if result["valid"]:
            valid_count += 1
            print(f"[{idx}/{len(wgsl_files)}] ✅ {relative}")
        else:
            invalid_count += 1
            print(f"\n[{idx}/{len(wgsl_files)}] ❌ {relative}")
            for err in result["errors"][:3]:
                line_info = f" (line {err['line']})" if err.get("line") else ""
                print(f"   └─ {err['message']}{line_info}")
            if len(result["errors"]) > 3:
                print(f"   └─ ... and {len(result['errors']) - 3} more errors")

            if USE_KIMI:
                print("   🤖 Asking kimi-cli for fix...")
                kimi_response = ask_kimi(wgsl_file, result["raw"])
                kimi_results.append({
                    "file": str(relative),
                    "kimi_response": kimi_response,
                })
                print("   ✅ kimi-cli responded")

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "total": len(wgsl_files),
        "valid": valid_count,
        "invalid": invalid_count,
        "shaders": results,
    }

    if USE_KIMI:
        report["kimi_results"] = kimi_results

    REPORT_FILE.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"\n{'═' * 60}")
    print("\n📊 Summary:")
    print(f"   Total shaders: {len(wgsl_files)}")
    print(f"   ✅ Valid: {valid_count}")
    print(f"   ❌ Invalid: {invalid_count}")
    print(f"\n📝 Report saved to: {REPORT_FILE}")

    sys.exit(1 if invalid_count > 0 else 0)


if __name__ == "__main__":
    main()
