#!/usr/bin/env python3
"""
Aggregation Agent for Shader Validation Swarm
Combines all 4 agent reports into a master validation report
"""

import json
from datetime import datetime
from collections import defaultdict

# Load all reports
print("Loading reports...")

with open('/root/image_video_effects/reports/wgsl_syntax_report.json', 'r') as f:
    syntax_report = json.load(f)

with open('/root/image_video_effects/reports/bindgroup_compatibility_report.json', 'r') as f:
    bindgroup_report = json.load(f)

with open('/root/image_video_effects/reports/runtime_errors_report.json', 'r') as f:
    runtime_report = json.load(f)

with open('/root/image_video_effects/reports/param_validation_report.json', 'r') as f:
    param_report = json.load(f)

# Build lookup dictionaries
syntax_by_id = {s['shader_id']: s for s in syntax_report['shaders']}
bindgroup_by_id = {s['shader_id']: s for s in bindgroup_report['shaders']}
runtime_by_id = {s['shader_id']: s for s in runtime_report['shaders']}
param_by_id = {s['shader_id']: s for s in param_report['shaders']}

# Collect all shader IDs
all_shader_ids = set(syntax_by_id.keys()) | set(bindgroup_by_id.keys()) | set(runtime_by_id.keys()) | set(param_by_id.keys())
print(f"Total unique shaders: {len(all_shader_ids)}")

# Categorize issues
CRITICAL_ISSUES = ['missing_write', 'invalid_binding', 'missing_builtin', 'syntax_error']
HIGH_ISSUES = ['missing_depth_write', 'incompatible_bindings', 'wrong_binding_type']
MEDIUM_ISSUES = ['workgroup_size_mismatch', 'division_by_zero', 'array_bounds', 'missing_params']
LOW_ISSUES = ['unused_param', 'unconfigured_param', 'style_issue', 'naming_mismatch']

def classify_priority(shader_id):
    """Classify shader priority based on all reports"""
    issues = []
    agents = []
    
    # Check syntax report
    if shader_id in syntax_by_id:
        s = syntax_by_id[shader_id]
        if s.get('status') == 'error':
            agents.append('syntax')
            for e in s.get('errors', []):
                issues.append(('critical', e))
        for w in s.get('warnings', []):
            if 'Workgroup size' in w:
                issues.append(('medium', w))
            elif 'Missing binding' in w:
                issues.append(('high', w))
    
    # Check bindgroup report
    if shader_id in bindgroup_by_id:
        s = bindgroup_by_id[shader_id]
        if s.get('status') == 'incompatible':
            agents.append('bindgroup')
            for e in s.get('errors', []):
                issues.append(('critical' if 'Missing binding' in e else 'high', e))
        if s.get('missing_bindings'):
            issues.append(('high', f"Missing bindings: {s['missing_bindings']}"))
    
    # Check runtime report
    if shader_id in runtime_by_id:
        s = runtime_by_id[shader_id]
        severity = s.get('severity', 'clean')
        if severity in ['critical', 'error']:
            agents.append('runtime')
        for err in s.get('potential_runtime_errors', []):
            err_type = err.get('type', '')
            desc = err.get('description', '')
            if err_type in ['missing_write', 'invalid_binding', 'missing_builtin']:
                issues.append(('critical', desc))
            elif err_type == 'missing_depth_write':
                issues.append(('medium', desc))
            elif err_type in ['division_by_zero', 'array_bounds']:
                issues.append(('medium', desc))
    
    # Check param report
    if shader_id in param_by_id:
        s = param_by_id[shader_id]
        for issue in s.get('issues', []):
            issue_type = issue.get('type', '')
            desc = issue.get('description', '')
            if issue_type == 'nonstandard_workgroup_size':
                issues.append(('medium', desc))
            elif issue_type == 'unused_param':
                issues.append(('low', desc))
            elif issue_type == 'unconfigured_param':
                issues.append(('low', desc))
    
    # Determine overall priority
    priority_levels = [p for p, _ in issues]
    if 'critical' in priority_levels:
        overall = 'critical'
    elif 'high' in priority_levels:
        overall = 'high'
    elif 'medium' in priority_levels:
        overall = 'medium'
    elif 'low' in priority_levels:
        overall = 'low'
    else:
        overall = 'clean'
    
    return {
        'issues': issues,
        'agents': list(set(agents)),
        'priority': overall
    }

def get_recommended_fix(issues):
    """Generate recommended fix based on issues"""
    if not issues:
        return "No fixes needed"
    
    critical_fixes = []
    for priority, desc in issues:
        if 'missing_write' in desc.lower():
            critical_fixes.append("Add textureStore(writeTexture, global_id.xy, color) at end of main()")
        elif 'invalid_binding' in desc.lower():
            critical_fixes.append("Remove or remap binding 13+ to valid range 0-12")
        elif 'missing_builtin' in desc.lower():
            critical_fixes.append("Add @builtin(global_invocation_id) to main function parameter")
        elif 'missing_depth_write' in desc.lower():
            critical_fixes.append("Add textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0))")
        elif 'workgroup' in desc.lower():
            critical_fixes.append("Change @workgroup_size to (8, 8, 1)")
    
    return '; '.join(critical_fixes[:2]) if critical_fixes else "Review warnings"

# Process all shaders
print("Processing shaders...")
shaders_by_priority = {'critical': [], 'high': [], 'medium': [], 'low': [], 'clean': []}
common_issues = defaultdict(list)
common_issues['syntax_errors'] = []  # Ensure this key exists
by_category = defaultdict(lambda: {'total': 0, 'critical': 0, 'high': 0, 'medium': 0, 'low': 0, 'clean': 0})
error_types = defaultdict(int)

for shader_id in all_shader_ids:
    result = classify_priority(shader_id)
    priority = result['priority']
    
    # Get file path
    file_path = f"public/shaders/{shader_id}.wgsl"
    if shader_id in syntax_by_id:
        file_path = syntax_by_id[shader_id].get('file', file_path)
    
    # Extract issue descriptions
    issue_list = [desc for _, desc in result['issues']]
    
    # Determine category from param report
    category = 'unknown'
    if shader_id in param_by_id:
        json_file = param_by_id[shader_id].get('json_file', '')
        if 'advanced-hybrid' in json_file:
            category = 'advanced-hybrid'
        elif 'artistic' in json_file:
            category = 'artistic'
        elif 'generative' in json_file:
            category = 'generative'
        elif 'interactive-mouse' in json_file:
            category = 'interactive-mouse'
        elif 'distortion' in json_file:
            category = 'distortion'
        elif 'simulation' in json_file:
            category = 'simulation'
        elif 'visual-effects' in json_file:
            category = 'visual-effects'
        elif 'lighting-effects' in json_file:
            category = 'lighting-effects'
        elif 'geometric' in json_file:
            category = 'geometric'
        elif 'retro-glitch' in json_file:
            category = 'retro-glitch'
        elif 'liquid-effects' in json_file:
            category = 'liquid-effects'
        elif 'hybrid' in json_file:
            category = 'hybrid'
        elif 'image' in json_file:
            category = 'image'
    
    # Build shader entry
    entry = {
        'shader_id': shader_id,
        'file': file_path,
        'issues': issue_list[:5],  # Top 5 issues
        'agents_flagged': result['agents'],
        'recommended_fix': get_recommended_fix(result['issues'])
    }
    
    shaders_by_priority[priority].append(entry)
    by_category[category]['total'] += 1
    by_category[category][priority] += 1
    
    # Track common issues
    for p, desc in result['issues']:
        desc_lower = desc.lower()
        if 'missing_write' in desc_lower or 'does not call texturestore' in desc_lower:
            common_issues['missing_texture_store'].append(shader_id)
            error_types['missing_write'] += 1
        if 'invalid_binding' in desc_lower or "binding 13" in desc_lower or "binding doesn't exist" in desc_lower:
            common_issues['invalid_bindings'].append(shader_id)
            error_types['invalid_binding'] += 1
        if 'workgroup' in desc_lower and 'size' in desc_lower:
            common_issues['workgroup_size_mismatch'].append(shader_id)
            error_types['workgroup_size_mismatch'] += 1
        if 'missing_depth_write' in desc_lower or 'writedepthtexture' in desc_lower:
            common_issues['missing_depth_write'].append(shader_id)
            error_types['missing_depth_write'] += 1
        if 'division_by_zero' in desc_lower:
            common_issues['division_by_zero'].append(shader_id)
            error_types['division_by_zero'] += 1
        if 'array_bounds' in desc_lower or 'out-of-bounds' in desc_lower:
            common_issues['array_bounds'].append(shader_id)
            error_types['array_bounds'] += 1
        if 'syntax_error' in desc_lower or 'unmatched parentheses' in desc_lower:
            common_issues['syntax_errors'].append(shader_id)
            error_types['syntax_error'] += 1

# Calculate summary statistics
fully_valid = len(shaders_by_priority['clean'])
with_warnings = len(shaders_by_priority['low']) + len(shaders_by_priority['medium'])
with_errors = len(shaders_by_priority['critical']) + len(shaders_by_priority['high'])

# Build master report
master_report = {
    'timestamp': datetime.now().isoformat(),
    'summary': {
        'total_shaders': len(all_shader_ids),
        'fully_valid': fully_valid,
        'with_warnings': with_warnings,
        'with_errors': with_errors,
        'critical_issues': len(shaders_by_priority['critical']),
        'high_priority': len(shaders_by_priority['high']),
        'medium_priority': len(shaders_by_priority['medium']),
        'low_priority': len(shaders_by_priority['low'])
    },
    'reports': {
        'wgsl_syntax': {
            'valid': syntax_report.get('valid_count', 0),
            'errors': syntax_report.get('error_count', 0),
            'warnings': syntax_report.get('warning_count', 0)
        },
        'bindgroup_compat': {
            'compatible': bindgroup_report.get('compatible_count', 0),
            'incompatible': bindgroup_report.get('incompatible_count', 0)
        },
        'runtime_errors': {
            'clean': runtime_report.get('clean_count', 0),
            'with_warnings': runtime_report.get('summary', {}).get('medium', 0),
            'with_errors': runtime_report.get('summary', {}).get('critical', 0) + runtime_report.get('error_count', 0)
        },
        'param_validation': {
            'valid': param_report.get('valid_count', 0),
            'invalid': param_report.get('invalid_count', 0)
        }
    },
    'shaders_needing_fixes': {
        'critical': shaders_by_priority['critical'][:50],  # Limit to 50
        'high': shaders_by_priority['high'][:50],
        'medium': shaders_by_priority['medium'][:50],
        'low': shaders_by_priority['low'][:50]
    },
    'common_issues': {
        'missing_texture_store': list(set(common_issues.get('missing_texture_store', []))),
        'invalid_bindings': list(set(common_issues.get('invalid_bindings', []))),
        'workgroup_size_mismatch': list(set(common_issues.get('workgroup_size_mismatch', []))),
        'missing_depth_write': list(set(common_issues.get('missing_depth_write', []))),
        'division_by_zero': list(set(common_issues.get('division_by_zero', []))),
        'array_bounds': list(set(common_issues.get('array_bounds', []))),
        'unused_params': [s['shader_id'] for s in param_report['shaders'] if any(i['type'] == 'unused_param' for i in s.get('issues', []))]
    },
    'statistics': {
        'by_category': dict(by_category),
        'error_types': dict(error_types)
    },
    'orphan_files': {
        'orphan_wgsl': param_report.get('orphan_wgsl_files', []),
        'orphan_json': param_report.get('orphan_json_files', [])
    }
}

# Write master report
output_path = '/root/image_video_effects/reports/shader_validation_master_report.json'
with open(output_path, 'w') as f:
    json.dump(master_report, f, indent=2)

print(f"\nMaster report written to: {output_path}")
print(f"\nSummary:")
print(f"  Total shaders: {master_report['summary']['total_shaders']}")
print(f"  Fully valid: {master_report['summary']['fully_valid']}")
print(f"  With warnings: {master_report['summary']['with_warnings']}")
print(f"  With errors: {master_report['summary']['with_errors']}")
print(f"  Critical: {master_report['summary']['critical_issues']}")
print(f"  High: {master_report['summary']['high_priority']}")
print(f"  Medium: {master_report['summary']['medium_priority']}")
print(f"  Low: {master_report['summary']['low_priority']}")
