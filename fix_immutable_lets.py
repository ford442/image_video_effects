#!/usr/bin/env python3
import os
import re

SHADER_DIR = "public/shaders"

def fix_shader(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    original = content

    # Fix the most common cases
    content = re.sub(r'let (mousePos|uv|p|pos|mouse|dir|rayDir|center) =', r'var \1 =', content)
    
    # Also fix any remaining mutations on let variables (rare)
    content = re.sub(r'\b(let\s+\w+)\s*(\.\w+\s*[\*\+-]=)', r'var \1\2', content)

    if content != original:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"✅ Fixed: {os.path.basename(file_path)}")
        return True
    return False

fixed = 0
for root, _, files in os.walk(SHADER_DIR):
    for file in files:
        if file.endswith('.wgsl'):
            path = os.path.join(root, file)
            if fix_shader(path):
                fixed += 1

print(f"\n🎉 Done! Fixed {fixed} shaders.")
print("Now run: npm run build")
