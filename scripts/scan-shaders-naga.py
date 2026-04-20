#!/usr/bin/env python3
"""
Proper naga-based WGSL scanner.
Runs the real `naga` CLI on every .wgsl file and captures full error output.
Then optionally pipes failures to kimi-cli for fixes + visual improvements.
"""

import os
import subprocess
import json
import sys
from pathlib import Path
from datetime import datetime, timezone

SHADERS_DIR = Path("public/shaders").resolve()
REPORT_FILE = Path("reports/naga-scan-report.json")
USE_KIMI = "--kimi" in sys.argv

# Ensure cargo bin is on PATH so naga can be found
CARGO_BIN = Path.home() / ".cargo" / "bin"
if str(CARGO_BIN) not in os.environ.get("PATH", ""):
    os.environ["PATH"] = f"{CARGO_BIN}{os.pathsep}{os.environ.get('PATH', '')}"


def run_naga(wgsl_file: Path) -> dict:
    """Run naga CLI on a single .wgsl file. Returns full result dict."""
    try:
        result = subprocess.run(
            ["naga", str(wgsl_file)],
            capture_output=True,
            text=True,
            timeout=15,
        )
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


def ask_kimi(wgsl_path: Path, raw_error: str) -> str:
    """Send failing shader + error to kimi-cli for fix + visual improvement."""
    try:
        wgsl_code = wgsl_path.read_text()
    except Exception as e:
        return f"Could not read file: {e}"

    prompt = f"""You are a WebGPU WGSL expert. This shader failed naga validation.

File: {wgsl_path}

NAGA ERROR OUTPUT:
{raw_error}

SHADER CODE:
```wgsl
{wgsl_code}
```

Please:

1. FIX the compile error(s) shown above. Explain what was wrong.
2. IMPROVE the visual output — suggest and apply richer colors, better noise/math, glow effects, or more dynamic animation while keeping the shader's theme.
3. Return the complete, fixed WGSL code in a single code block.
"""

    try:
        result = subprocess.run(
            ["kimi-cli", "--no-stream"],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=120,
        )
        return result.stdout.strip() or result.stderr.strip()
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
