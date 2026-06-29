#!/usr/bin/env python3
"""
Phase F WGSL Audit — comprehensive shader quality audit.
Generates reports/phase-f-audit-report.json and reports/phase-f-audit-report.md.
"""

import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

SHADER_DIR = Path('/root/image_video_effects/public/shaders')
DEF_DIR = Path('/root/image_video_effects/shader_definitions')
REPORT_JSON = Path('/root/image_video_effects/reports/phase-f-audit-report.json')
REPORT_MD = Path('/root/image_video_effects/reports/phase-f-audit-report.md')

VALID_CATEGORIES = {
    'image', 'generative', 'interactive-mouse', 'distortion', 'simulation',
    'artistic', 'visual-effects', 'hybrid', 'advanced-hybrid', 'retro-glitch',
    'lighting-effects', 'geometric', 'liquid-effects', 'post-processing'
}

SKIP_NAMES = {'_hash_library', '_template_canonical_compute', '_template_shared_memory',
              '_template_workgroup_atomics', 'gen_capabilities', 'imageVideo', 'texture'}


def naga_check(path: Path) -> dict:
    tmp = '/tmp/phase-f-naga-out.wgsl'
    try:
        result = subprocess.run(
            ['naga', str(path), tmp],
            capture_output=True, text=True, timeout=30
        )
        return {
            'valid': result.returncode == 0,
            'error': result.stderr.strip() if result.returncode != 0 else ''
        }
    except Exception as e:
        return {'valid': False, 'error': str(e)}


def check_bindings(content: str) -> dict:
    issues = []
    # Check canonical 13 bindings exist
    for i in range(13):
        if not re.search(rf'@group\(0\)\s*@binding\({i}\)', content):
            issues.append(f'Missing binding {i}')
    # Check Uniforms struct fields
    uniforms = re.search(r'struct\s+Uniforms\s*\{([^}]+)\}', content, re.DOTALL)
    if not uniforms:
        issues.append('Missing Uniforms struct')
    else:
        body = uniforms.group(1)
        for field in ['config', 'zoom_config', 'zoom_params', 'ripples']:
            if field not in body:
                issues.append(f'Uniforms missing {field}')
        normalized_body = body.replace(' ', '').replace('\t', '').replace('\n', '')
        if 'ripples:array<vec4<f32>,50>' not in normalized_body:
            issues.append('ripples array size/type mismatch')
    return {'issues': issues}


def check_workgroup(content: str) -> dict:
    match = re.search(r'@workgroup_size\(([^)]+)\)', content)
    if not match:
        return {'valid': False, 'value': None, 'issues': ['No workgroup_size found']}
    parts = [p.strip() for p in match.group(1).split(',')]
    try:
        dims = [int(p) for p in parts if p]
    except ValueError:
        return {'valid': False, 'value': match.group(1), 'issues': ['Non-literal workgroup_size']}
    total = 1
    for d in dims:
        total *= d
    issues = []
    if total > 256:
        issues.append(f'Workgroup size {dims} = {total} > 256 baseline')
    if total > 1024:
        issues.append(f'Workgroup size {dims} = {total} > 1024 max')
    return {'valid': len(issues) == 0, 'value': dims, 'total': total, 'issues': issues}


def check_alpha(content: str, is_generative: bool) -> dict:
    issues = []
    # Find textureStore(writeTexture, ...) calls
    stores = re.findall(r'textureStore\(\s*writeTexture\s*,[^;]+;', content, re.DOTALL)
    hardcoded_alpha = re.search(r'vec4<f32>\([^)]*,\s*1\.0\s*\)', content) is not None
    if not is_generative and hardcoded_alpha:
        issues.append('Hardcoded alpha=1.0 in non-generative shader')
    return {'issues': issues, 'store_count': len(stores)}


def check_depth_write(content: str) -> dict:
    has_depth = 'writeDepthTexture' in content and 'textureStore(writeDepthTexture' in content
    return {'has_depth_write': has_depth, 'issues': [] if has_depth else ['Missing writeDepthTexture store']}


def check_utf8(path: Path) -> dict:
    issues = []
    raw = path.read_bytes()
    if raw.startswith(b'\xef\xbb\xbf'):
        issues.append('UTF-8 BOM at start')
    if b'\x00' in raw:
        issues.append('Null bytes in file')
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as e:
        issues.append(f'UTF-8 decode error: {e}')
        text = ''
    if '\ufffd' in text:
        issues.append('Replacement character (U+FFFD) found')
    return {'issues': issues}


def check_json(id: str) -> dict:
    issues = []
    # find json by walking categories
    json_path = None
    category = None
    for cat_dir in DEF_DIR.iterdir():
        if not cat_dir.is_dir():
            continue
        candidate = cat_dir / f'{id}.json'
        if candidate.exists():
            json_path = candidate
            category = cat_dir.name
            break
    if not json_path:
        return {'exists': False, 'category': None, 'issues': ['No JSON definition found']}
    try:
        data = json.loads(json_path.read_text())
    except json.JSONDecodeError as e:
        return {'exists': True, 'category': category, 'issues': [f'Invalid JSON: {e}']}
    if data.get('id') != id:
        issues.append('JSON id mismatch')
    effective_category = data.get('category') or category
    if effective_category not in VALID_CATEGORIES:
        issues.append(f'Invalid category: {effective_category}')
    params = data.get('parameters', [])
    for p in params:
        for key in ['id', 'name', 'default', 'min', 'max', 'step']:
            if key not in p:
                issues.append(f'Param missing {key}: {p}')
    return {'exists': True, 'category': effective_category, 'issues': issues}


def audit_shader(path: Path) -> dict:
    id = path.stem
    content = path.read_text(encoding='utf-8')
    json_info = check_json(id)
    is_generative = (
        id.startswith('gen-') or
        'generative' in content.lower() or
        json_info['category'] == 'generative'
    )

    naga = naga_check(path)
    bindings = check_bindings(content)
    workgroup = check_workgroup(content)
    alpha = check_alpha(content, is_generative)
    depth = check_depth_write(content)
    utf8 = check_utf8(path)

    all_issues = []
    all_issues.extend([f'NAGA: {naga["error"]}'] if not naga['valid'] else [])
    all_issues.extend([f'BINDING: {i}' for i in bindings['issues']])
    all_issues.extend([f'WORKGROUP: {i}' for i in workgroup['issues']])
    all_issues.extend([f'ALPHA: {i}' for i in alpha['issues']])
    all_issues.extend([f'DEPTH: {i}' for i in depth['issues']])
    all_issues.extend([f'UTF8: {i}' for i in utf8['issues']])
    all_issues.extend([f'JSON: {i}' for i in json_info['issues']])

    severity = 'PASS'
    if not naga['valid'] or bindings['issues'] or workgroup.get('total', 0) > 1024 or depth['issues']:
        severity = 'CRITICAL'
    elif workgroup.get('total', 0) > 256 or alpha['issues'] or json_info['issues']:
        severity = 'WARNING'
    elif utf8['issues']:
        severity = 'WARNING'

    return {
        'id': id,
        'size_bytes': path.stat().st_size,
        'naga_valid': naga['valid'],
        'workgroup': workgroup.get('value'),
        'workgroup_total': workgroup.get('total'),
        'has_depth_write': depth['has_depth_write'],
        'json_category': json_info['category'],
        'json_exists': json_info['exists'],
        'severity': severity,
        'issues': all_issues,
        'issue_count': len(all_issues)
    }


def main():
    shaders = sorted(SHADER_DIR.glob('*.wgsl'))
    results = []
    for i, path in enumerate(shaders, 1):
        if path.stem in SKIP_NAMES:
            continue
        if i % 100 == 0:
            print(f'  {i}/{len(shaders)}: {path.stem}')
        results.append(audit_shader(path))

    total = len(results)
    critical = sum(1 for r in results if r['severity'] == 'CRITICAL')
    warning = sum(1 for r in results if r['severity'] == 'WARNING')
    pass_count = sum(1 for r in results if r['severity'] == 'PASS')
    naga_fail = sum(1 for r in results if not r['naga_valid'])

    report = {
        'timestamp': datetime.now().isoformat(),
        'total_shaders': total,
        'summary': {
            'pass': pass_count,
            'warning': warning,
            'critical': critical,
            'naga_failures': naga_fail
        },
        'shaders': results
    }

    REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
    REPORT_JSON.write_text(json.dumps(report, indent=2))

    # Build markdown report
    md = f"""# Phase F WGSL Audit Report

**Timestamp:** {report['timestamp']}
**Total shaders audited:** {total}

## Summary

| Severity | Count |
|----------|------:|
| ✅ PASS | {pass_count} |
| ⚠️ WARNING | {warning} |
| 🚨 CRITICAL | {critical} |
| Naga failures | {naga_fail} |

## Top Issues by Category

"""

    # Group issues
    issue_categories = {}
    for r in results:
        for issue in r['issues']:
            cat = issue.split(':')[0]
            issue_categories.setdefault(cat, []).append((r['id'], issue))

    for cat, items in sorted(issue_categories.items(), key=lambda x: -len(x[1])):
        md += f"### {cat} ({len(items)} occurrences)\n\n"
        for sid, issue in items[:10]:
            md += f"- `{sid}`: {issue}\n"
        if len(items) > 10:
            md += f"- ... and {len(items) - 10} more\n"
        md += "\n"

    md += "## Critical Issues (fix first)\n\n"
    crits = [r for r in results if r['severity'] == 'CRITICAL']
    for r in sorted(crits, key=lambda x: -x['issue_count'])[:30]:
        md += f"### `{r['id']}` ({r['issue_count']} issues)\n"
        for issue in r['issues']:
            md += f"- {issue}\n"
        md += "\n"

    md += "## Full Shader List\n\n"
    md += "| Shader | Severity | Issues | Naga | Workgroup | Depth | JSON Category |\n"
    md += "|--------|----------|--------|------|-----------|-------|---------------|\n"
    for r in sorted(results, key=lambda x: (x['severity'] != 'CRITICAL', x['severity'] != 'WARNING', -x['issue_count'])):
        md += f"| `{r['id']}` | {r['severity']} | {r['issue_count']} | {'OK' if r['naga_valid'] else 'FAIL'} | {r['workgroup']} | {'Yes' if r['has_depth_write'] else 'No'} | {r['json_category'] or '—'} |\n"

    REPORT_MD.write_text(md)
    print(f"Audit complete: {total} shaders")
    print(f"  PASS: {pass_count}, WARNING: {warning}, CRITICAL: {critical}")
    print(f"  Reports: {REPORT_JSON}, {REPORT_MD}")


if __name__ == '__main__':
    main()
