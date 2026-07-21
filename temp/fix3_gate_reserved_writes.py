#!/usr/bin/env python3
"""Fix Agent 3: gate ungated reserved extraBuffer[0..4] writes with a
single-invocation guard `if (<gid>.x == 0u && <gid>.y == 0u) { ... }`.

Only touches literal writes to indices 0..4 that are NOT already inside a
single-invocation gate. Groups contiguous write lines into one gate block.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path("/root/image_video_effects")
SHADERS = ROOT / "public" / "shaders"

WRITE_RE = re.compile(r'^(\s*)extraBuffer\[\s*([0-4])\s*\]\s*=(?!=)')

# Gate patterns (same family the checker accepts)
GATE_PAIR_RE = re.compile(
    r'(\w+)\s*\.\s*x\s*==\s*0u?\s*&&\s*\1\s*\.\s*y\s*==\s*0u?|'
    r'(\w+)\s*\.\s*y\s*==\s*0u?\s*&&\s*\2\s*\.\s*x\s*==\s*0u?|'
    r'all\s*\(\s*\w+\s*\.\s*xy\s*==\s*vec2\s*(?:<u32>)?\s*\(\s*0u?'
)


def enclosing_gated(lines, idx):
    """True if line idx is inside an if-block whose condition is a
    single-invocation gate (scan backwards for nearest unmatched 'if')."""
    depth = 0
    for j in range(idx, -1, -1):
        line = lines[j]
        depth += line.count('}') - line.count('{')
        if 'if' in line and GATE_PAIR_RE.search(line):
            # gate opens a block below it (or same line) that has not closed
            if depth < line.count('{'):
                return True
        # isLeader-style: check gate vars
        m = re.search(r'if\s*\(\s*(\w+)\s*\)', line)
        if m and depth < line.count('{'):
            var = m.group(1)
            src = '\n'.join(lines)
            if re.search(r'\b(?:let|var)\s+' + re.escape(var) +
                         r'\s*(?::\s*bool\s*)?=\s*[^;]*==\s*0u?[^;]*&&[^;]*==\s*0u?',
                         src):
                return True
    return False


def fix_file(path: Path):
    lines = path.read_text(encoding='utf-8').splitlines()
    src = '\n'.join(lines)
    m = re.search(r'@builtin\(global_invocation_id\)\s+(\w+)', src)
    if not m:
        return 0, 'no global_invocation_id'
    gid = m.group(1)

    out = []
    n_writes = 0
    i = 0
    while i < len(lines):
        wm = WRITE_RE.match(lines[i])
        if wm and not enclosing_gated(lines, i):
            indent = wm.group(1)
            group = []
            while i < len(lines) and WRITE_RE.match(lines[i]):
                group.append(lines[i])
                n_writes += 1
                i += 1
            out.append(f'{indent}if ({gid}.x == 0u && {gid}.y == 0u) {{')
            out.extend(f'{indent}  {g.strip()}' for g in group)
            out.append(f'{indent}}}')
        else:
            out.append(lines[i])
            i += 1
    if n_writes:
        path.write_text('\n'.join(out) + '\n', encoding='utf-8')
    return n_writes, None


def main():
    data = json.load(open(ROOT / 'reports/audit-2026-07-21/lane-c-extrabuf.json'))
    files = sorted({f for f, _, _ in data['ungated']})
    total = 0
    for f in files:
        n, err = fix_file(SHADERS / f)
        print(f'{f}: gated {n} write(s)' + (f'  [SKIP: {err}]' if err else ''))
        total += n
    print(f'TOTAL gated writes: {total}')


if __name__ == '__main__':
    main()
