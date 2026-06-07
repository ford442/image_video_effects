#!/usr/bin/env python3
"""
Standardize shader JSON categories to match the new category system.

This script:
1. Reads all shader definition JSON files
2. Maps folder-based categories to standardized values
3. Updates the "category" field in each file
4. Ensures consistent tagging
"""

import json
import os
from pathlib import Path
from typing import Dict, List, Set

# Base directory for shader definitions
SHADER_DEFS_DIR = Path("shader_definitions")

# Category mapping from folder names to standardized categories
FOLDER_TO_CATEGORY: Dict[str, str] = {
    "artistic": "artistic",
    "distortion": "distortion",
    "generative": "generative",
    "geometric": "geometric",
    "image": "image",
    "interactive-mouse": "interactive",
    "lighting-effects": "visual-effects",
    "liquid-effects": "liquid",
    "retro-glitch": "retro-glitch",
    "simulation": "simulation",
    "visual-effects": "visual-effects",
}

# Legacy category values that need to be remapped
CATEGORY_REMAP: Dict[str, str] = {
    "interactive-mouse": "interactive",
    "lighting-effects": "visual-effects",
    "liquid-effects": "liquid",
    "filter": "image",
    "reactive": "generative",
    "transition": "image",
    "tessellation": "geometric",
    "geometry": "geometric",
    "warp": "distortion",
    "feedback": "image",
    "shader": "generative",
    "glitch": "retro-glitch",
}

# Tags to add based on category
CATEGORY_TAGS: Dict[str, List[str]] = {
    "interactive": ["mouse-driven", "interactive"],
    "generative": ["procedural", "generative"],
    "simulation": ["simulation", "physics"],
    "distortion": ["warp", "distort", "transform"],
    "image": ["filter", "image-processing"],
    "artistic": ["stylized", "artistic"],
    "retro-glitch": ["glitch", "retro", "vintage"],
    "geometric": ["geometric", "pattern"],
    "visual-effects": ["vfx", "particles", "glow"],
    "liquid": ["fluid", "liquid", "water"],
}


def get_all_shader_files() -> List[Path]:
    """Get all JSON shader definition files."""
    json_files = []
    if SHADER_DEFS_DIR.exists():
        for folder in SHADER_DEFS_DIR.iterdir():
            if folder.is_dir():
                for json_file in folder.glob("*.json"):
                    json_files.append(json_file)
    return json_files


def standardize_category(shader_data: dict, folder_name: str) -> tuple[dict, bool]:
    """
    Standardize the category field in a shader definition.
    
    Returns:
        tuple: (updated_data, was_modified)
    """
    modified = False
    
    # Get current category
    current_category = shader_data.get("category", "").lower().strip()
    
    # Determine target category from folder first
    target_category = FOLDER_TO_CATEGORY.get(folder_name, folder_name)
    
    # If there's an existing category, check if it needs remapping
    if current_category:
        if current_category in CATEGORY_REMAP:
            target_category = CATEGORY_REMAP[current_category]
            modified = True
        elif current_category in FOLDER_TO_CATEGORY.values():
            # Already a valid category
            target_category = current_category
        else:
            # Unknown category, use folder-based
            modified = True
    else:
        # No category field, need to add it
        modified = True
    
    # Update category if different
    if shader_data.get("category") != target_category:
        shader_data["category"] = target_category
        modified = True
    
    # Ensure tags exist
    if "tags" not in shader_data:
        shader_data["tags"] = []
        modified = True
    
    # Add category-based tags if not present
    category_tags = CATEGORY_TAGS.get(target_category, [])
    existing_tags = set(t.lower() for t in shader_data["tags"])
    for tag in category_tags:
        if tag.lower() not in existing_tags:
            shader_data["tags"].append(tag)
            modified = True
    
    return shader_data, modified


def process_shader_file(json_file: Path) -> dict:
    """Process a single shader JSON file."""
    try:
        with open(json_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        folder_name = json_file.parent.name
        updated_data, modified = standardize_category(data, folder_name)
        
        if modified:
            with open(json_file, 'w', encoding='utf-8') as f:
                json.dump(updated_data, f, indent=2, ensure_ascii=False)
            return {"status": "updated", "file": str(json_file), "category": updated_data.get("category")}
        else:
            return {"status": "ok", "file": str(json_file), "category": updated_data.get("category")}
    
    except json.JSONDecodeError as e:
        return {"status": "error", "file": str(json_file), "error": f"Invalid JSON: {e}"}
    except Exception as e:
        return {"status": "error", "file": str(json_file), "error": str(e)}


def print_summary(results: List[dict]):
    """Print a summary of the processing results."""
    updated = [r for r in results if r["status"] == "updated"]
    errors = [r for r in results if r["status"] == "error"]
    ok = [r for r in results if r["status"] == "ok"]
    
    print("\n" + "=" * 60)
    print("CATEGORY STANDARDIZATION SUMMARY")
    print("=" * 60)
    print(f"Total files processed: {len(results)}")
    print(f"Updated: {len(updated)}")
    print(f"Already correct: {len(ok)}")
    print(f"Errors: {len(errors)}")
    
    if updated:
        print(f"\nUpdated files ({len(updated)}):")
        categories: Dict[str, int] = {}
        for r in updated:
            cat = r.get("category", "unknown")
            categories[cat] = categories.get(cat, 0) + 1
            print(f"  ✓ {r['file']} -> {cat}")
        
        print(f"\nCategory distribution:")
        for cat, count in sorted(categories.items(), key=lambda x: -x[1]):
            print(f"  {cat}: {count}")
    
    if errors:
        print(f"\nErrors ({len(errors)}):")
        for r in errors:
            print(f"  ✗ {r['file']}: {r['error']}")
    
    print("=" * 60)


def main():
    """Main entry point."""
    print("Shader Category Standardization Tool")
    print("=" * 60)
    
    # Change to the project directory
    script_dir = Path(__file__).parent.parent
    os.chdir(script_dir)
    
    # Get all shader files
    shader_files = get_all_shader_files()
    print(f"Found {len(shader_files)} shader definition files\n")
    
    if not shader_files:
        print("No shader files found. Make sure you're running from the project root.")
        return
    
    # Process all files
    results = []
    for i, json_file in enumerate(shader_files, 1):
        print(f"Processing [{i}/{len(shader_files)}]: {json_file}", end="\r")
        result = process_shader_file(json_file)
        results.append(result)
    
    print()  # New line after progress
    print_summary(results)


if __name__ == "__main__":
    main()
