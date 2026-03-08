#!/usr/bin/env python3
"""
Auto-fix 'target' reserved keyword errors by renaming to 'target_pos'.
"""

import re
from pathlib import Path
from collections import defaultdict

def fix_target_keyword(wgsl_path):
    """Fix 'target' variable names by renaming to 'target_pos'."""
    
    try:
        with open(wgsl_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        return {'status': 'error', 'message': f'Failed to read file: {e}'}
    
    original_content = ''.join(lines)
    modified = False
    
    # Fix the variable declarations and all usages
    new_lines = []
    for i, line in enumerate(lines):
        # Get code part (before comments)
        code_part = line.split('//')[0]
        comment_part = line[len(code_part):]
        
        # Check if this line has 'target' in the code part (not comment)
        if 'target' in code_part:
            # Replace 'target' with 'target_pos' but be careful:
            # 1. Match word boundaries
            # 2. Don't replace in strings (simplified - just look for code)
            # 3. Keep indentation
            
            new_code = re.sub(r'\btarget\b', 'target_pos', code_part)
            
            if new_code != code_part:
                modified = True
                new_lines.append(new_code + comment_part)
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)
    
    new_content = ''.join(new_lines)
    
    if modified:
        try:
            with open(wgsl_path, 'w', encoding='utf-8') as f:
                f.writelines(new_lines)
            return {'status': 'fixed', 'message': 'Renamed target → target_pos'}
        except Exception as e:
            return {'status': 'error', 'message': f'Failed to write file: {e}'}
    else:
        return {'status': 'ok', 'message': 'No target keyword found'}

def fix_all_shaders():
    """Fix all WGSL files with 'target' keyword errors."""
    shader_dir = Path('/workspaces/image_video_effects/public/shaders')
    
    # Files we know have 'target' errors
    problematic_files = [
        'nebula-gyroid.wgsl',
        'gen-isometric-city.wgsl',
        'cosmic-jellyfish.wgsl',
        'gen-quantum-neural-lace.wgsl',
        'gen-hyper-labyrinth.wgsl',
        'gen-bioluminescent-abyss.wgsl',
        'gen-neuro-cosmos.wgsl',
        'gen-alien-flora.wgsl',
        'gen-chronos-labyrinth.wgsl'
    ]
    
    results = {}
    fixed_count = 0
    
    for filename in problematic_files:
        wgsl_file = shader_dir / filename
        if wgsl_file.exists():
            result = fix_target_keyword(str(wgsl_file))
            results[filename] = result
            if result['status'] == 'fixed':
                fixed_count += 1
    
    return results, fixed_count

def main():
    print("=" * 80)
    print("Auto-fixing 'target' reserved keyword errors")
    print("=" * 80)
    print()
    
    results, fixed_count = fix_all_shaders()
    
    print(f"Processed 9 files")
    print(f"Fixed {fixed_count} files")
    print()
    
    print("=" * 80)
    print("RESULTS:")
    print("=" * 80)
    
    for filename in sorted(results.keys()):
        result = results[filename]
        status_icon = "✓" if result['status'] == 'fixed' else "✗"
        print(f"{status_icon} {filename}: {result['message']}")
    
    print()
    print("=" * 80)
    print("Done!")
    print("=" * 80)

if __name__ == '__main__':
    main()
