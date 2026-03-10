#!/usr/bin/env python3
"""
Improved scanner for immutable 'let' reassignment errors that understands scope.
This version properly ignores comments and only flags reassignments in the same scope.
"""

import re
import os
from pathlib import Path
from collections import defaultdict

def remove_comments(line):
    """Remove comments from a line of WGSL code."""
    # Handle strings first to avoid removing // inside strings
    # This is a simple approach - just split on //
    return line.split('//')[0]

def is_comment_line(line):
    """Check if a line is just a comment."""
    stripped = line.lstrip()
    return stripped.startswith('//')

def find_immutable_let_errors(wgsl_path):
    """Scan a WGSL file for 'let' variables being reassigned in same scope."""
    errors = []
    
    try:
        with open(wgsl_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        return [{'error': f'Failed to read file: {e}'}]
    
    # Track let declarations by scope
    # Key each declaration by (function_name, var_name)
    let_vars = {}  # (scope_id, var_name) -> line_number
    scope_stack = [0]  # Track brace depth
    scope_counter = 0
    current_scope = 0
    
    for i, line in enumerate(lines, 1):
        code_part = remove_comments(line)
        
        # Skip empty/comment-only lines
        if not code_part.strip():
            continue
        
        # Track scope (very simplified - just by brace count)
        # Real scope tracking would need to parse WGSL properly
        open_braces = code_part.count('{')
        close_braces = code_part.count('}')
        
        # For each opening brace, increment scope
        for _ in range(open_braces):
            scope_counter += 1
            scope_stack.append(scope_counter)
        
        current_scope = scope_stack[-1] if scope_stack else 0
        
        # Check if this is a let declaration
        let_match = re.search(r'let\s+(\w+)\s*=', code_part)
        if let_match:
            var_name = let_match.group(1)
            key = (current_scope, var_name)
            let_vars[key] = i
        
        # Check for reassignments in current scope
        for (scope_id, var_name), decl_line in list(let_vars.items()):
            # Only flag errors if reassignment is in same scope AND after declaration
            if scope_id == current_scope and i > decl_line:
                # Pattern: variable followed by assignment operator
                assignment_patterns = [
                    rf'\b{var_name}\s*\+=',
                    rf'\b{var_name}\s*-=',
                    rf'\b{var_name}\s*\*=',
                    rf'\b{var_name}\s*/=',
                    rf'\b{var_name}\s*=(?!=)',  # = but not ==
                ]
                
                for pattern in assignment_patterns:
                    if re.search(pattern, code_part):
                        # Make sure this is not a re-declaration
                        if not re.search(rf'let\s+{var_name}', code_part):
                            errors.append({
                                'var_name': var_name,
                                'decl_line': decl_line,
                                'error_line': i,
                                'error_code': line.strip(),
                                'operator': re.search(rf'{var_name}\s*(\+=|-=|\*=|/=|=)', code_part).group(1) if re.search(rf'{var_name}\s*(\+=|-=|\*=|/=|=)', code_part) else '='
                            })
        
        # For each closing brace, decrement scope and clean up old scope vars
        for _ in range(close_braces):
            if scope_stack:
                removed_scope = scope_stack.pop()
                # Remove declarations from closed scope
                to_remove = [k for k in let_vars.keys() if k[0] == removed_scope]
                for k in to_remove:
                    del let_vars[k]
    
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
        
        if errors and not any(e.get('error') for e in errors):
            results[str(wgsl_file)] = errors
            error_count += len(errors)
    
    return results, error_count, file_count

def main():
    print("=" * 80)
    print("Scanning all WGSL shaders (v2 - with scope awareness)")
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
        
        for file_path in sorted(results.keys()):
            print(f"\n📄 {Path(file_path).name}")
            
            for i, error in enumerate(results[file_path], 1):
                print(f"   Error #{i}:")
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

if __name__ == '__main__':
    main()
