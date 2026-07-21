#!/usr/bin/env python3
"""Pass 2: authoritative let-scan (reuse v2 scanner), OOB analysis, unused-binding aggregation."""
import re, os, sys, json, glob, collections, importlib.util

SHADER_DIR = "/root/image_video_effects/public/shaders"
spec = importlib.util.spec_from_file_location("v2", "/root/image_video_effects/scripts/scan_immutable_lets_v2.py")
v2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)

def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.DOTALL)
    src = re.sub(r'//[^\n]*', ' ', src)
    return src

BINDING_RE = re.compile(r'@group\(\s*0\s*\)\s*@binding\(\s*(\d+)\s*\)\s*var\s*(<[a-z_,\s]+>)?\s*(\w+)\s*:\s*([^;]+);')

let_results = {}
unused_by_binding = collections.Counter()
unused_detail = {}
oob_missing_guard = []       # files with textureStore but no dims guard at all
oob_neighbor_loads = collections.defaultdict(list)  # textureLoad with offset, check clamp
oob_store_clampless = collections.defaultdict(list)
loop_detail = {}

files = sorted(glob.glob(os.path.join(SHADER_DIR, "*.wgsl")))
for path in files:
    name = os.path.basename(path)
    with open(path, encoding='utf-8') as f:
        raw = f.read()
    code = strip_comments(raw)

    # 4. authoritative let scan
    errs = v2.find_immutable_let_errors(path)
    errs = [e for e in errs if 'error' not in e]
    if errs:
        let_results[name] = errs

    # 5. unused bindings aggregated
    bindings = {int(m.group(1)): m.group(3) for m in BINDING_RE.finditer(code)}
    body = BINDING_RE.sub(' ', code)
    for b, vname in bindings.items():
        if not re.search(r'\b' + re.escape(vname) + r'\b', body):
            unused_by_binding[b] += 1
            unused_detail.setdefault(name, []).append((b, vname))

    # 2. OOB: guard presence
    has_dims_guard = bool(re.search(r'textureDimensions', code)) and bool(
        re.search(r'clamp\s*\(|any\s*\([^)]*>=\s*(dims|dimsI)|all\s*\([^)]*<\s*(dims|dimsI)|if\s*\([^)]*>=\s*(dims|dimsI)', code))
    stores = list(re.finditer(r'textureStore\s*\(\s*(\w+)\s*,\s*([^,]+),', code))
    loads = list(re.finditer(r'textureLoad\s*\(\s*(\w+)\s*,\s*([^,)]+)', code))
    if stores and not has_dims_guard:
        oob_missing_guard.append(name)
    # neighbor loads with +/- offsets
    for m in loads:
        coord_expr = m.group(2)
        if re.search(r'[+\-]\s*(vec2|\d|offset|dx|dy|i\b|j\b|x\b|y\b)', coord_expr) or '+' in coord_expr or '-' in coord_expr:
            # check clamp near usage
            ctx = code[max(0, m.start()-300):m.end()+50]
            if 'clamp' not in ctx and 'textureDimensions' not in ctx and '%' not in coord_expr:
                oob_neighbor_loads[name].append(coord_expr.strip()[:80])
    for m in stores:
        coord_expr = m.group(2).strip()
        if re.search(r'[+\-]', coord_expr):
            ctx = code[max(0, m.start()-300):m.end()+30]
            if 'clamp' not in ctx:
                oob_store_clampless[name].append(coord_expr[:80])

    # 6. loop detail: loop{} blocks without break, large for-bounds
    for m in re.finditer(r'loop\s*\{', code):
        # crude: find matching close by brace counting
        depth, i = 0, m.end()-1
        start = i
        while i < len(code):
            if code[i] == '{': depth += 1
            elif code[i] == '}':
                depth -= 1
                if depth == 0: break
            i += 1
        block = code[start:i]
        has_break = 'break' in block or 'return' in block or 'continue' in block
        has_continuing = 'continuing' in block
        if not has_break:
            loop_detail.setdefault(name, []).append('loop{} WITHOUT break/return/continuing (possible infinite)')
        elif not has_continuing:
            loop_detail.setdefault(name, []).append('loop{} with break but no continuing clause (style/validation risk)')
    for m in re.finditer(r'for\s*\([^;]*;[^;<]*<\s*(\d+)\s*;', code):
        n = int(m.group(1))
        if n > 500:
            loop_detail.setdefault(name, []).append(f'for-loop fixed bound {n}')
    for m in re.finditer(r'@workgroup_size\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', code):
        x, y, z = map(int, m.groups())
        if x*y*z > 256:
            loop_detail.setdefault(name, []).append(f'workgroup_size({x},{y},{z}) = {x*y*z} > 256 invocations')

out = {
 'let_regressions': {k: [{'var': e['var_name'], 'decl': e['decl_line'], 'err': e['error_line'], 'code': e['error_code'][:120]} for e in v] for k, v in let_results.items()},
 'unused_by_binding': dict(sorted(unused_by_binding.items())),
 'unused_files_all13': [k for k, v in unused_detail.items() if len(v) >= 8],
 'oob_missing_dims_guard': oob_missing_guard,
 'oob_neighbor_loads': {k: list(set(v))[:6] for k, v in oob_neighbor_loads.items()},
 'oob_store_clampless': {k: list(set(v))[:6] for k, v in oob_store_clampless.items()},
 'loop_detail': loop_detail,
}
with open('/root/image_video_effects/reports/audit-2026-07-21/lane-c-pass2.json', 'w') as f:
    json.dump(out, f, indent=1)
print("let regression files:", len(let_results), "errors:", sum(len(v) for v in let_results.values()))
print("unused by binding:", dict(sorted(unused_by_binding.items())))
print("files w/ >=8 unused bindings:", len(out['unused_files_all13']))
print("oob missing dims guard:", len(oob_missing_guard))
print("oob neighbor loads:", len(oob_neighbor_loads))
print("oob store clampless:", len(oob_store_clampless))
print("loop files:", len(loop_detail))
