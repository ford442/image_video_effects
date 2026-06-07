#!/usr/bin/env python3
"""
Auto-fix immutable 'let' reassignment errors by changing 'let' to 'var'.
This is a robust version that properly handles variable tracking.
"""

import re
import os
from pathlib import Path
from collections import defaultdict

def analyze_shader(wgsl_path):
    """Analyze a WGSL file to find which 'let' variables need to be 'var'."""
    
    try:
        with open(wgsl_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        return None, f'Failed to read file: {e}'
    
    # Track let declarations
    let_declarations = {}  # var_name -> line_index
    needs_var = set()
    
    # First pass: find all let declarations
    for i, line in enumerate(lines):
        match = re.search(r'^\s*let\s+(\w+)\s*=', line)
        if match:
            var_name = match.group(1)
            let_declarations[var_name] = i
    
    # Second pass: find reassignments (+=, -=, *=, /=, =)
    for i, line in enumerate(lines):
        for var_name in let_declarations.keys():
            # Skip the declaration line itself
            if i == let_declarations[var_name]:
                continue
            
            # Look for reassignment operators
            # Match: variable {whitespace} {operator}
            if re.search(rf'\b{var_name}\s*(\+=|-=|\*=|/=)', line):
                needs_var.add(var_name)
            elif re.search(rf'\b{var_name}\s*=(?!=)', line):
                # Direct assignment (but not ==, !=, <=, >=)
                # Make sure it's not in a comment
                code_part = line.split('//')[0]  # Remove comments
                if re.search(rf'\b{var_name}\s*=(?!=)', code_part):
                    needs_var.add(var_name)
    
    return (let_declarations, needs_var), None

def fix_shader(wgsl_path):
    """Fix a WGSL file by converting problematic 'let' to 'var'."""
    
    analysis, error = analyze_shader(wgsl_path)
    if error:
        return {'status': 'error', 'message': error}
    
    let_declarations, needs_var = analysis
    
    if not needs_var:
        return {'status': 'ok', 'message': 'No fixes needed'}
    
    # Read the file
    with open(wgsl_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # Fix the declarations
    fixed_count = 0
    for var_name in needs_var:
        if var_name in let_declarations:
            line_idx = let_declarations[var_name]
            original = lines[line_idx]
            # Replace 'let' with 'var' at the start of variable declaration
            lines[line_idx] = re.sub(
                rf'(\s*)let(\s+{re.escape(var_name)}\b)',
                rf'\1var\2',
                lines[line_idx],
                count=1
            )
            if lines[line_idx] != original:
                fixed_count += 1
    
    # Write back
    if fixed_count > 0:
        with open(wgsl_path, 'w', encoding='utf-8') as f:
            f.writelines(lines)
        return {'status': 'fixed', 'vars_fixed': sorted(needs_var), 'count': fixed_count}
    else:
        return {'status': 'ok', 'message': 'Analysis showed fixes needed but unable to apply'}

def fix_all_shaders():
    """Fix all WGSL files in the public/shaders directory."""
    shader_dir = Path('/workspaces/image_video_effects/public/shaders')
    
    results = {}
    total_fixed_files = 0
    total_fixed_vars = 0
    error_files = []
    
    wgsl_files = sorted(shader_dir.glob('*.wgsl'))
    
    for i, wgsl_file in enumerate(wgsl_files, 1):
        result = fix_shader(str(wgsl_file))
        results[wgsl_file.name] = result
        
        if result['status'] == 'fixed':
            total_fixed_files += 1
            total_fixed_vars += result['count']
        elif result['status'] == 'error':
            error_files.append((wgsl_file.name, result['message']))
    
    return results, total_fixed_files, total_fixed_vars, error_files

def main():
    print("=" * 80)
    print("Auto-fixing immutable 'let' reassignment errors")
    print("=" * 80)
    print()
    
    results, fixed_files, fixed_vars, errors = fix_all_shaders()
    
    print(f"Processed {len(results)} files")
    print(f"Fixed {fixed_files} files ({fixed_vars} variable declarations changed)")
    
    if errors:
        print(f"\n{len(errors)} errors encountered:")
        for filename, err_msg in errors:
            print(f"  ✗ {filename}: {err_msg}")
    
    if fixed_files > 0:
        print("\n" + "=" * 80)
        print("FIXED FILES:")
        print("=" * 80)
        
        for filename in sorted(results.keys()):
            result = results[filename]
            if result['status'] == 'fixed':
                vars_list = ', '.join(result['vars_fixed'])
                print(f"✓ {filename}")
                print(f"  Changed: {vars_list}")
    
    print("\n" + "=" * 80)
    print("Done!")
    print("=" * 80)

if __name__ == '__main__':
    main()
