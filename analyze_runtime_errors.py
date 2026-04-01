#!/usr/bin/env python3
"""
Agent 3: Runtime Error Detector
Analyzes WGSL shaders for patterns that cause runtime WebGPU errors.
"""

import json
import re
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional
import concurrent.futures

class RuntimeErrorDetector:
    def __init__(self, shaders_dir: str = "public/shaders"):
        self.shaders_dir = Path(shaders_dir)
        self.results = []
        self.total_shaders = 0
        self.clean_count = 0
        self.error_count = 0
        
        # Regex patterns for runtime error detection
        self.patterns = {
            # CRITICAL: Missing textureStore call for writeTexture
            'texture_store_write': re.compile(r'textureStore\s*\(\s*writeTexture', re.IGNORECASE),
            
            # CRITICAL: Missing textureStore call for writeDepthTexture
            'texture_store_depth': re.compile(r'textureStore\s*\(\s*writeDepthTexture', re.IGNORECASE),
            
            # CRITICAL: Missing global_invocation_id
            'global_invocation_id': re.compile(r'@builtin\s*\(\s*global_invocation_id\s*\)', re.IGNORECASE),
            
            # CRITICAL: Workgroup size exceeding limits
            'workgroup_size': re.compile(r'@workgroup_size\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)'),
            
            # CRITICAL: Wrong sampler usage - using u_sampler (filterable) with depth texture
            'wrong_sampler_depth': re.compile(
                r'textureSampleLevel\s*\(\s*readDepthTexture\s*,\s*u_sampler',
                re.IGNORECASE
            ),
            
            # WARNING: Wrong sampler usage - using non_filtering_sampler with color texture
            'wrong_sampler_color': re.compile(
                r'textureSampleLevel\s*\(\s*readTexture\s*,\s*non_filtering_sampler',
                re.IGNORECASE
            ),
            
            # WARNING: Using comparison_sampler incorrectly
            'comparison_sampler_direct': re.compile(
                r'textureSampleLevel\s*\([^)]*comparison_sampler',
                re.IGNORECASE
            ),
            
            # CRITICAL: Binding declarations
            'binding_decl': re.compile(r'@group\(0\)\s*@binding\((\d+)\)', re.IGNORECASE),
            
            # WARNING: Unchecked array access to u.ripples
            'ripples_access': re.compile(
                r'u\.ripples\s*\[\s*(\w+)\s*\]',
                re.IGNORECASE
            ),
            
            # WARNING: Unchecked plasmaBuffer access
            'plasma_buffer_access': re.compile(r'plasmaBuffer\s*\[\s*(\w+)\s*\]', re.IGNORECASE),
            
            # WARNING: Unchecked extraBuffer access
            'extra_buffer_access': re.compile(r'extraBuffer\s*\[\s*([^\]]+)\s*\]', re.IGNORECASE),
            
            # Check for loop bounds on ripples
            'ripple_loop_bound': re.compile(
                r'for\s*\(\s*\w+\s+\w+\s*=\s*(?:0u?|0)u?\s*;\s*\w+\s*<\s*(\d+)u?\s*;',
                re.IGNORECASE
            ),
            
            # Check for u32 cast on loop variable
            'u32_cast': re.compile(r'u32\s*\(\s*u\.config\.y\s*\)', re.IGNORECASE),
            
            # WARNING: Potential division by zero in code (not comments)
            'division_pattern': re.compile(
                r'[=\(].*?/\s*([a-zA-Z_][a-zA-Z0-9_\.\[\]]*)',
                re.IGNORECASE
            ),
            
            # Check for function definitions
            'fn_main': re.compile(r'fn\s+main\s*\('),
            'fn_compute': re.compile(r'@compute'),
            'fn_vertex': re.compile(r'@vertex'),
            'fn_fragment': re.compile(r'@fragment'),
            
            # Check for Uniforms struct binding
            'uniforms_binding': re.compile(
                r'@group\(0\)\s*@binding\(3\)\s+var<uniform>\s+u\s*:',
                re.IGNORECASE
            ),
            
            # Check for infinite loops
            'infinite_loop': re.compile(
                r'(while\s*\(\s*true\s*\)|for\s*\(\s*;?\s*;?\s*\))',
                re.IGNORECASE
            ),
        }
    
    def is_code_line(self, line: str) -> bool:
        """Check if line is actual code (not comment)."""
        stripped = line.strip()
        # Skip empty lines and comment lines
        if not stripped or stripped.startswith('//') or stripped.startswith('*'):
            return False
        return True
    
    def get_code_only(self, line: str) -> str:
        """Get only the code part of a line (remove trailing comments)."""
        # Remove // comments
        if '//' in line:
            line = line[:line.index('//')]
        return line.strip()
    
    def analyze_shader(self, file_path: Path) -> Dict[str, Any]:
        """Analyze a single shader file for runtime error patterns."""
        shader_id = file_path.stem
        errors = []
        warnings = []
        
        try:
            content = file_path.read_text(encoding='utf-8')
            lines = content.split('\n')
        except Exception as e:
            return {
                "shader_id": shader_id,
                "file": str(file_path),
                "status": "has_errors",
                "potential_runtime_errors": [{
                    "type": "file_error",
                    "line": 0,
                    "description": f"Failed to read file: {str(e)}"
                }],
                "severity": "critical"
            }
        
        # Determine shader type
        is_render_shader = self.patterns['fn_vertex'].search(content) or self.patterns['fn_fragment'].search(content)
        has_compute = self.patterns['fn_compute'].search(content)
        has_main = self.patterns['fn_main'].search(content)
        
        # Skip library/template files
        if shader_id.startswith('_') and not has_main:
            return {
                "shader_id": shader_id,
                "file": str(file_path),
                "status": "clean",
                "potential_runtime_errors": [],
                "severity": "low",
                "note": "Library/template file - no main function"
            }
        
        # For render shaders, use different checks
        if is_render_shader and not has_compute:
            # Render shaders have different requirements
            return {
                "shader_id": shader_id,
                "file": str(file_path),
                "status": "clean",
                "potential_runtime_errors": [],
                "severity": "low",
                "note": "Render shader (vertex/fragment) - different validation rules"
            }
        
        # Initialize tracking
        has_texture_store_write = False
        has_texture_store_depth = False
        has_global_id = False
        has_uniforms_binding = False
        bindings_found = set()
        max_workgroup_threads = 0
        has_ripple_loop_bound = False
        ripple_bound_value = 0
        
        for line_num, line in enumerate(lines, 1):
            code_only = self.get_code_only(line)
            if not code_only:
                continue
            
            # Check for textureStore(writeTexture
            if self.patterns['texture_store_write'].search(code_only):
                has_texture_store_write = True
            
            # Check for textureStore(writeDepthTexture
            if self.patterns['texture_store_depth'].search(code_only):
                has_texture_store_depth = True
            
            # Check for global_invocation_id
            if self.patterns['global_invocation_id'].search(code_only):
                has_global_id = True
            
            # Check for uniforms binding
            if self.patterns['uniforms_binding'].search(code_only):
                has_uniforms_binding = True
            
            # Check for bindings
            binding_match = self.patterns['binding_decl'].search(code_only)
            if binding_match:
                bindings_found.add(int(binding_match.group(1)))
            
            # Check for wrong sampler with depth texture
            if self.patterns['wrong_sampler_depth'].search(code_only):
                errors.append({
                    "type": "sampler_mismatch",
                    "line": line_num,
                    "description": "CRITICAL: Using u_sampler (filterable) with readDepthTexture. Depth textures require non_filtering_sampler. This causes: 'texture sample type isn't compatible with sampler'",
                    "code": code_only[:100]
                })
            
            # Check for non_filtering_sampler with color texture
            if self.patterns['wrong_sampler_color'].search(code_only):
                warnings.append({
                    "type": "sampler_mismatch",
                    "line": line_num,
                    "description": "Using non_filtering_sampler with readTexture. Color textures should use u_sampler for proper filtering.",
                    "code": code_only[:100]
                })
            
            # Check for comparison_sampler used with textureSampleLevel
            if self.patterns['comparison_sampler_direct'].search(code_only):
                errors.append({
                    "type": "sampler_mismatch",
                    "line": line_num,
                    "description": "CRITICAL: comparison_sampler should use textureSampleCompare, not textureSampleLevel",
                    "code": code_only[:100]
                })
            
            # Check workgroup size
            wg_match = self.patterns['workgroup_size'].search(code_only)
            if wg_match:
                x, y, z = int(wg_match.group(1)), int(wg_match.group(2)), int(wg_match.group(3))
                total = x * y * z
                max_workgroup_threads = max(max_workgroup_threads, total)
                if total > 256:
                    errors.append({
                        "type": "workgroup_size",
                        "line": line_num,
                        "description": f"CRITICAL: Workgroup size ({x}, {y}, {z}) = {total} exceeds WebGPU limit of 256 threads per workgroup",
                        "code": code_only[:100]
                    })
            
            # Check for infinite loops
            if self.patterns['infinite_loop'].search(code_only):
                errors.append({
                    "type": "infinite_loop",
                    "line": line_num,
                    "description": "CRITICAL: Potential infinite loop detected. WebGPU may timeout or crash.",
                    "code": code_only[:100]
                })
            
            # Check for u.ripples access with variable index
            ripple_match = self.patterns['ripples_access'].search(code_only)
            if ripple_match:
                index_expr = ripple_match.group(1)
                # Check if it's a loop variable with a bound
                if index_expr in ['i', 'idx', 'index', 'rippleIndex']:
                    # Look for a loop with bound before this line
                    if not has_ripple_loop_bound:
                        warnings.append({
                            "type": "array_bounds",
                            "line": line_num,
                            "description": f"Accessing u.ripples[{index_expr}]. Ensure loop bound is <= 50 to prevent out-of-bounds access.",
                            "code": code_only[:100]
                        })
                elif not index_expr.isdigit():
                    warnings.append({
                        "type": "array_bounds",
                        "line": line_num,
                        "description": f"Accessing u.ripples[{index_expr}] with non-constant index. Array size is 50 (indices 0-49). Add bounds check.",
                        "code": code_only[:100]
                    })
            
            # Check for plasmaBuffer access
            plasma_match = self.patterns['plasma_buffer_access'].search(code_only)
            if plasma_match:
                idx = plasma_match.group(1)
                if not idx.isdigit():
                    warnings.append({
                        "type": "array_bounds",
                        "line": line_num,
                        "description": f"Accessing plasmaBuffer[{idx}] without constant index. Ensure bounds are checked.",
                        "code": code_only[:100]
                    })
            
            # Check for extraBuffer access
            extra_match = self.patterns['extra_buffer_access'].search(code_only)
            if extra_match:
                idx = extra_match.group(1).strip()
                if not idx.replace('u', '').replace(' ', '').isdigit():
                    warnings.append({
                        "type": "array_bounds",
                        "line": line_num,
                        "description": f"Accessing extraBuffer with expression [{idx}]. Ensure index is within buffer bounds.",
                        "code": code_only[:100]
                    })
            
            # Check for division patterns that might cause division by zero
            # Only in actual code context (not comments)
            if '/' in code_only and not code_only.strip().startswith('//'):
                # Check for patterns like /variable where variable could be zero
                div_match = re.search(r'/\s*([a-zA-Z_][a-zA-Z0-9_\[\].]*)', code_only)
                if div_match:
                    divisor = div_match.group(1)
                    # Skip known safe patterns
                    safe_divisors = ['resolution', '2.0', '3.0', '4.0', 'PI', 'pi', '256', '255', 
                                     'w', 'h', 'width', 'height', 'dim', 'size', 'count', 'length',
                                     '32', '16', '8', '64', '128', 'aspect', 'gridSize', 'texSize']
                    if not any(d in divisor.lower() for d in safe_divisors):
                        # Check if there's a guard
                        context_before = '\n'.join(lines[max(0, line_num-5):line_num])
                        guards = ['> 0', '!= 0', '> 0.0', '!= 0.0', 'max(', 'abs(']
                        if not any(g in context_before for g in guards):
                            warnings.append({
                                "type": "division_by_zero",
                                "line": line_num,
                                "description": f"Potential division by zero: dividing by '{divisor}' without explicit zero check",
                                "code": code_only[:100]
                            })
        
        # Post-analysis checks for compute shaders with main function
        if has_main and has_compute:
            if not has_texture_store_write:
                errors.append({
                    "type": "missing_write",
                    "line": 0,
                    "description": "CRITICAL: Compute shader does not call textureStore(writeTexture, ...). All compute shaders must write to writeTexture or the pipeline will fail."
                })
            
            if not has_texture_store_depth:
                warnings.append({
                    "type": "missing_depth_write",
                    "line": 0,
                    "description": "Shader does not call textureStore(writeDepthTexture, ...). Depth pass-through is recommended for proper depth handling."
                })
            
            if not has_global_id:
                errors.append({
                    "type": "missing_builtin",
                    "line": 0,
                    "description": "CRITICAL: Compute shader missing @builtin(global_invocation_id) parameter in main function. Required for compute dispatch."
                })
            
            # Check for required bindings
            invalid_bindings = [b for b in bindings_found if b > 12]
            for binding in invalid_bindings:
                errors.append({
                    "type": "invalid_binding",
                    "line": 0,
                    "description": f"CRITICAL: Binding {binding} exceeds maximum allowed (12). BindGroupLayout only defines bindings 0-12. This causes: 'Binding doesn't exist in BindGroupLayout'"
                })
        
        # Determine severity
        critical_types = {'missing_write', 'missing_builtin', 'invalid_binding', 'workgroup_size', 
                         'sampler_mismatch', 'infinite_loop'}
        
        severity = "clean"
        if any(e['type'] in critical_types for e in errors):
            severity = "critical"
        elif errors:
            severity = "high"
        elif warnings:
            severity = "medium"
        
        # Combine all issues
        all_issues = errors + warnings
        
        if errors:
            status = "has_errors"
            self.error_count += 1
        elif warnings:
            status = "has_warnings"
            self.clean_count += 1
        else:
            status = "clean"
            self.clean_count += 1
        
        return {
            "shader_id": shader_id,
            "file": str(file_path),
            "status": status,
            "potential_runtime_errors": all_issues,
            "severity": severity
        }
    
    def analyze_all_shaders(self):
        """Analyze all WGSL shader files."""
        shader_files = sorted(self.shaders_dir.glob("*.wgsl"))
        self.total_shaders = len(shader_files)
        
        print(f"Agent 3: Runtime Error Detector")
        print(f"Analyzing {self.total_shaders} shaders for runtime errors...")
        print()
        
        # Use parallel processing for faster analysis
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
            futures = {executor.submit(self.analyze_shader, f): f for f in shader_files}
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                self.results.append(result)
                if len(self.results) % 100 == 0:
                    print(f"  Processed {len(self.results)}/{self.total_shaders} shaders...")
        
        # Sort results by shader_id
        self.results.sort(key=lambda x: x['shader_id'])
        
        print(f"\n✓ Analysis complete!")
        print(f"  Total shaders analyzed: {self.total_shaders}")
        print(f"  Clean: {self.clean_count}")
        print(f"  With errors: {self.error_count}")
    
    def generate_report(self, output_path: str = "runtime_errors_report.json"):
        """Generate the JSON report."""
        report = {
            "timestamp": datetime.now().isoformat(),
            "agent": "Agent 3: Runtime Error Detector",
            "mission": "Analyze shaders for patterns that cause runtime WebGPU errors",
            "total_shaders": self.total_shaders,
            "clean_count": self.clean_count,
            "error_count": self.error_count,
            "summary": {
                "critical": len([r for r in self.results if r['severity'] == 'critical']),
                "high": len([r for r in self.results if r['severity'] == 'high']),
                "medium": len([r for r in self.results if r['severity'] == 'medium']),
                "clean": len([r for r in self.results if r['severity'] == 'clean'])
            },
            "common_error_types": self._count_error_types(),
            "shaders": self.results
        }
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2)
        
        print(f"\nReport saved to: {output_path}")
        
        # Print detailed summary
        critical_shaders = [r for r in self.results if r['severity'] == 'critical']
        if critical_shaders:
            print(f"\n⚠️  CRITICAL ISSUES FOUND: {len(critical_shaders)} shaders")
            print("=" * 70)
            for shader in critical_shaders:
                print(f"\n  {shader['shader_id']}:")
                for issue in shader['potential_runtime_errors']:
                    if issue['type'] in ['missing_write', 'missing_builtin', 'invalid_binding', 
                                        'workgroup_size', 'sampler_mismatch', 'infinite_loop']:
                        print(f"    Line {issue['line']:4d}: [{issue['type']}]")
                        print(f"            {issue['description'][:80]}")
    
    def _count_error_types(self) -> Dict[str, int]:
        """Count occurrences of each error type."""
        counts = {}
        for result in self.results:
            for issue in result['potential_runtime_errors']:
                error_type = issue['type']
                counts[error_type] = counts.get(error_type, 0) + 1
        return dict(sorted(counts.items(), key=lambda x: -x[1]))

def main():
    detector = RuntimeErrorDetector("public/shaders")
    detector.analyze_all_shaders()
    detector.generate_report("runtime_errors_report.json")

if __name__ == "__main__":
    main()
