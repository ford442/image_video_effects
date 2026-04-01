#!/usr/bin/env python3
"""
Agent 4: Parameter Validator
Validates all shader JSON definitions against their WGSL implementations.
"""

import json
import os
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional, Set, Tuple

# Configuration
SHADER_DEFINITIONS_DIR = Path("/root/image_video_effects/shader_definitions")
SHADERS_DIR = Path("/root/image_video_effects/public/shaders")
OUTPUT_FILE = Path("/root/image_video_effects/param_validation_report.json")

# Valid categories (from AGENTS.md)
VALID_CATEGORIES = {
    "image", "generative", "interactive-mouse", "distortion", "simulation",
    "artistic", "visual-effects", "hybrid", "advanced-hybrid", "retro-glitch",
    "lighting-effects", "geometric", "liquid-effects", "post-processing"
}

# Valid param component mappings
PARAM_COMPONENTS = ["x", "y", "z", "w"]

class ShaderValidator:
    def __init__(self):
        self.results = []
        self.orphan_wgsl_files = []
        self.orphan_json_files = []
        self.json_to_wgsl_map = {}  # Maps shader_id -> (json_path, wgsl_path)
        self.wgsl_files_found = set()
        self.json_files_found = set()
        
    def find_all_files(self):
        """Find all JSON and WGSL files."""
        # Find all JSON files
        for json_file in SHADER_DEFINITIONS_DIR.rglob("*.json"):
            self.json_files_found.add(json_file)
            
        # Find all WGSL files
        for wgsl_file in SHADERS_DIR.rglob("*.wgsl"):
            # Skip template files and non-shader files
            if wgsl_file.name.startswith("_"):
                continue
            self.wgsl_files_found.add(wgsl_file)
            
    def parse_json(self, json_path: Path) -> Tuple[Optional[Dict], List[Dict]]:
        """Parse a JSON file and return the data and any issues."""
        issues = []
        data = None
        
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            issues.append({
                "type": "invalid_json",
                "description": f"JSON parse error: {str(e)}"
            })
            return None, issues
        except Exception as e:
            issues.append({
                "type": "file_read_error",
                "description": f"Failed to read file: {str(e)}"
            })
            return None, issues
            
        return data, issues
    
    def validate_json_structure(self, data: Any, json_path: Path) -> List[Dict]:
        """Validate the JSON structure has required fields."""
        issues = []
        
        # Ensure data is a dict
        if not isinstance(data, dict):
            issues.append({
                "type": "invalid_json_root",
                "description": f"JSON root must be an object, got {type(data).__name__}"
            })
            return issues
        
        # Check required fields
        required_fields = ["id", "name", "url", "category"]
        for field in required_fields:
            if field not in data:
                issues.append({
                    "type": "missing_required_field",
                    "description": f"Missing required field: '{field}'"
                })
        
        # Validate category
        if "category" in data:
            if data["category"] not in VALID_CATEGORIES:
                issues.append({
                    "type": "invalid_category",
                    "description": f"Invalid category '{data['category']}'. Valid: {sorted(VALID_CATEGORIES)}"
                })
        
        # Check id matches filename
        if "id" in data:
            expected_id = json_path.stem
            if data["id"] != expected_id:
                issues.append({
                    "type": "id_mismatch",
                    "description": f"ID '{data['id']}' doesn't match filename '{expected_id}'"
                })
        
        # Check url format
        if "url" in data:
            expected_url = f"shaders/{json_path.stem}.wgsl"
            if data["url"] != expected_url:
                issues.append({
                    "type": "url_mismatch",
                    "description": f"URL '{data['url']}' doesn't match expected '{expected_url}'"
                })
        
        return issues
    
    def validate_params(self, data: Dict) -> Tuple[List[Dict], bool]:
        """Validate parameter definitions. Returns (issues, is_valid)."""
        issues = []
        
        # Ensure data is a dict
        if not isinstance(data, dict):
            issues.append({
                "type": "invalid_json_root",
                "description": f"JSON root must be an object, got {type(data).__name__}"
            })
            return issues, False
        
        params = data.get("params", [])
        
        if not params:
            return [], True
        
        # Validate params is a list
        if not isinstance(params, list):
            issues.append({
                "type": "invalid_params_type",
                "description": f"Params must be a list, got {type(params).__name__}"
            })
            return issues, False
        
        # Check max params
        if len(params) > 4:
            issues.append({
                "type": "too_many_params",
                "description": f"Too many params: {len(params)} (max 4)"
            })
        
        # Check for duplicate param IDs (only for dict params)
        param_ids = []
        for p in params:
            if isinstance(p, dict):
                param_ids.append(p.get("id"))
            else:
                param_ids.append(str(p))
        
        seen_ids = set()
        for pid in param_ids:
            if pid in seen_ids:
                issues.append({
                    "type": "duplicate_param_id",
                    "description": f"Duplicate param ID: '{pid}'"
                })
            seen_ids.add(pid)
        
        # Validate each param
        for i, param in enumerate(params):
            if not isinstance(param, dict):
                issues.append({
                    "type": "invalid_param_type",
                    "description": f"Param[{i}] must be an object, got {type(param).__name__}: {param}"
                })
                continue
            param_issues = self._validate_single_param(param, i)
            issues.extend(param_issues)
        
        return issues, len(issues) == 0
    
    def _validate_single_param(self, param: Dict, index: int) -> List[Dict]:
        """Validate a single parameter definition."""
        issues = []
        param_prefix = f"Param[{index}]"
        
        # Check required fields
        required = ["id", "name", "default", "min", "max"]
        for field in required:
            if field not in param:
                issues.append({
                    "type": "missing_param_field",
                    "description": f"{param_prefix}: Missing required field '{field}'"
                })
        
        # Validate ranges
        if "min" in param and "max" in param:
            min_val = param["min"]
            max_val = param["max"]
            
            if min_val >= max_val:
                issues.append({
                    "type": "invalid_range",
                    "description": f"{param_prefix}: min ({min_val}) must be less than max ({max_val})"
                })
            
            # Check default is within range
            if "default" in param:
                default = param["default"]
                if default < min_val or default > max_val:
                    issues.append({
                        "type": "default_out_of_range",
                        "description": f"{param_prefix}: default ({default}) not in range [{min_val}, {max_val}]"
                    })
        
        # Validate step if present
        if "step" in param:
            step = param["step"]
            if step <= 0:
                issues.append({
                    "type": "invalid_step",
                    "description": f"{param_prefix}: step ({step}) must be positive"
                })
        
        return issues
    
    def analyze_wgsl(self, wgsl_path: Path) -> Tuple[Set[str], List[Dict]]:
        """Analyze WGSL file for zoom_params usage. Returns (used_components, issues)."""
        issues = []
        used_components = set()
        
        try:
            with open(wgsl_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except Exception as e:
            issues.append({
                "type": "wgsl_read_error",
                "description": f"Failed to read WGSL file: {str(e)}"
            })
            return set(), issues
        
        # Check for zoom_params usage patterns
        # Patterns like: u.zoom_params.x, zoom_params.x, etc.
        patterns = [
            r'u\.zoom_params\.(x|y|z|w)',
            r'zoom_params\.(x|y|z|w)',
        ]
        
        for pattern in patterns:
            matches = re.findall(pattern, content)
            for match in matches:
                used_components.add(match)
        
        # Check for workgroup_size (8,8,1 is standard per AGENTS.md, but 16,16,1 is also widely used)
        workgroup_match = re.search(r'@workgroup_size\((\d+),\s*(\d+),\s*(\d+)\)', content)
        if workgroup_match:
            x, y, z = int(workgroup_match.group(1)), int(workgroup_match.group(2)), int(workgroup_match.group(3))
            if (x, y, z) != (8, 8, 1):
                # This is a warning, not an error, as 16,16,1 is commonly used
                issues.append({
                    "type": "nonstandard_workgroup_size",
                    "description": f"Workgroup size ({x}, {y}, {z}) - standard is (8, 8, 1)"
                })
        
        # Check for required bindings
        required_bindings = [
            (r'@group\(0\)\s*@binding\(0\)', "sampler"),
            (r'@group\(0\)\s*@binding\(1\)', "readTexture"),
            (r'@group\(0\)\s*@binding\(2\)', "writeTexture"),
            (r'@group\(0\)\s*@binding\(3\)', "uniforms"),
        ]
        
        for pattern, name in required_bindings:
            if not re.search(pattern, content):
                issues.append({
                    "type": "missing_binding",
                    "description": f"Missing required binding: {name}"
                })
        
        # Check for textureStore call (any textureStore, not just writeTexture)
        if not re.search(r'textureStore\s*\(', content):
            issues.append({
                "type": "missing_texture_store",
                "description": "Missing any textureStore call"
            })
        
        return used_components, issues
    
    def cross_validate_params(self, json_data: Dict, wgsl_components: Set[str]) -> List[Dict]:
        """Cross-validate JSON params with WGSL zoom_params usage."""
        issues = []
        params = json_data.get("params", [])
        
        # Filter to only dict params
        valid_params = [p for p in params if isinstance(p, dict)]
        
        # Map param indices to components
        expected_components = set()
        for i in range(len(valid_params)):
            if i < 4:
                expected_components.add(PARAM_COMPONENTS[i])
        
        # Check if params defined in JSON are used in WGSL
        if valid_params:
            # Params are defined in JSON
            for i, param in enumerate(valid_params[:4]):  # Only first 4
                component = PARAM_COMPONENTS[i]
                if component not in wgsl_components:
                    issues.append({
                        "type": "unused_param",
                        "description": f"Param '{param.get('id', i)}' (zoom_params.{component}) defined in JSON but not used in WGSL"
                    })
        
        # Check if zoom_params used in WGSL have corresponding JSON params
        # This is a warning, not an error, as some shaders use zoom_params internally
        for component in wgsl_components:
            idx = PARAM_COMPONENTS.index(component)
            if idx >= len(valid_params):
                # Check if it's used for actual parameter control vs internal calculation
                issues.append({
                    "type": "unconfigured_param",
                    "description": f"zoom_params.{component} used in WGSL but no corresponding param defined in JSON (may be intentional for internal use)"
                })
        
        return issues
    
    def validate_shader(self, json_path: Path) -> Dict:
        """Validate a single shader definition."""
        result = {
            "shader_id": json_path.stem,
            "json_file": str(json_path.relative_to(Path("/root/image_video_effects"))),
            "wgsl_file": None,
            "status": "unknown",
            "issues": [],
            "params_valid": True,
            "params_used_in_wgsl": [],
            "json_params_count": 0,
            "wgsl_has_zoom_params": False
        }
        
        # Parse JSON
        data, parse_issues = self.parse_json(json_path)
        result["issues"].extend(parse_issues)
        
        if data is None:
            result["status"] = "invalid"
            result["params_valid"] = False
            return result
        
        # Validate JSON structure (if data is a dict)
        if isinstance(data, dict):
            structure_issues = self.validate_json_structure(data, json_path)
            result["issues"].extend(structure_issues)
        
        # Validate params
        param_issues, params_valid = self.validate_params(data)
        result["issues"].extend(param_issues)
        result["params_valid"] = params_valid
        
        # Count params (only valid dict params)
        if isinstance(data, dict):
            params = data.get("params", [])
            result["json_params_count"] = len([p for p in params if isinstance(p, dict)])
        else:
            result["json_params_count"] = 0
        
        # Find corresponding WGSL file
        wgsl_filename = json_path.stem + ".wgsl"
        wgsl_path = SHADERS_DIR / wgsl_filename
        
        if not wgsl_path.exists():
            # Try to find based on url field
            if "url" in data:
                alt_path = Path("/root/image_video_effects/public") / data["url"]
                if alt_path.exists():
                    wgsl_path = alt_path
            
            if not wgsl_path.exists():
                result["status"] = "invalid"
                result["issues"].append({
                    "type": "missing_wgsl_file",
                    "description": f"WGSL file not found: {wgsl_filename}"
                })
                self.orphan_json_files.append(str(result["json_file"]))
                return result
        
        result["wgsl_file"] = str(wgsl_path.relative_to(Path("/root/image_video_effects")))
        
        # Analyze WGSL
        wgsl_components, wgsl_issues = self.analyze_wgsl(wgsl_path)
        result["issues"].extend(wgsl_issues)
        result["params_used_in_wgsl"] = sorted(list(wgsl_components))
        result["wgsl_has_zoom_params"] = len(wgsl_components) > 0
        
        # Cross-validate (only if data is a dict)
        if isinstance(data, dict):
            cross_issues = self.cross_validate_params(data, wgsl_components)
            result["issues"].extend(cross_issues)
        
        # Determine final status
        if any(i["type"] in ["missing_wgsl_file", "missing_required_field", "invalid_json", 
                              "missing_texture_store", "missing_binding"] 
               for i in result["issues"]):
            result["status"] = "invalid"
        elif result["issues"]:
            result["status"] = "valid_with_warnings"
        else:
            result["status"] = "valid"
        
        return result
    
    def find_orphan_wgsl_files(self):
        """Find WGSL files without corresponding JSON definitions."""
        orphan_files = []
        
        for wgsl_path in self.wgsl_files_found:
            # Skip template and utility files
            if wgsl_path.name.startswith("_"):
                continue
                
            # Look for corresponding JSON
            shader_id = wgsl_path.stem
            json_found = False
            
            for json_path in self.json_files_found:
                if json_path.stem == shader_id:
                    json_found = True
                    break
            
            if not json_found:
                orphan_files.append(str(wgsl_path.relative_to(Path("/root/image_video_effects"))))
        
        return orphan_files
    
    def run_validation(self):
        """Run the full validation."""
        print("Agent 4: Parameter Validator - Starting validation...")
        
        # Find all files
        self.find_all_files()
        print(f"Found {len(self.json_files_found)} JSON files and {len(self.wgsl_files_found)} WGSL files")
        
        # Validate each JSON file
        for json_path in sorted(self.json_files_found):
            result = self.validate_shader(json_path)
            self.results.append(result)
        
        # Find orphan WGSL files
        self.orphan_wgsl_files = self.find_orphan_wgsl_files()
        
        # Find orphan JSON files (those with missing WGSL)
        self.orphan_json_files = [
            r["json_file"] for r in self.results 
            if any(i["type"] == "missing_wgsl_file" for i in r["issues"])
        ]
        
        # Generate report
        report = self.generate_report()
        
        # Write report
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2)
        
        print(f"\nValidation complete!")
        print(f"Total definitions: {report['total_definitions']}")
        print(f"Valid: {report['valid_count']}")
        print(f"Invalid: {report['invalid_count']}")
        print(f"Warnings: {report['warning_count']}")
        print(f"Orphan WGSL files: {len(report['orphan_wgsl_files'])}")
        print(f"Orphan JSON files: {len(report['orphan_json_files'])}")
        print(f"\nReport saved to: {OUTPUT_FILE}")
        
        return report
    
    def generate_report(self) -> Dict:
        """Generate the final validation report."""
        valid_count = sum(1 for r in self.results if r["status"] == "valid")
        invalid_count = sum(1 for r in self.results if r["status"] == "invalid")
        warning_count = sum(1 for r in self.results if r["status"] == "valid_with_warnings")
        
        # Categorize issues
        issue_types = {}
        for result in self.results:
            for issue in result["issues"]:
                issue_type = issue["type"]
                if issue_type not in issue_types:
                    issue_types[issue_type] = 0
                issue_types[issue_type] += 1
        
        return {
            "timestamp": datetime.now().isoformat(),
            "total_definitions": len(self.results),
            "valid_count": valid_count,
            "invalid_count": invalid_count,
            "warning_count": warning_count,
            "orphan_wgsl_files": sorted(self.orphan_wgsl_files),
            "orphan_json_files": sorted(self.orphan_json_files),
            "issue_summary": issue_types,
            "shaders": self.results
        }


def main():
    validator = ShaderValidator()
    report = validator.run_validation()
    
    # Print summary of issues
    print("\n=== Issue Summary ===")
    for issue_type, count in sorted(report["issue_summary"].items(), key=lambda x: -x[1]):
        print(f"  {issue_type}: {count}")

if __name__ == "__main__":
    main()
