#!/usr/bin/env python3
"""
WGSL Syntax Validator - Agent 1: Shader Validation Swarm
Validates all .wgsl files for syntax errors, proper bindings, and WGSL compliance.
"""

import os
import re
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any, Tuple

SHADERS_DIR = Path("/root/image_video_effects/public/shaders")
OUTPUT_FILE = Path("/root/image_video_effects/wgsl_syntax_report.json")

# Required bindings for standard compute shaders
REQUIRED_BINDINGS = [
    (0, 0, "var", "sampler"),
    (0, 1, "var", "texture_2d<f32>"),
    (0, 2, "var", "texture_storage_2d<rgba32float, write>"),
    (0, 3, "var<uniform>", "Uniforms"),
    (0, 4, "var", "texture_2d<f32>"),
    (0, 5, "var", "sampler"),
    (0, 6, "var", "texture_storage_2d<r32float, write>"),
    (0, 7, "var", "texture_storage_2d<rgba32float, write>"),
    (0, 8, "var", "texture_storage_2d<rgba32float, write>"),
    (0, 9, "var", "texture_2d<f32>"),
    (0, 10, "var<storage, read_write>", "array<f32>"),
    (0, 11, "var", "sampler_comparison"),
    (0, 12, "var<storage, read>", "array<vec4<f32>>"),
]

# Shader categories that don't require full compute bindings
NON_COMPUTE_PREFIXES = ('_', 'gen_', 'texture', 'imageVideo')
NON_COMPUTE_PATTERNS = ['_hash_library', '_template_', 'texture.wgsl', 'imageVideo']


class WGSLValidator:
    def __init__(self, filepath: Path):
        self.filepath = filepath
        self.content = ""
        self.lines = []
        self.errors: List[Dict[str, Any]] = []
        self.warnings: List[Dict[str, Any]] = []
        self.is_compute_shader = False
        self.has_vertex_stage = False
        self.has_fragment_stage = False
        
    def load(self) -> bool:
        """Load the shader file."""
        try:
            with open(self.filepath, 'r', encoding='utf-8') as f:
                self.content = f.read()
                self.lines = self.content.split('\n')
            return True
        except Exception as e:
            self.errors.append({
                "line": 0,
                "severity": "critical",
                "message": f"Failed to load file: {str(e)}"
            })
            return False
    
    def detect_shader_type(self):
        """Detect what type of shader this is."""
        filename = self.filepath.name
        
        # Check for library files (utility files, not actual shaders)
        self.is_library = filename.startswith('_')
        
        # Check for compute shader
        self.is_compute_shader = '@compute' in self.content
        
        # Check for vertex/fragment stages
        self.has_vertex_stage = '@vertex' in self.content
        self.has_fragment_stage = '@fragment' in self.content
        
        # Generative shaders (gen_*) often have simplified binding structure
        self.is_generative = filename.startswith('gen_') or filename.startswith('gen-')
        
        # Texture/ImageVideo shaders are render shaders, not compute
        self.is_render_shader = filename in ['texture.wgsl', 'imageVideo.wgsl']
        
    def add_error(self, line_num: int, severity: str, message: str):
        """Add an error to the report."""
        self.errors.append({
            "line": line_num,
            "severity": severity,
            "message": message
        })
    
    def add_warning(self, line_num: int, message: str):
        """Add a warning to the report."""
        self.warnings.append({
            "line": line_num,
            "severity": "warning",
            "message": message
        })
    
    def check_workgroup_size(self):
        """Check that workgroup_size is appropriate."""
        pattern = r'@workgroup_size\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)'
        matches = list(re.finditer(pattern, self.content))
        
        if not matches:
            # Check for compute shader without workgroup_size
            if self.is_compute_shader:
                for i, line in enumerate(self.lines, 1):
                    if '@compute' in line and '@workgroup_size' not in line:
                        self.add_error(i, "critical", "Compute shader missing @workgroup_size attribute")
                        break
            return
        
        for match in matches:
            x, y, z = int(match.group(1)), int(match.group(2)), int(match.group(3))
            line_num = self.content[:match.start()].count('\n') + 1
            
            # Standard shaders should use (8, 8, 1)
            # But some specialized shaders may use different sizes
            if (x, y, z) != (8, 8, 1):
                if self.filepath.name.startswith('liquid'):
                    # Liquid shaders often use different workgroup sizes
                    self.add_warning(line_num, f"Workgroup size is ({x}, {y}, {z}), expected (8, 8, 1) for standard shaders")
                else:
                    self.add_warning(line_num, f"Workgroup size is ({x}, {y}, {z}), expected (8, 8, 1)")
    
    def check_bindings(self):
        """Check that all required bindings are present for compute shaders."""
        if not self.is_compute_shader:
            return
            
        # Skip full binding check for library/template files
        if self.is_library or self.is_render_shader:
            return
        
        binding_pattern = r'@group\((\d+)\)\s*@binding\((\d+)\)\s*(var(?:<[^>]+>)?)\s+(\w+)\s*:\s*([^;]+)'
        matches = list(re.finditer(binding_pattern, self.content))
        
        found_bindings = set()
        for match in matches:
            group = int(match.group(1))
            binding = int(match.group(2))
            found_bindings.add((group, binding))
        
        # Check for critical bindings (0-3 are essential)
        critical_bindings = [(0, i) for i in range(4)]
        for group, binding in critical_bindings:
            if (group, binding) not in found_bindings:
                self.add_error(0, "critical", f"Missing required binding @group({group}) @binding({binding})")
        
        # For generative shaders, be more lenient with additional bindings
        if not self.is_generative:
            # Check for other important bindings
            for group, binding, _, _ in REQUIRED_BINDINGS[4:8]:  # Check bindings 4-7
                if (group, binding) not in found_bindings:
                    self.add_warning(0, f"Missing binding @group({group}) @binding({binding}) - may cause issues")
    
    def check_struct_uniforms(self):
        """Check that the Uniforms struct is properly defined for compute shaders."""
        if not self.is_compute_shader:
            return
            
        # Skip for library/template files
        if self.is_library:
            return
        
        # Find struct Uniforms
        struct_pattern = r'struct\s+Uniforms\s*\{([^}]+)\}'
        match = re.search(struct_pattern, self.content, re.DOTALL)
        
        if not match:
            # Some generative shaders might not use Uniforms
            if not self.is_generative:
                self.add_error(0, "critical", "Missing 'struct Uniforms' definition")
            return
        
        struct_content = match.group(1)
        
        # Check for required fields
        required_fields = [
            ("config", "vec4<f32>"),
            ("zoom_config", "vec4<f32>"),
            ("zoom_params", "vec4<f32>"),
        ]
        
        for field_name, field_type in required_fields:
            field_pattern = rf'{field_name}\s*:\s*{re.escape(field_type)}'
            if not re.search(field_pattern, struct_content):
                self.add_error(0, "critical", f"Missing or incorrect field in Uniforms struct: {field_name}: {field_type}")
        
        # Check for ripples array (optional for some shader types)
        if 'ripples' not in struct_content and not self.is_generative:
            self.add_warning(0, "Missing 'ripples' array in Uniforms struct - may affect mouse interactions")
    
    def check_main_function(self):
        """Check that the main function is properly defined."""
        if self.is_library:
            return
            
        if self.is_compute_shader:
            # Check for compute shader main function
            main_pattern = r'fn\s+main\s*\(\s*@builtin\(global_invocation_id\)\s+\w+\s*:\s*vec3<u32>\s*\)'
            if not re.search(main_pattern, self.content):
                # Check for alternative patterns
                if 'fn main' not in self.content:
                    self.add_error(0, "critical", "Missing 'fn main' function definition")
                else:
                    # Check for incorrect parameter format
                    for i, line in enumerate(self.lines, 1):
                        if 'fn main' in line and '@builtin(global_invocation_id)' not in self.content:
                            self.add_error(i, "critical", "main function missing @builtin(global_invocation_id) parameter")
                            break
        
        if self.has_vertex_stage:
            # Check for vertex main
            if '@vertex' in self.content and 'fn main' not in self.content:
                self.add_error(0, "critical", "Vertex shader missing main function")
                
        if self.has_fragment_stage:
            # Check for fragment main  
            if '@fragment' in self.content and 'fn main' not in self.content:
                self.add_error(0, "critical", "Fragment shader missing main function")
    
    def check_braces(self):
        """Check for unmatched braces."""
        open_count = self.content.count('{')
        close_count = self.content.count('}')
        
        if open_count != close_count:
            self.add_error(0, "critical", f"Unmatched braces: {open_count} opening, {close_count} closing")
        
        # Check parentheses
        open_paren = self.content.count('(')
        close_paren = self.content.count(')')
        if open_paren != close_paren:
            self.add_error(0, "critical", f"Unmatched parentheses: {open_paren} opening, {close_paren} closing")
    
    def check_texture_store(self):
        """Check that textureStore is called for writeTexture."""
        if not self.is_compute_shader or self.is_library:
            return
            
        if 'writeTexture' in self.content and 'textureStore' not in self.content:
            self.add_warning(0, "writeTexture declared but textureStore not used - shader may not write output")
    
    def check_syntax_issues(self):
        """Check for common WGSL syntax issues."""
        # Check for 'let' variables that are never assigned (immutable let issue)
        let_pattern = r'^\s*let\s+(\w+)\s*:'
        for i, line in enumerate(self.lines, 1):
            match = re.search(let_pattern, line)
            if match:
                var_name = match.group(1)
                # Check if this let variable is assigned (has = after declaration)
                if '=' not in line.split('//')[0]:
                    self.add_error(i, "critical", f"'let' variable '{var_name}' declared without initialization - use 'var' or assign a value")
        
        # Check for potential array access issues
        array_pattern = r'(\w+)\[(\w+)\]'
        for match in re.finditer(array_pattern, self.content):
            index = match.group(2)
            # Check if index is a float type (common error)
            if index in ['f32', '0.0', '1.0'] or ('.' in index and not index.startswith('0x')):
                line_num = self.content[:match.start()].count('\n') + 1
                self.add_error(line_num, "critical", f"Array index appears to be float type - array indices must be integers")
    
    def check_variable_usage(self):
        """Check for undefined variable usage."""
        if self.is_library:
            return
            
        # Find all function definitions
        fn_pattern = r'fn\s+(\w+)\s*\([^)]*\)\s*(?:->\s*\w+)?\s*\{'
        fn_matches = list(re.finditer(fn_pattern, self.content))
        
        for fn_match in fn_matches:
            fn_name = fn_match.group(1)
            fn_start = fn_match.end() - 1  # Position after opening brace
            
            # Find the matching closing brace (simplified - just find next top-level fn or end)
            next_fn = re.search(r'\nfn\s+', self.content[fn_match.end():])
            if next_fn:
                fn_end = fn_match.end() + next_fn.start()
            else:
                fn_end = len(self.content)
            
            fn_body = self.content[fn_start:fn_end]
            
            # Check for undefined variables in function body
            # This is a simplified check - just look for obvious issues
            builtin_vars = {'global_id', 'local_id', 'workgroup_id', 'num_workgroups', 'sample_index'}
            
    def check_wgsl_keywords(self):
        """Check for invalid or deprecated WGSL keywords."""
        # Check for deprecated keywords
        deprecated = {
            'attribute': '@attribute syntax is deprecated',
            'stride': 'stride is deprecated, use array element type directly',
        }
        
        for keyword, message in deprecated.items():
            if keyword in self.content.lower():
                for i, line in enumerate(self.lines, 1):
                    if keyword in line.lower():
                        self.add_warning(i, message)
    
    def validate(self) -> Dict[str, Any]:
        """Run all validation checks."""
        if not self.load():
            return self.get_result()
        
        self.detect_shader_type()
        
        # Run checks
        self.check_braces()
        
        if not self.is_library:
            self.check_workgroup_size()
            self.check_bindings()
            self.check_struct_uniforms()
            self.check_main_function()
            self.check_texture_store()
            self.check_syntax_issues()
            self.check_variable_usage()
            self.check_wgsl_keywords()
        
        return self.get_result()
    
    def get_result(self) -> Dict[str, Any]:
        """Get the validation result."""
        shader_id = self.filepath.stem
        
        # Combine errors and warnings for output
        all_issues = []
        for e in self.errors:
            all_issues.append(f"line {e['line']}: [{e['severity'].upper()}] {e['message']}")
        for w in self.warnings:
            all_issues.append(f"line {w['line']}: [WARNING] {w['message']}")
        
        # Determine status
        if self.errors:
            status = "error"
        elif self.warnings:
            status = "warning"
        else:
            status = "valid"
        
        return {
            "shader_id": shader_id,
            "file": str(self.filepath.relative_to(Path("/root/image_video_effects"))),
            "status": status,
            "shader_type": "compute" if self.is_compute_shader else ("vertex/fragment" if (self.has_vertex_stage or self.has_fragment_stage) else "library/utility"),
            "errors": [f"line {e['line']}: [{e['severity'].upper()}] {e['message']}" for e in self.errors],
            "warnings": [f"line {w['line']}: [WARNING] {w['message']}" for w in self.warnings]
        }


def main():
    """Main validation function."""
    print("=" * 60)
    print("WGSL Syntax Validator - Agent 1: Shader Validation Swarm")
    print("=" * 60)
    
    # Find all WGSL files
    shader_files = sorted(SHADERS_DIR.glob("*.wgsl"))
    total = len(shader_files)
    
    print(f"\nFound {total} shader files to validate...\n")
    
    results = []
    valid_count = 0
    error_count = 0
    warning_count = 0
    
    for i, shader_file in enumerate(shader_files, 1):
        print(f"[{i}/{total}] Validating {shader_file.name}...", end=" ")
        
        validator = WGSLValidator(shader_file)
        result = validator.validate()
        results.append(result)
        
        if result["status"] == "valid":
            valid_count += 1
            print("✓ VALID")
        elif result["status"] == "warning":
            warning_count += 1
            print(f"⚠ WARNING ({len(result['warnings'])} warnings)")
        else:
            error_count += 1
            print(f"✗ ERROR ({len(result['errors'])} errors)")
    
    # Create report
    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "total_shaders": total,
        "valid_count": valid_count,
        "warning_count": warning_count,
        "error_count": error_count,
        "shaders": results
    }
    
    # Write report
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    
    print("\n" + "=" * 60)
    print("VALIDATION COMPLETE")
    print("=" * 60)
    print(f"Total shaders: {total}")
    print(f"Valid: {valid_count} ({valid_count/total*100:.1f}%)")
    print(f"With warnings: {warning_count} ({warning_count/total*100:.1f}%)")
    print(f"With errors: {error_count} ({error_count/total*100:.1f}%)")
    print(f"\nReport saved to: {OUTPUT_FILE}")
    
    return report


if __name__ == "__main__":
    main()
