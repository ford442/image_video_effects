#!/usr/bin/env python3
"""
BindGroup Compatibility Checker for Pixelocity Shaders
Agent 2: Validates all shaders match Renderer.ts bind group layout

IMPORTANT NOTES:
1. Variable names are flexible - only binding NUMBER and TYPE matter
2. Workgroup size (16, 16, 1) is widely used and accepted
3. imageVideo.wgsl is a VERTEX/FRAGMENT shader (not compute)
4. Some shaders intentionally use binding 13 for multi-pass effects
"""

import os
import re
import json
import glob
from datetime import datetime
from pathlib import Path

# Expected bindings configuration - binding numbers and types are MANDATORY
EXPECTED_BINDINGS = {
    0: {"type": "sampler", "access": None, "storage_class": None},
    1: {"type": "texture_2d<f32>", "access": None, "storage_class": None},
    2: {"type": "texture_storage_2d<rgba32float, write>", "access": "write", "storage_class": None},
    3: {"type": "Uniforms", "access": None, "storage_class": "uniform"},
    4: {"type": "texture_2d<f32>", "access": None, "storage_class": None},
    5: {"type": "sampler", "access": None, "storage_class": None},
    6: {"type": "texture_storage_2d<r32float, write>", "access": "write", "storage_class": None},
    7: {"type": "texture_storage_2d<rgba32float, write>", "access": "write", "storage_class": None},
    8: {"type": "texture_storage_2d<rgba32float, write>", "access": "write", "storage_class": None},
    9: {"type": "texture_2d<f32>", "access": None, "storage_class": None},
    10: {"type": "array<f32>", "access": "read_write", "storage_class": "storage"},
    11: {"type": "sampler_comparison", "access": None, "storage_class": None},
    12: {"type": "array<vec4<f32>>", "access": "read", "storage_class": "storage"},
}

# Expected Uniforms struct fields
EXPECTED_UNIFORMS_FIELDS = {
    "config": "vec4<f32>",
    "zoom_config": "vec4<f32>",
    "zoom_params": "vec4<f32>",
    "ripples": "array<vec4<f32>, 50>"
}

# Known special files
TEMPLATE_FILES = [
    "_hash_library.wgsl",
    "_template_shared_memory.wgsl",
    "_template_workgroup_atomics.wgsl",
    "gen_capabilities.wgsl",
]

# Vertex/Fragment shaders (not compute shaders)
RENDER_SHADERS = [
    "imageVideo.wgsl",
    "texture.wgsl",
]

# Regex patterns
BINDING_PATTERN = re.compile(
    r'@group\(0\)\s*@binding\((\d+)\)\s*var\s*(<[^>]+>)?\s*(\w+)\s*:\s*([^;]+);',
    re.MULTILINE
)

UNIFORM_STRUCT_PATTERN = re.compile(
    r'struct\s+Uniforms\s*\{([^}]+)\}',
    re.MULTILINE | re.DOTALL
)

WORKGROUP_PATTERN = re.compile(
    r'@compute\s+@workgroup_size\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)',
    re.MULTILINE
)

BINDING_13_PLUS_PATTERN = re.compile(
    r'@group\(0\)\s*@binding\((1[3-9]|[2-9]\d+)\)',
    re.MULTILINE
)

VERTEX_SHADER_PATTERN = re.compile(r'@vertex', re.MULTILINE)
FRAGMENT_SHADER_PATTERN = re.compile(r'@fragment', re.MULTILINE)
COMPUTE_SHADER_PATTERN = re.compile(r'@compute', re.MULTILINE)
STRUCT_FIELD_PATTERN = re.compile(r'(\w+)\s*:\s*([^,\n]+)', re.MULTILINE)

def normalize_type(type_str):
    return type_str.replace(" ", "").lower()

def check_type_match(binding_num, found_type, found_storage):
    """Check if found type matches expected type for a binding."""
    found_normalized = normalize_type(found_type)
    found_storage_lower = found_storage.lower() if found_storage else ""
    
    if binding_num == 0:
        return "sampler" in found_normalized and "comparison" not in found_normalized
    elif binding_num == 1:
        return "texture_2d<f32>" in found_normalized
    elif binding_num == 2:
        return ("texture_storage_2d" in found_normalized and 
                "rgba32float" in found_normalized and 
                "write" in found_normalized)
    elif binding_num == 3:
        return "uniforms" in found_normalized and "uniform" in found_storage_lower
    elif binding_num == 4:
        return "texture_2d<f32>" in found_normalized or "texture_depth_2d" in found_normalized
    elif binding_num == 5:
        return "sampler" in found_normalized and "comparison" not in found_normalized
    elif binding_num == 6:
        return ("texture_storage_2d" in found_normalized and 
                "r32float" in found_normalized and 
                "write" in found_normalized)
    elif binding_num == 7:
        return ("texture_storage_2d" in found_normalized and 
                "rgba32float" in found_normalized and 
                "write" in found_normalized)
    elif binding_num == 8:
        return ("texture_storage_2d" in found_normalized and 
                "rgba32float" in found_normalized and 
                "write" in found_normalized)
    elif binding_num == 9:
        return "texture_2d<f32>" in found_normalized
    elif binding_num == 10:
        has_array = "array" in found_normalized and "f32" in found_normalized
        has_rw = "read_write" in found_storage_lower
        return has_array and has_rw
    elif binding_num == 11:
        return "sampler_comparison" in found_normalized
    elif binding_num == 12:
        has_array = "array" in found_normalized and "vec4" in found_normalized
        has_read = "read" in found_storage_lower and "write" not in found_storage_lower
        return has_array and has_read
    return False

def parse_shader(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    shader_id = Path(filepath).stem
    filename = Path(filepath).name
    
    result = {
        "shader_id": shader_id,
        "file": filepath,
        "status": "compatible",
        "shader_type": "unknown",
        "is_template": filename in TEMPLATE_FILES,
        "missing_bindings": [],
        "wrong_type_bindings": [],
        "has_binding_13_plus": False,
        "texture_store_targets": [],
        "uniforms_struct": {"valid": True, "missing_fields": [], "extra_fields": []},
        "workgroup_sizes": [],
        "workgroup_size_valid": True,
        "errors": [],
        "warnings": []
    }
    
    # Determine shader type
    has_vertex = bool(VERTEX_SHADER_PATTERN.search(content))
    has_fragment = bool(FRAGMENT_SHADER_PATTERN.search(content))
    has_compute = bool(COMPUTE_SHADER_PATTERN.search(content))
    
    if has_vertex or has_fragment:
        result["shader_type"] = "render"
        result["status"] = "render_shader"
        result["warnings"].append("Render shader (vertex/fragment) - compute bind group checks not applicable")
        return result
    
    if not has_compute:
        result["shader_type"] = "unknown"
        result["status"] = "incompatible"
        result["errors"].append("No @compute, @vertex, or @fragment entry points found")
        return result
    
    result["shader_type"] = "compute"
    
    # Skip template files
    if filename in TEMPLATE_FILES:
        result["status"] = "template"
        result["warnings"].append("Template file - standard bind group checks skipped")
        return result
    
    # Extract all bindings
    found_bindings = {}
    for match in BINDING_PATTERN.finditer(content):
        binding_num = int(match.group(1))
        storage_class = match.group(2).strip() if match.group(2) else ""
        var_name = match.group(3)
        var_type = match.group(4).strip()
        found_bindings[binding_num] = {"name": var_name, "type": var_type, "storage_class": storage_class}
    
    # Check for bindings 13+
    binding_13_matches = BINDING_13_PLUS_PATTERN.findall(content)
    if binding_13_matches:
        result["has_binding_13_plus"] = True
        result["warnings"].append(f"Uses extended binding(s): {binding_13_matches}")
    
    # Check each expected binding
    for binding_num, expected in EXPECTED_BINDINGS.items():
        if binding_num not in found_bindings:
            result["missing_bindings"].append(binding_num)
            result["status"] = "incompatible"
            result["errors"].append(f"Missing binding {binding_num}")
        else:
            found = found_bindings[binding_num]
            if not check_type_match(binding_num, found["type"], found["storage_class"]):
                result["wrong_type_bindings"].append({
                    "binding": binding_num,
                    "var_name": found["name"],
                    "found_type": found["type"],
                    "storage_class": found["storage_class"]
                })
                result["status"] = "incompatible"
                result["errors"].append(
                    f"Binding {binding_num} ({found['name']}) has incompatible type: '{found['type']}'"
                )
    
    # Check Uniforms struct
    uniforms_match = UNIFORM_STRUCT_PATTERN.search(content)
    if uniforms_match:
        struct_content = uniforms_match.group(1)
        found_fields = {}
        for field_match in STRUCT_FIELD_PATTERN.finditer(struct_content):
            field_name = field_match.group(1).strip()
            field_type = field_match.group(2).strip()
            found_fields[field_name] = field_type
        
        for expected_name in EXPECTED_UNIFORMS_FIELDS:
            if expected_name not in found_fields:
                result["uniforms_struct"]["missing_fields"].append(expected_name)
                result["uniforms_struct"]["valid"] = False
        
        for found_name in found_fields:
            if found_name not in EXPECTED_UNIFORMS_FIELDS:
                result["uniforms_struct"]["extra_fields"].append(found_name)
        
        if not result["uniforms_struct"]["valid"]:
            result["status"] = "incompatible"
            result["errors"].append(
                f"Uniforms struct missing fields: {result['uniforms_struct']['missing_fields']}"
            )
    else:
        result["uniforms_struct"]["valid"] = False
        result["status"] = "incompatible"
        result["errors"].append("Uniforms struct not found")
    
    # Check workgroup sizes
    for match in WORKGROUP_PATTERN.finditer(content):
        x, y, z = int(match.group(1)), int(match.group(2)), int(match.group(3))
        result["workgroup_sizes"].append([x, y, z])
    
    if result["workgroup_sizes"]:
        has_valid = any(ws == [8, 8, 1] or ws == [16, 16, 1] for ws in result["workgroup_sizes"])
        if not has_valid:
            result["workgroup_size_valid"] = False
            result["status"] = "incompatible"
            result["errors"].append(f"Non-standard workgroup sizes: {result['workgroup_sizes']}")
    else:
        result["workgroup_size_valid"] = False
        result["status"] = "incompatible"
        result["errors"].append("No @workgroup_size found")
    
    # Check textureStore calls
    pattern = re.compile(r'textureStore\(\s*(\w+)\s*,', re.MULTILINE)
    result["texture_store_targets"] = pattern.findall(content)
    
    if not result["texture_store_targets"]:
        result["status"] = "incompatible"
        result["errors"].append("No textureStore calls found")
    
    return result

def main():
    shaders_dir = "/root/image_video_effects/public/shaders"
    report = {
        "timestamp": datetime.now().isoformat(),
        "total_shaders": 0,
        "compatible_count": 0,
        "incompatible_count": 0,
        "template_count": 0,
        "render_shader_count": 0,
        "shaders": [],
        "summary": {
            "by_category": {
                "compatible": [],
                "incompatible": [],
                "templates": [],
                "render_shaders": []
            },
            "issues": {
                "missing_bindings": {},
                "wrong_types": {},
                "invalid_workgroup": [],
                "missing_uniforms_fields": []
            }
        }
    }
    
    shader_files = sorted(glob.glob(os.path.join(shaders_dir, "*.wgsl")))
    report["total_shaders"] = len(shader_files)
    
    print(f"Checking {len(shader_files)} shaders for BindGroup compatibility...")
    print(f"Template files (skipped from compatibility count): {TEMPLATE_FILES}")
    print(f"Render shaders (vertex/fragment): {RENDER_SHADERS}")
    
    for i, filepath in enumerate(shader_files, 1):
        shader_id = Path(filepath).stem
        filename = Path(filepath).name
        
        if i % 100 == 0 or i == 1:
            print(f"  Processing {i}/{len(shader_files)}: {shader_id}")
        
        try:
            result = parse_shader(filepath)
            report["shaders"].append(result)
            
            if result["status"] == "template":
                report["template_count"] += 1
                report["summary"]["by_category"]["templates"].append(shader_id)
            elif result["status"] == "render_shader":
                report["render_shader_count"] += 1
                report["summary"]["by_category"]["render_shaders"].append(shader_id)
            elif result["status"] == "compatible":
                report["compatible_count"] += 1
                report["summary"]["by_category"]["compatible"].append(shader_id)
            else:
                report["incompatible_count"] += 1
                report["summary"]["by_category"]["incompatible"].append(shader_id)
                
                # Track issues
                for err in result["errors"]:
                    if "Missing binding" in err:
                        binding = err.split()[-1]
                        report["summary"]["issues"]["missing_bindings"][binding] = \
                            report["summary"]["issues"]["missing_bindings"].get(binding, 0) + 1
                    elif "incompatible type" in err.lower():
                        binding = err.split()[1]
                        report["summary"]["issues"]["wrong_types"][shader_id] = err
        except Exception as e:
            print(f"    ERROR parsing {shader_id}: {e}")
            report["shaders"].append({
                "shader_id": shader_id,
                "file": filepath,
                "status": "incompatible",
                "errors": [f"Parse error: {str(e)}"]
            })
            report["incompatible_count"] += 1
    
    # Write report
    report_path = "/root/image_video_effects/bindgroup_compatibility_report.json"
    with open(report_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2)
    
    print(f"\n{'='*70}")
    print(f"BINDGROUP COMPATIBILITY CHECK COMPLETE")
    print(f"{'='*70}")
    print(f"Total shaders checked: {report['total_shaders']}")
    print(f"  ✓ Compatible:       {report['compatible_count']}")
    print(f"  ✗ Incompatible:     {report['incompatible_count']}")
    print(f"  ⓘ Templates:        {report['template_count']}")
    print(f"  ⓘ Render shaders:   {report['render_shader_count']}")
    print(f"\nReport saved to: {report_path}")
    
    # Print issue statistics
    print(f"\n{'='*70}")
    print("ISSUE BREAKDOWN")
    print(f"{'='*70}")
    
    if report["summary"]["issues"]["missing_bindings"]:
        print("\nMissing bindings:")
        for binding, count in sorted(report["summary"]["issues"]["missing_bindings"].items(), 
                                      key=lambda x: int(x[0])):
            print(f"  Binding {binding}: {count} shaders")
    
    if report["summary"]["issues"]["wrong_types"]:
        print(f"\nWrong type bindings: {len(report['summary']['issues']['wrong_types'])} shaders")
    
    # Workgroup statistics
    wg_stats = {}
    for s in report["shaders"]:
        for ws in s.get("workgroup_sizes", []):
            key = f"({ws[0]}, {ws[1]}, {ws[2]})"
            wg_stats[key] = wg_stats.get(key, 0) + 1
    
    print("\nWorkgroup size distribution:")
    for size, count in sorted(wg_stats.items(), key=lambda x: -x[1]):
        marker = " ✓" if size in ["(8, 8, 1)", "(16, 16, 1)"] else " ⚠"
        print(f"  {size}: {count} occurrences{marker}")
    
    # Incompatible shader details
    incompatible = [s for s in report["shaders"] if s["status"] == "incompatible"]
    if incompatible:
        print(f"\n{'='*70}")
        print(f"INCOMPATIBLE SHADERS ({len(incompatible)})")
        print(f"{'='*70}")
        for s in incompatible[:20]:
            print(f"\n{s['shader_id']}:")
            for err in s['errors'][:3]:
                print(f"  • {err}")
        if len(incompatible) > 20:
            print(f"\n... and {len(incompatible) - 20} more")

if __name__ == "__main__":
    main()
