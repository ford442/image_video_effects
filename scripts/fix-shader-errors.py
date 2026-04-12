#!/usr/bin/env python3
"""
Shader Error Fixer - Automatically fixes common WGSL errors
Run this after getting shader scan results
"""

import json
import re
import sys
from pathlib import Path

def fix_shader(filepath, error_msg):
    """Apply fixes based on error message"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    fixes = []
    
    # Fix 1: 'mod' is a reserved keyword -> rename to 'mod_val' or 'module'
    if "'mod' is a reserved keyword" in error_msg:
        content = re.sub(r'\bmod\b', 'mod_val', content)
        fixes.append("Renamed 'mod' to 'mod_val'")
    
    # Fix 2: 'active' is a reserved keyword
    if "'active' is a reserved keyword" in error_msg:
        content = re.sub(r'\bactive\b', 'is_active', content)
        fixes.append("Renamed 'active' to 'is_active'")
    
    # Fix 3: 'self' is a reserved keyword
    if "'self' is a reserved keyword" in error_msg:
        content = re.sub(r'\bself\b', 'this_val', content)
        fixes.append("Renamed 'self' to 'this_val'")
    
    # Fix 4: local_id -> local_invocation_id
    if "'local_id'" in error_msg:
        content = content.replace('local_id', 'local_invocation_id')
        fixes.append("Fixed 'local_id' to 'local_invocation_id'")
    
    # Fix 5: i32 vs u32 comparison - cast to same type
    if "no matching overload for 'operator >= (i32, u32)'" in error_msg:
        # Find patterns like: for (var i: i32 = 0; i >= count; i++) where count is u32
        # Convert loop indices to u32
        content = re.sub(
            r'for\s*\(\s*var\s+(\w+):\s*i32\s*=\s*0\s*;\s*\1\s*<\s*(\w+)\s*;',
            r'for (var \1: u32 = 0u; \1 < \2;',
            content
        )
        fixes.append("Fixed i32/u32 comparison")
    
    # Fix 6: Cannot assign to swizzle (e.g., pos.yz = ...)
    if "cannot assign to value of type 'swizzle" in error_msg:
        # Replace pos.yz = val with pos = vec2<f32>(pos.x, val.y) or similar
        # This is complex, mark for manual review
        fixes.append("⚠️ SWIZZLE ASSIGNMENT - needs manual fix")
    
    # Fix 7: unresolved value 'audioReactivity' -> use proper uniform access
    if "unresolved value 'audioReactivity'" in error_msg:
        content = content.replace('audioReactivity', 'u.zoom_params.w')
        fixes.append("Fixed 'audioReactivity' to 'u.zoom_params.w'")
    
    # Fix 8: textureSampleLevel with vec2<i32> coords - should be vec2<f32>
    if "no matching call to 'textureSampleLevel" in error_msg and "vec2<i32>" in error_msg:
        # Find and fix integer coords
        content = re.sub(
            r'textureSampleLevel\(([^,]+),\s*([^,]+),\s*vec2<i32>\(([^)]+)\)',
            r'textureSampleLevel(\1, \2, vec2<f32>(\3)',
            content
        )
        fixes.append("Fixed textureSampleLevel coords to vec2<f32>")
    
    # Fix 9: textureLoad on write-only storage texture
    if "no matching call to 'textureLoad" in error_msg and "texture_storage_2d" in error_msg:
        # These need to use a read texture instead
        fixes.append("⚠️ textureLoad on write-only storage - needs manual fix (use dataTextureC)")
    
    # Fix 10: mod() function doesn't exist -> use fract() or custom mod
    if "unresolved call target 'mod'" in error_msg:
        # Add custom mod function if not present
        if 'fn custom_mod(' not in content:
            mod_func = '''
fn custom_mod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}
'''
            # Insert after first function or at beginning
            content = mod_func + '\n' + content
        content = content.replace('mod(', 'custom_mod(')
        fixes.append("Replaced mod() with custom_mod()")
    
    # Fix 11: struct member not found 'lighting_params'
    if "struct member lighting_params not found" in error_msg:
        # The shader references a uniform that doesn't exist
        fixes.append("⚠️ References 'lighting_params' - needs manual fix")
    
    # Fix 12: cannot assign to 'let' -> change to 'var'
    if "cannot assign to 'let" in error_msg:
        # Find the specific let and change to var
        # This is tricky without line numbers, do pattern match
        content = re.sub(
            r'let\s+(\w+)\s*=\s*([^;]+);(\s*\n[^/]*\1\s*=)',
            r'var \1 = \2;\3',
            content
        )
        fixes.append("Changed 'let' to 'var' for mutable variables")
    
    # Fix 13: missing initializer for let/var
    if "missing initializer" in error_msg:
        fixes.append("⚠️ Missing initializer - needs manual fix")
    
    # Fix 14: expected '}' for function body
    if "expected '}' for function body" in error_msg:
        fixes.append("⚠️ SYNTAX ERROR - unclosed brace, needs manual review")
    
    # Fix 15: invalid character (UTF-8 issues)
    if "invalid character found" in error_msg:
        # Remove common problematic unicode characters
        content = content.replace('\u201c', '"').replace('\u201d', '"')  # Smart quotes
        content = content.replace('\u2018', "'").replace('\u2019', "'")  # Smart apostrophes
        content = content.replace('\u2013', '-').replace('\u2014', '-')  # En/em dashes
        fixes.append("Fixed invalid unicode characters")
    
    # Fix 16: invalid type for parameter
    if "invalid type for parameter" in error_msg:
        fixes.append("⚠️ INVALID PARAMETER TYPE - needs manual fix")
    
    # Fix 17: cannot assign to 'let f' (specific pattern)
    if "cannot assign to 'let f'" in error_msg:
        content = re.sub(r'\blet\s+f\s*=', 'var f =', content)
        fixes.append("Fixed 'let f' to 'var f'")
    
    # Write back if changed
    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return fixes
    
    return None

def main():
    # Read the scan report
    report_path = Path('/root/shader_list.json')
    if not report_path.exists():
        print("❌ Report not found at /root/shader_list.json")
        sys.exit(1)
    
    with open(report_path, 'r') as f:
        report = json.load(f)
    
    errors = report.get('errors', [])
    print(f"🔧 Found {len(errors)} shaders with errors")
    print()
    
    base_path = Path('/root/image_video_effects/public')
    fixed_count = 0
    needs_manual = []
    
    for error in errors:
        shader_id = error['id']
        shader_url = error['url']
        error_msg = error.get('error', '')
        
        # Convert URL to filepath
        if shader_url.startswith('./'):
            shader_url = shader_url[2:]
        if shader_url.startswith('shaders/'):
            shader_url = shader_url[8:]
        
        filepath = base_path / 'shaders' / shader_url
        
        if not filepath.exists():
            print(f"⚠️  {shader_id}: File not found at {filepath}")
            continue
        
        print(f"🔨 Fixing {shader_id}...")
        
        try:
            fixes = fix_shader(filepath, error_msg)
            if fixes:
                print(f"   ✅ Fixed: {', '.join(fixes)}")
                fixed_count += 1
            else:
                # Check if it has manual fix markers
                if any('⚠️' in msg for msg in [error_msg]):
                    needs_manual.append(shader_id)
                    print(f"   ⚠️  Needs manual fix")
                else:
                    print(f"   ℹ️  No automatic fix available")
        except Exception as e:
            print(f"   ❌ Error: {e}")
            needs_manual.append(shader_id)
    
    print()
    print('=' * 60)
    print(f"✅ Fixed: {fixed_count}/{len(errors)} shaders")
    
    if needs_manual:
        print()
        print(f"⚠️  Needs manual review ({len(needs_manual)}):")
        for sid in needs_manual:
            print(f"   - {sid}")
    
    print()
    print("Next steps:")
    print("1. Review shaders marked for manual fix")
    print("2. Run shader scanner again to verify fixes")
    print("3. npm run build && deploy")

if __name__ == '__main__':
    main()
