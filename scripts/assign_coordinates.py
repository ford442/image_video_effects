#!/usr/bin/env python3
"""
Shader Coordinate Assigner
Assigns coordinates (0-1000) to all shaders based on visual characteristics
"""

import json
import os
from pathlib import Path

# Coordinate mapping logic
# 0-100:   Ambient / Liquid (slow, smooth)
# 100-250: Organic / Living (natural motion)
# 250-400: Interactive Mouse (responsive, fluid)
# 400-550: Artistic Stylization (filters, paint)
# 550-700: Visual Effects (glitch, chromatic, noise)
# 700-850: Retro / Glitch / Digital (artifacts, pixel)
# 850-1000: Extreme Distortion (black holes, heavy warp)

CATEGORY_BASE_COORDS = {
    "liquid-effects": 50,
    "generative": 150,
    "simulation": 200,
    "lighting-effects": 250,
    "interactive-mouse": 300,
    "artistic": 450,
    "image": 500,
    "visual-effects": 600,
    "geometric": 750,
    "retro-glitch": 780,
    "distortion": 900,
}

# Keyword-based adjustments
TEMPO_ADJUSTMENTS = {
    # High tempo = higher coordinate
    "fast": +50, "rapid": +60, "chaos": +70, "glitch": +40,
    "noise": +30, "shake": +40, "pulse": +20,
    # Low tempo = lower coordinate
    "slow": -30, "ambient": -40, "gentle": -25, "calm": -30,
    "smooth": -20, "flow": -10,
}

DISTORTION_ADJUSTMENTS = {
    # High distortion = higher coordinate
    "warp": +40, "lens": +35, "black-hole": +80, "gravitational": +70,
    "bend": +30, "twist": +25, "vortex": +40, "swirl": +20,
    "ripple": +15, "displace": +20,
}

STYLE_ADJUSTMENTS = {
    "crt": +20, "vhs": +25, "pixel": +15, "mosaic": +10,
    "ascii": +10, "dither": +15, "bayer": +15,
    "oil": -20, "watercolor": -25, "charcoal": -15,
    "paint": -10, "ink": -5,
}

def assign_coordinate(shader_data, folder_category):
    """Assign coordinate based on shader characteristics"""
    shader_id = shader_data.get("id", "")
    # Use folder category if available, fall back to JSON category
    category = folder_category or shader_data.get("category", "unknown")
    name = shader_data.get("name", "")
    description = shader_data.get("description", "")
    tags = shader_data.get("tags", []) or []
    features = shader_data.get("features", []) or []
    
    # Start with category base
    base = CATEGORY_BASE_COORDS.get(category, 500)
    
    # Create searchable text
    searchable = f"{shader_id} {name} {description} {' '.join(tags)} {' '.join(features)}".lower()
    
    # Apply adjustments
    adjustment = 0
    for keyword, adj in TEMPO_ADJUSTMENTS.items():
        if keyword in searchable:
            adjustment += adj
    for keyword, adj in DISTORTION_ADJUSTMENTS.items():
        if keyword in searchable:
            adjustment += adj
    for keyword, adj in STYLE_ADJUSTMENTS.items():
        if keyword in searchable:
            adjustment += adj
    
    # Special cases
    if "generative" in features or category == "generative":
        # Generative shaders vary widely, use keywords to place them
        if any(x in searchable for x in ["deep", "abyss", "ocean", "space", "cosmic"]):
            adjustment -= 50  # Slower, ambient generative
        elif any(x in searchable for x in ["particles", "swarm", "flock"]):
            adjustment += 30  # More active
    
    if "depth-aware" in features:
        adjustment += 10  # Slightly more complex
    
    # Calculate final coordinate
    coordinate = base + adjustment
    
    # Clamp to valid range
    coordinate = max(0, min(1000, coordinate))
    
    # Add small random offset based on shader_id hash to spread within category
    # (deterministic - same ID always gets same offset)
    hash_offset = hash(shader_id) % 20 - 10
    coordinate = max(0, min(1000, coordinate + hash_offset))
    
    return round(coordinate)

def generate_reason(shader_data, coordinate, folder_category):
    """Generate explanation for coordinate assignment"""
    category = folder_category or shader_data.get("category", "unknown")
    name = shader_data.get("name", "")
    tags = shader_data.get("tags", []) or []
    
    zone = ""
    if coordinate < 100:
        zone = "ambient/liquid"
    elif coordinate < 250:
        zone = "organic/living"
    elif coordinate < 400:
        zone = "interactive"
    elif coordinate < 550:
        zone = "artistic"
    elif coordinate < 700:
        zone = "visual effects"
    elif coordinate < 850:
        zone = "retro/digital"
    else:
        zone = "extreme distortion"
    
    return f"{category} → {zone} ({coordinate})"

def main():
    shader_defs_path = Path("/root/.openclaw/workspace/shader_definitions")
    coordinates = {}
    
    # Process all JSON files
    for json_file in sorted(shader_defs_path.rglob("*.json")):
        try:
            with open(json_file, 'r') as f:
                shader = json.load(f)
            
            shader_id = shader.get("id")
            if not shader_id:
                continue
            
            # Get category from folder name (parent folder of the JSON file)
            folder_category = json_file.parent.name
            
            coord = assign_coordinate(shader, folder_category)
            reason = generate_reason(shader, coord, folder_category)
            
            coordinates[shader_id] = {
                "coordinate": coord,
                "reason": reason,
                "name": shader.get("name", ""),
                "category": folder_category or shader.get("category", "unknown"),
                "features": shader.get("features", []) or [],
                "tags": shader.get("tags", []) or []
            }
        except Exception as e:
            print(f"Error processing {json_file}: {e}")
    
    # Sort by coordinate
    sorted_coords = dict(sorted(coordinates.items(), key=lambda x: x[1]["coordinate"]))
    
    # Output full mapping
    output_path = Path("/root/.openclaw/workspace/shader_coordinates.json")
    with open(output_path, 'w') as f:
        json.dump(sorted_coords, f, indent=2)
    
    print(f"Assigned coordinates to {len(sorted_coords)} shaders")
    print(f"Output saved to {output_path}")
    
    # Print sample of assignments
    print("\n=== Sample Assignments ===")
    for i, (shader_id, data) in enumerate(list(sorted_coords.items())[:30]):
        print(f"{data['coordinate']:3d}: {shader_id} ({data['name']})")
        print(f"     → {data['reason']}")
    
    print("\n...")
    
    print("\n=== End of Spectrum ===")
    for shader_id, data in list(sorted_coords.items())[-10:]:
        print(f"{data['coordinate']:3d}: {shader_id} ({data['name']})")
        print(f"     → {data['reason']}")
    
    return sorted_coords

if __name__ == "__main__":
    main()
