#!/usr/bin/env python3
"""
BindGroup Auto-Repair Script for Pixelocity Shaders

Reads current bind-group violations and applies deterministic, safe rewrites:
  1. Binding 10: var<storage, read> → var<storage, read_write>
  2. Binding 12: var<storage> (no access) → var<storage, read>
  3. Missing bindings (4-12): insert canonical stub declarations
  4. Missing Uniforms ripples field: append conservatively (only when safe)

Shaders that cannot be auto-fixed (wrong struct type, complex layout) are
flagged in the summary for manual review.

Outputs:
  - In-place fixes to public/shaders/*.wgsl
  - Updated reports/bindgroup_compatibility_report.json
  - New     reports/bindgroup_fix_summary.md
"""

import os
import re
import json
import glob
import shutil
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parent.parent
SHADERS_DIR = REPO_ROOT / "public" / "shaders"
REPORTS_DIR = REPO_ROOT / "reports"
REPORT_PATH = REPORTS_DIR / "bindgroup_compatibility_report.json"
SUMMARY_PATH = REPORTS_DIR / "bindgroup_fix_summary.md"

# ---------------------------------------------------------------------------
# Canonical binding declarations (used when inserting missing stubs)
# ---------------------------------------------------------------------------
CANONICAL_BINDINGS = {
    0:  "@group(0) @binding(0)  var u_sampler: sampler;",
    1:  "@group(0) @binding(1)  var readTexture: texture_2d<f32>;",
    2:  "@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;",
    3:  "@group(0) @binding(3)  var<uniform> u: Uniforms;",
    4:  "@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;",
    5:  "@group(0) @binding(5)  var non_filtering_sampler: sampler;",
    6:  "@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;",
    7:  "@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;",
    8:  "@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;",
    9:  "@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;",
    10: "@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;",
    11: "@group(0) @binding(11) var comparison_sampler: sampler_comparison;",
    12: "@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;",
}

# ---------------------------------------------------------------------------
# Regex patterns
# ---------------------------------------------------------------------------

# Matches any @group(0) @binding(N) declaration line (possibly multi-line whitespace)
BINDING_DECL_RE = re.compile(
    r"@group\(0\)\s*@binding\((\d+)\)\s*var\s*(<[^>]+>)?\s*\w+\s*:\s*[^;]+;",
    re.MULTILINE | re.DOTALL,
)

# Binding-10 specific: matches '<storage, read>' (but NOT '<storage, read_write>')
B10_WRONG_RE = re.compile(
    r"(@group\(0\)\s*@binding\(10\)\s*var)"
    r"\s*<storage,\s*read>"          # wrong access – read only
    r"(?!\s*_write)",                # negative lookahead: must NOT be followed by _write
    re.MULTILINE,
)

# Binding-12 specific: matches '<storage>' with NO access qualifier at all
B12_WRONG_RE = re.compile(
    r"(@group\(0\)\s*@binding\(12\)\s*var)"
    r"\s*<storage>"                  # no access qualifier (neither read nor read_write)
    r"(?!\s*,)",                     # negative lookahead: must NOT be 'storage, something'
    re.MULTILINE,
)

# Uniforms struct body
UNIFORMS_STRUCT_RE = re.compile(
    r"struct\s+Uniforms\s*\{([^}]+)\}",
    re.MULTILINE | re.DOTALL,
)

# Individual struct field names
STRUCT_FIELD_NAME_RE = re.compile(r"^\s*(\w+)\s*:", re.MULTILINE)

# Template / render shader markers (skip these)
TEMPLATE_FILES = {
    "_hash_library.wgsl",
    "_template_shared_memory.wgsl",
    "_template_workgroup_atomics.wgsl",
    "gen_capabilities.wgsl",
}
RENDER_SHADERS = {"imageVideo.wgsl", "texture.wgsl"}

# ---------------------------------------------------------------------------
# Helper: find all declared binding numbers in the file
# ---------------------------------------------------------------------------

def get_declared_bindings(content: str) -> set[int]:
    return {int(m.group(1)) for m in BINDING_DECL_RE.finditer(content)}


# ---------------------------------------------------------------------------
# Fix 1 – Binding 10 wrong access mode
# ---------------------------------------------------------------------------

def fix_binding_10_access(content: str) -> tuple[str, bool]:
    """Replace <storage, read> with <storage, read_write> for @binding(10)."""
    fixed = B10_WRONG_RE.sub(r"\1<storage, read_write>", content)
    return fixed, fixed != content


# ---------------------------------------------------------------------------
# Fix 2 – Binding 12 wrong access mode
# ---------------------------------------------------------------------------

def fix_binding_12_access(content: str) -> tuple[str, bool]:
    """Replace bare <storage> with <storage, read> for @binding(12)."""
    fixed = B12_WRONG_RE.sub(r"\1<storage, read>", content)
    return fixed, fixed != content


# ---------------------------------------------------------------------------
# Fix 3 – Add missing binding declarations
# ---------------------------------------------------------------------------

def _last_binding_end(content: str) -> int:
    """Return the character position immediately after the last @binding() declaration."""
    last_end = -1
    for m in BINDING_DECL_RE.finditer(content):
        last_end = m.end()
    return last_end


def add_missing_bindings(content: str, missing: list[int]) -> tuple[str, bool]:
    """
    Insert canonical declarations for the given missing binding numbers directly
    after the last existing binding declaration in the file.
    Only inserts bindings that are absent AND have a known canonical declaration.
    """
    # Filter to only bindings we have canonical forms for
    to_add = sorted(b for b in missing if b in CANONICAL_BINDINGS)
    if not to_add:
        return content, False

    insert_pos = _last_binding_end(content)
    if insert_pos == -1:
        # No binding declarations found at all – skip
        return content, False

    stub_lines = "\n".join(CANONICAL_BINDINGS[b] for b in to_add)
    insert_text = "\n" + stub_lines
    fixed = content[:insert_pos] + insert_text + content[insert_pos:]
    return fixed, True


# ---------------------------------------------------------------------------
# Fix 4 – Add missing ripples field to Uniforms struct (conservative)
# ---------------------------------------------------------------------------

def add_uniforms_ripples(content: str) -> tuple[str, bool]:
    """
    Append 'ripples: array<vec4<f32>, 50>,' to the Uniforms struct if it is
    missing AND the struct contains only the three canonical fields (config,
    zoom_config, zoom_params).  Shaders with extra fields are skipped because
    the ripples field would land at the wrong memory offset.
    """
    m = UNIFORMS_STRUCT_RE.search(content)
    if not m:
        return content, False

    struct_body = m.group(1)

    # Already has ripples?
    if "ripples" in struct_body:
        return content, False

    # Collect field names
    fields = STRUCT_FIELD_NAME_RE.findall(struct_body)
    canonical_fields = {"config", "zoom_config", "zoom_params"}
    extra_fields = set(fields) - canonical_fields
    if extra_fields:
        # Unsafe: extra fields shift the ripples offset
        return content, False

    # Append ripples before the closing brace
    closing_brace_pos = m.start(1) + len(m.group(1))
    # m.group(1) ends just before the '}'
    # Insert just before the closing brace of the struct
    struct_end = m.start() + content[m.start():].index("}") + 1
    # Find the closing brace inside the full match
    full_match = m.group(0)
    brace_idx = full_match.rindex("}")
    ripples_line = "  ripples: array<vec4<f32>, 50>,\n"
    new_struct = full_match[:brace_idx] + ripples_line + full_match[brace_idx:]
    fixed = content[:m.start()] + new_struct + content[m.end():]
    return fixed, True


# ---------------------------------------------------------------------------
# Check helper: does this file need any fixes?
# ---------------------------------------------------------------------------

def classify_shader(content: str, filename: str) -> dict:
    """
    Quick classification of a WGSL file.  Returns a dict with:
      - fix_b10, fix_b12, missing_bindings, fix_ripples  (what can be auto-fixed)
      - skip_reason   (non-empty string means skip entirely)
      - manual_flags  (list of issues that need human review)
    """
    result = {
        "fix_b10": False,
        "fix_b12": False,
        "missing_bindings": [],
        "fix_ripples": False,
        "skip_reason": "",
        "manual_flags": [],
    }

    if filename in TEMPLATE_FILES:
        result["skip_reason"] = "template file"
        return result
    if filename in RENDER_SHADERS:
        result["skip_reason"] = "render shader (vertex/fragment)"
        return result
    if "@compute" not in content:
        result["skip_reason"] = "no @compute entry point"
        return result

    # Binding 10 access mode
    if B10_WRONG_RE.search(content):
        result["fix_b10"] = True

    # Binding 12 access mode
    if B12_WRONG_RE.search(content):
        result["fix_b12"] = True

    # Binding 12 wrong type (e.g., array<PlasmaBall, 50>) – manual only
    b12_type_re = re.compile(
        r"@group\(0\)\s*@binding\(12\)\s*var\s*<[^>]+>\s*\w+\s*:\s*([^;]+);",
        re.MULTILINE | re.DOTALL,
    )
    b12_type_m = b12_type_re.search(content)
    if b12_type_m:
        t = b12_type_m.group(1).strip().replace(" ", "").lower()
        if "plasmabuffer" not in t and "array<vec4<f32>" not in t:
            result["manual_flags"].append(
                f"binding 12 wrong type: {b12_type_m.group(1).strip()!r}"
            )

    # Missing bindings
    declared = get_declared_bindings(content)
    required = set(range(13))  # 0-12
    missing = sorted(required - declared)
    # Only auto-fix extended bindings (4-12); 0-3 missing means deep issue
    core_missing = [b for b in missing if b < 4]
    ext_missing = [b for b in missing if b >= 4]
    if core_missing:
        result["manual_flags"].append(f"missing core bindings: {core_missing}")
    if ext_missing:
        result["missing_bindings"] = ext_missing

    # Uniforms struct ripples
    um = UNIFORMS_STRUCT_RE.search(content)
    if um:
        fields = STRUCT_FIELD_NAME_RE.findall(um.group(1))
        if "ripples" not in fields:
            extra = set(fields) - {"config", "zoom_config", "zoom_params"}
            if extra:
                result["manual_flags"].append(
                    f"Uniforms missing ripples but has extra fields {sorted(extra)} "
                    f"– manual layout fix required"
                )
            else:
                result["fix_ripples"] = True
    else:
        result["manual_flags"].append("Uniforms struct not found")

    return result


# ---------------------------------------------------------------------------
# Main repair loop
# ---------------------------------------------------------------------------

def repair_shader(filepath: Path) -> dict:
    """Apply all safe auto-fixes to a single shader file.  Returns an audit record."""
    filename = filepath.name
    content_orig = filepath.read_text(encoding="utf-8")

    record = {
        "shader_id": filepath.stem,
        "file": str(filepath),
        "fixes_applied": [],
        "manual_flags": [],
        "skipped": False,
        "skip_reason": "",
        "status": "no_action",
    }

    classification = classify_shader(content_orig, filename)

    if classification["skip_reason"]:
        record["skipped"] = True
        record["skip_reason"] = classification["skip_reason"]
        record["status"] = "skipped"
        return record

    record["manual_flags"] = classification["manual_flags"]

    content = content_orig
    changed = False

    if classification["fix_b10"]:
        content, did_fix = fix_binding_10_access(content)
        if did_fix:
            record["fixes_applied"].append("binding_10_access: read → read_write")
            changed = True

    if classification["fix_b12"]:
        content, did_fix = fix_binding_12_access(content)
        if did_fix:
            record["fixes_applied"].append("binding_12_access: <storage> → <storage, read>")
            changed = True

    if classification["missing_bindings"]:
        content, did_fix = add_missing_bindings(content, classification["missing_bindings"])
        if did_fix:
            record["fixes_applied"].append(
                f"added_missing_bindings: {classification['missing_bindings']}"
            )
            changed = True

    if classification["fix_ripples"]:
        content, did_fix = add_uniforms_ripples(content)
        if did_fix:
            record["fixes_applied"].append("uniforms_ripples_field_added")
            changed = True

    if changed:
        filepath.write_text(content, encoding="utf-8")
        record["status"] = "fixed"
    elif record["manual_flags"]:
        record["status"] = "needs_manual_review"
    else:
        record["status"] = "already_compatible"

    return record


# ---------------------------------------------------------------------------
# Re-run the compatibility checker (reusing checker logic inline)
# ---------------------------------------------------------------------------

def _run_checker_inline() -> dict:
    """
    Run the same logic as bindgroup_checker.py but without writing anything.
    Returns the report dict.
    """
    # Import checker logic by exec-ing the file
    checker_path = Path(__file__).parent / "bindgroup_checker.py"
    if not checker_path.exists():
        return {}

    checker_code = checker_path.read_text()
    # Patch hardcoded paths to work wherever the repo lives
    checker_code = checker_code.replace(
        "/root/image_video_effects",
        str(REPO_ROOT),
    )
    namespace: dict = {"__name__": "module"}
    exec(compile(checker_code, str(checker_path), "exec"), namespace)

    parse_shader_fn = namespace["parse_shader"]
    EXPECTED_BINDINGS_cfg = namespace["EXPECTED_BINDINGS"]
    TEMPLATE_FILES_cfg = namespace["TEMPLATE_FILES"]
    RENDER_SHADERS_cfg = namespace["RENDER_SHADERS"]

    shader_files = sorted(SHADERS_DIR.glob("*.wgsl"))

    report = {
        "timestamp": datetime.now().isoformat(),
        "total_shaders": len(shader_files),
        "compatible_count": 0,
        "incompatible_count": 0,
        "template_count": 0,
        "render_shader_count": 0,
        "shaders": [],
        "summary": {
            "by_category": {
                "compatible": [],
                "incompatible": [],
                "templates": [],
                "render_shaders": [],
            },
            "issues": {
                "missing_bindings": {},
                "wrong_types": {},
                "invalid_workgroup": [],
                "missing_uniforms_fields": [],
            },
        },
    }

    for fp in shader_files:
        try:
            result = parse_shader_fn(str(fp))
        except Exception as exc:
            result = {
                "shader_id": fp.stem,
                "file": str(fp),
                "status": "incompatible",
                "errors": [f"Parse error: {exc}"],
            }

        report["shaders"].append(result)
        status = result.get("status", "incompatible")
        sid = result.get("shader_id", fp.stem)

        if status == "template":
            report["template_count"] += 1
            report["summary"]["by_category"]["templates"].append(sid)
        elif status == "render_shader":
            report["render_shader_count"] += 1
            report["summary"]["by_category"]["render_shaders"].append(sid)
        elif status == "compatible":
            report["compatible_count"] += 1
            report["summary"]["by_category"]["compatible"].append(sid)
        else:
            report["incompatible_count"] += 1
            report["summary"]["by_category"]["incompatible"].append(sid)
            for err in result.get("errors", []):
                if "Missing binding" in err:
                    bnum = err.split()[-1]
                    d = report["summary"]["issues"]["missing_bindings"]
                    d[bnum] = d.get(bnum, 0) + 1
                elif "incompatible type" in err.lower():
                    report["summary"]["issues"]["wrong_types"][sid] = err

    return report


# ---------------------------------------------------------------------------
# Generate summary markdown
# ---------------------------------------------------------------------------

def write_summary(
    audit_records: list[dict],
    before_report: dict,
    after_report: dict,
) -> None:
    fixed = [r for r in audit_records if r["status"] == "fixed"]
    manual = [r for r in audit_records if r["status"] == "needs_manual_review"]
    skipped = [r for r in audit_records if r["status"] == "skipped"]
    already_ok = [r for r in audit_records if r["status"] == "already_compatible"]

    # Count fix types
    fix_type_counts: dict[str, int] = {}
    for r in fixed:
        for fx in r["fixes_applied"]:
            key = fx.split(":")[0].strip()
            fix_type_counts[key] = fix_type_counts.get(key, 0) + 1

    before_incompatible = before_report.get("incompatible_count", "?")
    after_incompatible = after_report.get("incompatible_count", "?")
    total = before_report.get("total_shaders", len(audit_records))

    lines = [
        "# BindGroup Auto-Fix Summary",
        "",
        f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M UTC')}  ",
        f"**Tool:** `scripts/fix_bindgroups.py`",
        "",
        "## Overview",
        "",
        "| Metric | Count |",
        "| --- | --- |",
        f"| Total shaders processed | {total} |",
        f"| Incompatible **before** fix | {before_incompatible} |",
        f"| Incompatible **after** fix | {after_incompatible} |",
        f"| Shaders auto-fixed | {len(fixed)} |",
        f"| Shaders already compatible | {len(already_ok)} |",
        f"| Shaders requiring manual review | {len(manual)} |",
        f"| Shaders skipped (templates/render) | {len(skipped)} |",
        "",
        "## Fix Types Applied",
        "",
        "| Fix Type | Shaders Fixed |",
        "| --- | --- |",
    ]
    for fix_key, cnt in sorted(fix_type_counts.items(), key=lambda x: -x[1]):
        lines.append(f"| `{fix_key}` | {cnt} |")

    lines += [
        "",
        "## Auto-Fixed Shaders",
        "",
        "| Shader | Fixes Applied |",
        "| --- | --- |",
    ]
    for r in sorted(fixed, key=lambda x: x["shader_id"]):
        fixes_str = ", ".join(f"`{fx}`" for fx in r["fixes_applied"])
        lines.append(f"| `{r['shader_id']}` | {fixes_str} |")

    lines += [
        "",
        "## Shaders Requiring Manual Review",
        "",
        "These shaders could not be auto-fixed. Human intervention is needed.",
        "",
        "| Shader | Issues |",
        "| --- | --- |",
    ]
    for r in sorted(manual, key=lambda x: x["shader_id"]):
        flags_str = "; ".join(r["manual_flags"])
        lines.append(f"| `{r['shader_id']}` | {flags_str} |")

    lines += [
        "",
        "## Remaining Incompatible Shaders (post-fix)",
        "",
        "| Shader | Errors |",
        "| --- | --- |",
    ]
    for s in after_report.get("shaders", []):
        if s.get("status") == "incompatible":
            errs = "; ".join(s.get("errors", [])[:3])
            lines.append(f"| `{s['shader_id']}` | {errs} |")

    lines += [
        "",
        "---",
        "",
        "## Violation Type Reference",
        "",
        "| Violation | Auto-fixable? | Fix applied |",
        "| --- | --- | --- |",
        "| `binding_10_access: read → read_write` | ✅ Yes | Changed `<storage, read>` to `<storage, read_write>` |",
        "| `binding_12_access: <storage> → <storage, read>` | ✅ Yes | Added `, read` access qualifier |",
        "| `added_missing_bindings` | ✅ Yes | Inserted canonical stub declarations |",
        "| `uniforms_ripples_field_added` | ✅ Yes | Appended `ripples` field to Uniforms struct |",
        "| Binding 12 wrong struct type (`array<PlasmaBall, …>`) | ❌ No | Needs custom rewrite |",
        "| Uniforms struct with extra fields + missing `ripples` | ❌ No | Memory-layout conflict, manual fix |",
        "| No `@compute` entry point | ❌ No | Library/utility file |",
        "",
    ]

    SUMMARY_PATH.write_text("\n".join(lines), encoding="utf-8")
    print(f"Summary written to {SUMMARY_PATH}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    print("=" * 70)
    print("BindGroup Auto-Fix Pass")
    print("=" * 70)

    shader_files = sorted(SHADERS_DIR.glob("*.wgsl"))
    print(f"\nFound {len(shader_files)} WGSL files in {SHADERS_DIR}")

    # --- Capture BEFORE state from the existing report (or run checker) ---
    if REPORT_PATH.exists():
        with REPORT_PATH.open(encoding="utf-8") as fh:
            before_report = json.load(fh)
        print(
            f"Before state loaded from existing report "
            f"(timestamp: {before_report.get('timestamp', 'unknown')}): "
            f"{before_report.get('incompatible_count', '?')} incompatible"
        )
    else:
        print("No existing report found; running checker for before state …")
        before_report = _run_checker_inline()

    # --- Apply fixes ---
    print("\nApplying fixes …")
    audit_records: list[dict] = []
    fixed_count = 0
    manual_count = 0

    for fp in shader_files:
        record = repair_shader(fp)
        audit_records.append(record)
        if record["status"] == "fixed":
            fixed_count += 1
            print(f"  ✓ {fp.name}: {', '.join(record['fixes_applied'])}")
        elif record["status"] == "needs_manual_review":
            manual_count += 1
            print(f"  ⚠ {fp.name}: manual → {'; '.join(record['manual_flags'])}")

    print(f"\nFixed: {fixed_count}  |  Needs manual review: {manual_count}")

    # --- Re-run checker to get AFTER state ---
    print("\nRe-running compatibility checker …")
    after_report = _run_checker_inline()
    print(
        f"After state: {after_report.get('compatible_count', '?')} compatible, "
        f"{after_report.get('incompatible_count', '?')} incompatible"
    )

    # --- Write updated compatibility report ---
    REPORTS_DIR.mkdir(exist_ok=True)
    with REPORT_PATH.open("w", encoding="utf-8") as fh:
        json.dump(after_report, fh, indent=2)
    print(f"Compatibility report written to {REPORT_PATH}")

    # --- Write summary ---
    write_summary(audit_records, before_report, after_report)

    print("\n" + "=" * 70)
    print("Fix pass complete.")
    print(f"  Before incompatible: {before_report.get('incompatible_count', '?')}")
    print(f"  After  incompatible: {after_report.get('incompatible_count', '?')}")
    print(f"  Shaders auto-fixed:  {fixed_count}")
    print(f"  Manual review needed: {manual_count}")
    print("=" * 70)


if __name__ == "__main__":
    main()
