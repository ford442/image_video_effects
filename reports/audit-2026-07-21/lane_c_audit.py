#!/usr/bin/env python3
"""
Lane C pattern audit: scans all public/shaders/*.wgsl for common WGSL/WebGPU
mistakes. READ-ONLY with respect to shader files; writes JSON results only.
"""
import re, os, json, glob, collections

SHADER_DIR = "/root/image_video_effects/public/shaders"
OUT = "/root/image_video_effects/reports/audit-2026-07-21/lane-c-data.json"

CANONICAL = {  # binding -> expected canonical var names (any name allowed, but we track refs)
    0: "sampler", 1: "texture_2d<f32>", 2: "texture_storage_2d<rgba32float, write>",
    3: "uniform Uniforms", 4: "texture_2d<f32>", 5: "sampler",
    6: "texture_storage_2d<r32float, write>", 7: "texture_storage_2d<rgba32float, write>",
    8: "texture_storage_2d<rgba32float, write>", 9: "texture_2d<f32>",
    10: "storage read_write array<f32>", 11: "sampler_comparison",
    12: "storage read array<vec4<f32>>", 13: "texture_2d_array<f32> (opt-in)",
}
BINDING_RE = re.compile(r'@group\(\s*(\d+)\s*\)\s*@binding\(\s*(\d+)\s*\)\s*var\s*(<[a-z_,\s]+>)?\s*(\w+)\s*:\s*([^;]+);')

def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.DOTALL)
    src = re.sub(r'//[^\n]*', ' ', src)
    return src

results = {}

# ---------- category accumulators ----------
cat1_div = collections.Counter()           # denominator token -> count
cat1_files = collections.defaultdict(list) # file -> [(line, expr)]
cat2_oob_files = collections.defaultdict(list)
cat3_implicitsample_files = collections.defaultdict(list)
cat3_divergent = collections.defaultdict(list)
cat4_let = collections.defaultdict(list)
cat5_noncanonical = collections.defaultdict(list)
cat5_unused = collections.defaultdict(list)
cat6_loops = collections.defaultdict(list)
cat7_rmw = collections.defaultdict(list)
cat8_nan = collections.defaultdict(list)
cat9_glsl = collections.defaultdict(list)

DIV_RE = re.compile(r'/\s*([A-Za-z_][\w\.\[\]]*)')
GUARDED_DENOM = re.compile(r'/\s*(max|abs|clamp|select)\s*\(')
EPSILON_ADD = re.compile(r'/\s*\([^)]*[+\-]\s*(1e-?\d|0\.0\d+)')

files = sorted(glob.glob(os.path.join(SHADER_DIR, "*.wgsl")))
for path in files:
    name = os.path.basename(path)
    with open(path, encoding='utf-8') as f:
        raw = f.read()
    code = strip_comments(raw)
    lines = code.split('\n')
    rawlines = raw.split('\n')
    is_compute = '@compute' in code
    is_render = '@vertex' in code or '@fragment' in code

    # ---- bindings ----
    bindings = {}  # num -> varname
    for m in BINDING_RE.finditer(code):
        g, b, sc, vname, vtype = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4), m.group(5)
        if g != 0:
            cat5_noncanonical[name].append(f"group({g}) binding({b}) {vname} (nonzero group)")
            continue
        bindings[b] = vname
        if b > 13:
            cat5_noncanonical[name].append(f"binding({b}) {vname}: {vtype.strip()} (>13, layout only has 14 entries)")

    # unused bindings (declared canonical but never referenced past declaration)
    body = BINDING_RE.sub(' ', code)
    for b, vname in bindings.items():
        if not re.search(r'\b' + re.escape(vname) + r'\b', body):
            cat5_unused[name].append(f"binding({b}) {vname}")

    # ---- per-line pattern scans ----
    for i, line in enumerate(lines, 1):
        ls = line.strip()
        if not ls:
            continue

        # 1. division by zero risk
        if '/' in ls and not ls.startswith('@'):
            for m in DIV_RE.finditer(ls):
                denom = m.group(1)
                # skip obvious safe denominators
                if denom in ('f32', 'i32', 'u32', 'vec2', 'vec3', 'vec4', 'dims', 'dimsF',
                             'resolution', 'size', 'dimsI', 'dimsf'):
                    continue
                if re.match(r'^vec[234]', denom):
                    continue
                # guarded?
                if GUARDED_DENOM.search(ls):
                    continue
                if EPSILON_ADD.search(ls):
                    continue
                # literal-ish denominators
                if denom[0].isdigit():
                    continue
                cat1_div[denom.split('.')[0].split('[')[0]] += 1
                cat1_files[name].append((i, ls[:160]))
                break  # one record per line is enough

        # 2. textureLoad/textureStore OOB
        if re.search(r'texture(Store|Load)\s*\(', ls):
            cat2_oob_files  # populated in second pass (needs context)

        # 3. textureSample with implicit LOD in compute = hard error
        if re.search(r'\btextureSample\s*\(', ls):
            if is_compute:
                cat3_implicitsample_files[name].append((i, ls[:140]))
            else:
                cat3_divergent[name].append((i, ls[:140]))

        # 6. loop forms
        if re.search(r'\bloop\s*\{', ls):
            cat6_loops[name].append((i, 'loop{}: ' + ls[:120]))
        m = re.search(r'for\s*\([^;]*;[^;]*<\s*(\d+)\s*;', ls)
        if m and int(m.group(1)) > 500:
            cat6_loops[name].append((i, f'for-loop bound {m.group(1)}: ' + ls[:120]))

        # 8. NaN hazards
        if re.search(r'\bpow\s*\(', ls) and 'pow(abs(' not in ls.replace(' ', ''):
            if not re.search(r'pow\s*\(\s*(abs|max|clamp)\s*\(', ls.replace(' ', '')):
                cat8_nan[name].append((i, 'pow: ' + ls[:140]))
        if re.search(r'\bsqrt\s*\(', ls):
            if not re.search(r'sqrt\s*\(\s*(abs|max|clamp)\s*\(', ls.replace(' ', '')):
                cat8_nan[name].append((i, 'sqrt: ' + ls[:140]))
        if re.search(r'\blog\s*\(', ls) and not re.search(r'log\s*\(\s*(abs|max)', ls.replace(' ', '')):
            cat8_nan[name].append((i, 'log: ' + ls[:140]))
        if re.search(r'\bnormalize\s*\(', ls):
            cat8_nan[name].append((i, 'normalize: ' + ls[:140]))

        # 9. GLSL-isms (code only, comments stripped)
        for g in ('gl_FragCoord', 'gl_FragColor', 'texture2D(', '#version', 'gl_Position'):
            if g in ls:
                cat9_glsl[name].append((i, ls[:140]))

    # ---- 4. let reassignment regression (scope-light heuristic) ----
    # collect let declarations, then look for reassignment of that identifier
    let_decls = set(re.findall(r'\blet\s+([A-Za-z_]\w*)\s*[:=]', code))
    for v in let_decls:
        # reassignment: v = / v += / v -= / v *= / v /= (not ==, <=, >=, !=)
        if re.search(r'\b' + re.escape(v) + r'\s*(\+|-|\*|/|%)?=[^=]', code):
            # exclude the declaration line itself: check occurrences after decl
            decl_m = re.search(r'\blet\s+' + re.escape(v) + r'\b[^;]*;', code)
            rest = code[decl_m.end():] if decl_m else code
            if re.search(r'\b' + re.escape(v) + r'\s*(\+|-|\*|/|%)?=[^=]', rest):
                cat4_let[name].append(v)

    # ---- 7. extraBuffer read-modify-write / writes ----
    for m in re.finditer(r'\bextraBuffer\s*\[([^\]]+)\]\s*([+\-*/]?=)', code):
        idx, op = m.group(1).strip(), m.group(2)
        ctx = code[max(0, m.start()-200):m.end()+120].replace('\n', ' ')
        cat7_rmw[name].append(f"extraBuffer[{idx}] {op} ... {ctx[:150]}")

json_out = {
    'total_files': len(files),
    'cat1_top_denominators': cat1_div.most_common(40),
    'cat1_file_counts': sorted(((k, len(v)) for k, v in cat1_files.items()), key=lambda x: -x[1])[:60],
    'cat1_samples': {k: v[:5] for k, v in sorted(cat1_files.items(), key=lambda x: -len(x[1]))[:25]},
    'cat3_implicit_sample_compute': {k: v[:6] for k, v in cat3_implicitsample_files.items()},
    'cat4_let_regressions': {k: v for k, v in cat4_let.items()},
    'cat5_noncanonical_bindings': dict(cat5_noncanonical),
    'cat5_unused_counts': sorted(((k, len(v)) for k, v in cat5_unused.items()), key=lambda x: -x[1]),
    'cat5_unused_detail': dict(cat5_unused),
    'cat6_loops': {k: v[:8] for k, v in cat6_loops.items()},
    'cat7_rmw': {k: v[:8] for k, v in cat7_rmw.items()},
    'cat8_nan_counts': sorted(((k, len(v)) for k, v in cat8_nan.items()), key=lambda x: -x[1])[:80],
    'cat8_samples': {k: v[:6] for k, v in sorted(cat8_nan.items(), key=lambda x: -len(x[1]))[:30]},
    'cat9_glsl': dict(cat9_glsl),
}
with open(OUT, 'w') as f:
    json.dump(json_out, f, indent=1)
print("files:", len(files))
print("cat1 files:", len(cat1_files), "total divs:", sum(cat1_div.values()))
print("cat3 files:", len(cat3_implicitsample_files))
print("cat4 files:", len(cat4_let))
print("cat5 noncanonical:", len(cat5_noncanonical), "unused:", len(cat5_unused))
print("cat6 files:", len(cat6_loops))
print("cat7 files:", len(cat7_rmw))
print("cat8 files:", len(cat8_nan))
print("cat9 files:", len(cat9_glsl))
