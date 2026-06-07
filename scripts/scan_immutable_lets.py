#!/usr/bin/env python3
"""
Scan all WGSL shaders for immutable 'let' reassignment errors.
This detects cases where a 'let' variable is declared and then reassigned.
"""

import re
import os
import json
from pathlib import Path
from collections import defaultdict

def extract_variable_name(decl_line):
    """Extract variable name from a let declaration."""
    match = re.search(r'let\s+(\w+)\s*=', decl_line)
    if match:
        return match.group(1)
    return None

def find_immutable_let_errors(wgsl_path):
    """Scan a WGSL file for 'let' variables being reassigned."""
    errors = []
    
    try:
        with open(wgsl_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        return [{'error': f'Failed to read file: {e}'}]
    
    # Track let declarations and their line numbers
    let_vars = {}  # var_name -> line_number
    
    for i, line in enumerate(lines, 1):
        # Check if this is a let declaration
        if re.search(r'^\s*let\s+\w+\s*=', line):
            var_name = extract_variable_name(line)
            if var_name:
                let_vars[var_name] = i
        
        # Check for reassignments (+=, -=, *=, /=, =)
        for var_name, decl_line in let_vars.items():
            # Pattern: variable followed by assignment operator
            assignment_patterns = [
                rf'\b{var_name}\s*\+=',
                rf'\b{var_name}\s*-=',
                rf'\b{var_name}\s*\*=',
                rf'\b{var_name}\s*/=',
                rf'\b{var_name}\s*=(?!=)',  # = but not ==
            ]
            
            for pattern in assignment_patterns:
                if re.search(pattern, line):
                    # Make sure this is not a re-declaration (let var = ...)
                    if not re.search(rf'let\s+{var_name}', line):
                        errors.append({
                            'var_name': var_name,
                            'decl_line': decl_line,
                            'error_line': i,
                            'error_code': line.strip(),
                            'operator': re.search(rf'{var_name}\s*(\+=|-=|\*=|/=|=)', line).group(1)
                        })
    
    return errors

def scan_all_shaders():
    """Scan all WGSL files in the public/shaders directory."""
    shader_dir = Path('/workspaces/image_video_effects/public/shaders')
    
    results = defaultdict(list)
    error_count = 0
    file_count = 0
    
    for wgsl_file in sorted(shader_dir.glob('*.wgsl')):
        file_count += 1
        errors = find_immutable_let_errors(str(wgsl_file))
        
        if errors:
            results[str(wgsl_file)] = errors
            error_count += len(errors)
    
    return results, error_count, file_count

def main():
    print("=" * 80)
    print("Scanning all WGSL shaders for immutable 'let' reassignment errors")
    print("=" * 80)
    print()
    
    results, error_count, file_count = scan_all_shaders()
    
    print(f"Scanned {file_count} WGSL files")
    print(f"Found {error_count} immutable 'let' reassignment errors in {len(results)} files")
    print()
    
    if results:
        print("=" * 80)
        print("DETAILED ERRORS:")
        print("=" * 80)
        print()
        
        for file_path in sorted(results.keys()):
            print(f"\n📄 {Path(file_path).name}")
            print(f"   Path: {file_path}")
            
            for i, error in enumerate(results[file_path], 1):
                print(f"\n   Error #{i}:")
                print(f"   Variable: {error['var_name']}")
                print(f"   Declared at line: {error['decl_line']}")
                print(f"   Error at line: {error['error_line']}")
                print(f"   Operator: {error['operator']}")
                print(f"   Code: {error['error_code']}")
        
        # Summary
        print("\n" + "=" * 80)
        print("SUMMARY:")
        print("=" * 80)
        print(f"Files with errors: {len(results)}")
        print(f"Total errors: {error_count}")
        
        # Group by variable name
        var_errors = defaultdict(int)
        for errors in results.values():
            for error in errors:
                var_errors[error['var_name']] += 1
        
        print("\nMost common problematic variables:")
        for var_name, count in sorted(var_errors.items(), key=lambda x: -x[1])[:10]:
            print(f"  - {var_name}: {count} errors")
    else:
        print("✓ No immutable 'let' reassignment errors found!")
    
    print()
    print("=" * 80)
    print("NOTE: Fix by changing 'let' to 'var' for variables that need reassignment")
    print("=" * 80)

if __name__ == '__main__':
    main()
