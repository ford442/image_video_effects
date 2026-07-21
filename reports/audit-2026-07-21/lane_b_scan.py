#!/usr/bin/env python3
"""Lane B workgroup audit scanner (read-only over public/shaders)."""
import json, re, sys
from pathlib import Path

ROOT = Path("/root/image_video_effects")
SHADERS = ROOT / "public" / "shaders"
sys.path.insert(0, str(ROOT / "scripts"))
from bindgroup_checker import check_workgroup_size_convention  # noqa

# Mirror of src/renderer/ShaderCompilation.ts parseWorkgroupSize
def parse_workgroup_size_ts(src: str):
    m = re.search(r'@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)', src)
    if m:
        return (int(m.group(1)), int(m.group(2))), "primary"
    idx = src.find('@compute')
    if idx != -1:
        m2 = re.search(r'@workgroup_size\(\s*(\d+)\s*,\s*(\d+)', src[idx:])
        if m2:
            return (int(m2.group(1)), int(m2.group(2))), "fallback"
    return (8, 8), "default"

def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.DOTALL)
    src = re.sub(r'//[^\n]*', ' ', src)
    return src

# Find the ACTUAL workgroup size of the entry point named `main`
def main_entry_wg(src):
    s = strip_comments(src)
    # all entry points
    entries = re.findall(r'@compute\s*@workgroup_size\s*\(([^)]*)\)\s*fn\s+(\w+)', s)
    result = {}
    for args, name in entries:
        nums = [a.strip() for a in args.split(',')]
        result[name] = nums
    return result

WG_ATTR = re.compile(r'@workgroup_size\s*\(\s*(\d+)\s*(?:,\s*(\d+)\s*)?(?:,\s*(\d+)\s*)?\)')

report = {"histogram": {}, "multi_entry": [], "parser_mismatch": [],
          "convention_violations": [], "missing_bounds_guard": [],
          "workgroup_memory": [], "barrier_findings": []}

for f in sorted(SHADERS.glob("*.wgsl")):
    src = f.read_text(encoding="utf-8", errors="replace")
    entries = main_entry_wg(src)
    if not entries:
        continue
    parsed, how = parse_workgroup_size_ts(src)
    main_dims = entries.get("main")
    key = None
    for name, dims in entries.items():
        k = tuple(dims)
        report["histogram"][str(k)] = report["histogram"].get(str(k), 0) + 1
    if len(entries) > 1:
        report["multi_entry"].append({"file": f.name, "entries": entries,
                                      "parser_returns": parsed})
    # parser mismatch: what the TS parser returns vs what `main` declares
    if main_dims:
        mx = int(main_dims[0]) if main_dims[0].isdigit() else None
        my = int(main_dims[1]) if len(main_dims) > 1 and main_dims[1].isdigit() else 1
        if mx is not None and (mx, my) != parsed:
            report["parser_mismatch"].append({
                "file": f.name, "main_declares": main_dims,
                "parser_returns": parsed, "parse_path": how})
    else:
        report["parser_mismatch"].append({
            "file": f.name, "main_declares": None,
            "entries": entries, "parser_returns": parsed,
            "note": "no `main` entry point; renderer compiles entryPoint:'main' -> compile fails or wrong kernel"})

    # convention check
    for iss in check_workgroup_size_convention(src):
        report["convention_violations"].append({"file": f.name, **iss})

    # bounds guard check for 2D per-pixel shaders (non 1D)
    if main_dims and len(main_dims) >= 2 and main_dims[1] not in ("1",):
        body_start = src.find('fn main')
        body = src[body_start:] if body_start != -1 else src
        guard = re.search(r'(global_id|gid|coord|id)\.(x|y)\s*>=\s*(u32\()?(width|height|dim|res|resolution|tex)', body) \
            or re.search(r'if\s*\([^)]*\b(x|y)\b[^)]*>=[^)]*\b(textureDimensions|dims|dim|resolution|resX|resY|width|height)', body) \
            or re.search(r'inBounds', body) \
            or re.search(r'(>=|>)\s*(textureDimensions|dims\.)', body)
        stores = 'textureStore' in body
        if stores and not guard:
            report["missing_bounds_guard"].append({
                "file": f.name, "wg": main_dims,
                "note": "textureStore present but no global_id bounds guard detected"})

    # var<workgroup> memory estimate
    s = strip_comments(src)
    total = 0
    decls = []
    for m in re.finditer(r'var<workgroup>\s+(\w+)\s*:\s*([^;]+);', s):
        name, ty = m.group(1), m.group(2).strip()
        # crude size estimation
        def type_size(t):
            # nested arrays: array<T, N> or array<array<...>>
            mm = re.match(r'array<(.+),\s*(\d+)\s*>$', t)
            if mm:
                inner, n = mm.group(1).strip(), int(mm.group(2))
                return n * type_size(inner)
            mm = re.match(r'array<(.+)>$', t)
            if mm:
                return type_size(mm.group(1))
            t = t.replace('atomic<', '').rstrip('>')
            if t in ('f32', 'u32', 'i32'):
                return 4
            vm = re.match(r'vec(\d)<f32>', t)
            if vm:
                return int(vm.group(1)) * 4
            return 4
        try:
            sz = type_size(ty)
        except Exception:
            sz = -1
        total += max(sz, 0)
        decls.append({"name": name, "type": ty, "bytes": sz})
    if decls:
        report["workgroup_memory"].append({"file": f.name, "total_bytes": total,
                                           "over_16kb": total > 16384, "decls": decls})

    # barrier in non-uniform control flow: line-based heuristic
    lines = src.splitlines()
    stack = []  # (indent, is_uniform_branch)
    for i, line in enumerate(lines, 1):
        if 'workgroupBarrier' in line or 'storageBarrier' in line:
            # look backwards for enclosing if/loop with lid/gid dependence
            indent = len(line) - len(line.lstrip())
            # find nearest enclosing brace blocks by scanning up
            depth = 0
            suspect = None
            for j in range(i - 2, -1, -1):
                l2 = lines[j]
                depth += l2.count('}') - l2.count('{')
                if depth > 0:
                    hdr = l2.strip()
                    if re.match(r'(if|for|loop|while)\b', hdr):
                        cond = hdr
                        # uniform if condition depends only on builtins uniform across wg? lid.x is NOT uniform
                        if re.search(r'(local_invocation_id|lid\b|gl_LocalInvocationID)', cond):
                            suspect = (j + 1, hdr)
                        break
            if suspect:
                report["barrier_findings"].append({
                    "file": f.name, "line": i,
                    "barrier": line.strip(),
                    "enclosing_nonuniform_branch_line": suspect[0],
                    "branch": suspect[1][:120]})

out = ROOT / "reports" / "audit-2026-07-21" / "lane-b-workgroups.json"
out.write_text(json.dumps(report, indent=2))
print("histogram:", json.dumps(report["histogram"], indent=1))
print("multi_entry:", len(report["multi_entry"]))
print("parser_mismatch:", len(report["parser_mismatch"]))
print("convention_violations:", len(report["convention_violations"]))
print("missing_bounds_guard:", len(report["missing_bounds_guard"]))
print("workgroup_memory over 16KB:", [w["file"] for w in report["workgroup_memory"] if w["over_16kb"]])
print("barrier findings:", len(report["barrier_findings"]))
