#!/usr/bin/env python3
"""
Scan for 'target' reserved keyword usage in WGSL files.
'target' is a reserved keyword in WGSL and cannot be used as a variable name.
"""

import re
from pathlib import Path
from collections import defaultdict

def find_target_keyword_errors(wgsl_path):
    """Find uses of 'target' as a variable name in WGSL."""
    errors = []
    
    try:
        with open(wgsl_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        return [{'error': f'Failed to read file: {e}'}]
    
    for i, line in enumerate(lines, 1):
        code_part = line.split('//')[0]  # Remove comments
        
        if not code_part.strip():
            continue
        
        # Look for let/var target declarations
        if re.search(r'\b(let|var)\s+target\b', code_part):
            errors.append({
                'type': 'declaration',
                'line': i,
                'code': line.strip(),
                'keyword_type': 'target'
            })
        
        # Look for other uses of target (outside of comments)
        if re.search(r'\btarget\s*=', code_part):
            errors.append({
                'type': 'assignment',
                'line': i,
                'code': line.strip(),
                'keyword_type': 'target'
            })
        
        if re.search(r'\btarget\s*[+\-*/(]', code_part):
            errors.append({
                'type': 'usage',
                'line': i,
                'code': line.strip(),
                'keyword_type': 'target'
            })
    
    return errors

def scan_all_shaders():
    """Scan all WGSL files for 'target' keyword errors."""
    shader_dir = Path('/workspaces/image_video_effects/public/shaders')
    
    results = defaultdict(list)
    error_count = 0
    file_count = 0
    
    for wgsl_file in sorted(shader_dir.glob('*.wgsl')):
        file_count += 1
        errors = find_target_keyword_errors(str(wgsl_file))
        
        if errors and not any(e.get('error') for e in errors):
            results[str(wgsl_file)] = errors
            error_count += len(errors)
    
    return results, error_count, file_count

def main():
    print("=" * 80)
    print("Scanning for 'target' reserved keyword usage in WGSL")
    print("=" * 80)
    print()
    
    results, error_count, file_count = scan_all_shaders()
    
    print(f"Scanned {file_count} WGSL files")
    print(f"Found {error_count} 'target' keyword errors in {len(results)} files")
    print()
    
    if results:
        print("=" * 80)
        print("FILES WITH ERRORS:")
        print("=" * 80)
        
        for file_path in sorted(results.keys()):
            filename = Path(file_path).name
            errors = results[file_path]
            print(f"\n📄 {filename}")
            
            for i, error in enumerate(errors, 1):
                print(f"   Error #{i}:")
                print(f"   Type: {error['type']}")
                print(f"   Line {error['line']}: {error['code']}")
        
        print("\n" + "=" * 80)
        print("SUMMARY:")
        print("=" * 80)
        print(f"Files with errors: {len(results)}")
        print(f"Total errors: {error_count}")
    else:
        print("✓ No 'target' reserved keyword errors found!")
    
    print()
    print("=" * 80)
    print("NOTE: Fix by renaming 'target' to 'target_pos', 'aim_pos', or similar")
    print("=" * 80)

if __name__ == '__main__':
    main()
