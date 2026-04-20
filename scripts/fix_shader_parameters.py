#!/usr/bin/env python3
"""
Shader Parameter Audit Fix Script

Applies parameter and mouse reactivity fixes based on SHADER_PARAMETER_AUDIT.md

Usage: python3 fix_shader_parameters.py [--dry-run]
"""

import json
import os
import re
from pathlib import Path
from typing import Dict, List, Optional

# Base directory
BASE_DIR = Path("/root/image_video_effects")
SHADER_DEFS_DIR = BASE_DIR / "shader_definitions"
SHADERS_DIR = BASE_DIR / "public" / "shaders"

# Parameter templates for different shader types
PARAM_TEMPLATES = {
    "intensity": {
        "id": "intensity",
        "name": "Effect Intensity",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.x",
        "description": "Overall strength of the effect"
    },
    "speed": {
        "id": "speed", 
        "name": "Animation Speed",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.y",
        "description": "Speed of the animation"
    },
    "scale": {
        "id": "scale",
        "name": "Feature Scale", 
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.z",
        "description": "Size of visual features"
    },
    "glow": {
        "id": "glow",
        "name": "Glow/Bloom",
        "default": 0.3,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.w",
        "description": "Glow intensity"
    },
    "viscosity": {
        "id": "viscosity",
        "name": "Viscosity",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.x",
        "description": "Liquid thickness/resistance"
    },
    "turbulence": {
        "id": "turbulence",
        "name": "Turbulence",
        "default": 0.4,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.y",
        "description": "Chaotic flow intensity"
    },
    "ripple_strength": {
        "id": "ripple_strength",
        "name": "Ripple Strength",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.z",
        "description": "Wave distortion amount"
    },
    "color_shift": {
        "id": "color_shift",
        "name": "Color Shift",
        "default": 0.3,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.w",
        "description": "Color manipulation amount"
    }
}

# Shaders needing only param4 (w) - 14 shaders
MISSING_PARAM4 = {
    "chromatic-shockwave": {
        "param4": {"name": "Ring Count", "mapping": "zoom_params.w", "default": 0.5, "description": "Number of shockwave rings"}
    },
    "dynamic-halftone": {
        "param4": {"name": "Edge Sharpness", "mapping": "zoom_params.w", "default": 0.5, "description": "Halftone edge sharpness"}
    },
    "galaxy-compute": {
        "param4": {"name": "Galaxy Twist", "mapping": "zoom_params.w", "default": 0.5, "description": "Rotation/twist of galaxy arms"}
    },
    "halftone": {
        "param4": {"name": "Grid Rotation", "mapping": "zoom_params.w", "default": 0.0, "description": "Rotation angle of halftone grid"},
        "features": ["mouse-driven"]
    },
    "interactive-emboss": {
        "param4": {"name": "Emboss Depth", "mapping": "zoom_params.w", "default": 0.5, "description": "Depth of emboss effect"}
    },
    "kaleidoscope": {
        "param4": {"name": "Center Zoom", "mapping": "zoom_params.w", "default": 0.3, "description": "Zoom at kaleidoscope center"},
        "features": ["mouse-driven"]
    },
    "pixel-rain": {
        "param4": {"name": "Trail Fade", "mapping": "zoom_params.w", "default": 0.7, "description": "Trail persistence/fade rate"}
    },
    "quantum-fractal": {
        "param4": {"name": "Edge Glow", "mapping": "zoom_params.w", "default": 0.3, "description": "Glow on fractal edges"},
        "features": ["mouse-driven"]
    },
    "selective-color": {
        "param4": {"name": "Saturation Boost", "mapping": "zoom_params.w", "default": 0.5, "description": "Color saturation enhancement"}
    },
    "spectral-vortex": {
        "param4": {"name": "Color Dispersion", "mapping": "zoom_params.w", "default": 0.4, "description": "Spectral color separation"},
        "features": ["mouse-driven"]
    },
    "tile-twist": {
        "param4": {"name": "Edge Smoothness", "mapping": "zoom_params.w", "default": 0.5, "description": "Smoothness of tile edges"}
    },
    "vortex-warp": {
        "param4": {"name": "Turbulence", "mapping": "zoom_params.w", "default": 0.4, "description": "Vortex turbulence amount"}
    }
}

# Shaders needing param3 (z) - 2 shaders
MISSING_PARAM3 = {
    "infinite-zoom": {
        "param3": {"name": "Perspective Strength", "mapping": "zoom_params.z", "default": 0.5, "description": "Strength of perspective effect"}
    },
    "chromatic-manifold": {
        "param3": {"name": "Point Scatter", "mapping": "zoom_params.z", "default": 0.3, "description": "Scatter amount of points"}
    }
}

# Liquid shaders needing full 4 params + viscosity/turbulence - 14 shaders
LIQUID_SHADERS = [
    "ambient-liquid", "liquid-fast", "liquid-glitch", "liquid-jelly",
    "liquid-oil", "liquid-perspective", "liquid-rainbow", "liquid-rgb",
    "liquid", "liquid-viscous-simple", "liquid-viscous", "melting-oil",
    "navier-stokes-dye", "neon-edge-diffusion"
]

# Shaders needing mouse reactivity - 12 shaders
NEEDS_MOUSE = [
    ("crt-tv", ["mouse-driven"]),
    ("digital-decay", ["mouse-driven"]),
    ("galaxy", ["mouse-driven"]),
    ("halftone", ["mouse-driven"]),
    ("holographic-glitch", ["mouse-driven"]),
    ("kaleidoscope", ["mouse-driven"]),
    ("liquid", ["mouse-driven"]),
    ("neon-edges", ["mouse-driven"]),
    ("pixelation-drift", ["mouse-driven"]),
    ("plasma", ["mouse-driven"]),
    ("rain", ["mouse-driven"]),
    ("sine-wave", ["mouse-driven"]),
    ("snow", ["mouse-driven"]),
    ("spectrum-bleed", ["mouse-driven"]),
    ("stella-orbit", ["mouse-driven"])
]

def load_shader_def(shader_id: str) -> Optional[Dict]:
    """Find and load a shader definition JSON file."""
    # Search in all subdirectories
    for json_file in SHADER_DEFS_DIR.rglob("*.json"):
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
                # Skip if data is not a dict (some files might be lists)
                if not isinstance(data, dict):
                    continue
                if data.get('id') == shader_id:
                    return data, json_file
        except (json.JSONDecodeError, IOError):
            continue
    return None, None

def save_shader_def(data: Dict, filepath: Path):
    """Save shader definition back to JSON."""
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)

def create_param(name: str, mapping: str, default: float = 0.5, 
                 description: str = "", min_val: float = 0.0, 
                 max_val: float = 1.0, step: float = 0.01) -> Dict:
    """Create a parameter dictionary."""
    param_id = name.lower().replace(' ', '_').replace('/', '_')
    return {
        "id": param_id,
        "name": name,
        "default": default,
        "min": min_val,
        "max": max_val,
        "step": step,
        "mapping": mapping,
        "description": description
    }

def fix_missing_param4(dry_run: bool = False):
    """Fix shaders that are missing only param4."""
    print("\n=== Fixing shaders missing param4 (w) ===")
    fixed = 0
    
    for shader_id, config in MISSING_PARAM4.items():
        data, filepath = load_shader_def(shader_id)
        if not data:
            print(f"  ⚠️  Shader not found: {shader_id}")
            continue
        
        params = data.get('params', [])
        
        # Check if already has 4 params
        if len(params) >= 4:
            print(f"  ✅ {shader_id}: Already has 4+ params")
            continue
        
        # Add param4
        p4_config = config.get('param4', {})
        param4 = create_param(
            p4_config.get('name', 'Effect Strength'),
            p4_config.get('mapping', 'zoom_params.w'),
            p4_config.get('default', 0.5),
            p4_config.get('description', 'Additional effect control')
        )
        params.append(param4)
        data['params'] = params
        
        # Add features if specified
        if 'features' in config:
            features = data.get('features', [])
            for feat in config['features']:
                if feat not in features:
                    features.append(feat)
            data['features'] = features
        
        if not dry_run:
            save_shader_def(data, filepath)
        
        print(f"  ✅ {shader_id}: Added param4 ({len(params)} total params)")
        fixed += 1
    
    print(f"Fixed {fixed} shaders")
    return fixed

def fix_missing_param3(dry_run: bool = False):
    """Fix shaders that are missing param3 (z)."""
    print("\n=== Fixing shaders missing param3 (z) ===")
    fixed = 0
    
    for shader_id, config in MISSING_PARAM3.items():
        data, filepath = load_shader_def(shader_id)
        if not data:
            print(f"  ⚠️  Shader not found: {shader_id}")
            continue
        
        params = data.get('params', [])
        
        # Check if already has 3+ params
        if len(params) >= 3:
            print(f"  ✅ {shader_id}: Already has 3+ params")
            continue
        
        # Need to add params up to 3
        p3_config = config.get('param3', {})
        param3 = create_param(
            p3_config.get('name', 'Feature Scale'),
            p3_config.get('mapping', 'zoom_params.z'),
            p3_config.get('default', 0.5),
            p3_config.get('description', 'Scale of visual features')
        )
        params.append(param3)
        data['params'] = params
        
        if not dry_run:
            save_shader_def(data, filepath)
        
        print(f"  ✅ {shader_id}: Added param3 ({len(params)} total params)")
        fixed += 1
    
    print(f"Fixed {fixed} shaders")
    return fixed

def fix_liquid_shaders(dry_run: bool = False):
    """Fix liquid shaders with full 4 params + viscosity/turbulence."""
    print("\n=== Fixing liquid shaders with 4 params ===")
    fixed = 0
    
    liquid_params = [
        PARAM_TEMPLATES["viscosity"],
        PARAM_TEMPLATES["turbulence"],
        PARAM_TEMPLATES["ripple_strength"],
        PARAM_TEMPLATES["color_shift"]
    ]
    
    for shader_id in LIQUID_SHADERS:
        data, filepath = load_shader_def(shader_id)
        if not data:
            print(f"  ⚠️  Shader not found: {shader_id}")
            continue
        
        params = data.get('params', [])
        
        # If already has 4+ params, skip
        if len(params) >= 4:
            print(f"  ✅ {shader_id}: Already has 4+ params ({len(params)})")
            continue
        
        # Replace with full liquid params
        data['params'] = liquid_params.copy()
        
        # Ensure mouse-driven feature
        features = data.get('features', [])
        if 'mouse-driven' not in features:
            features.append('mouse-driven')
        data['features'] = features
        
        if not dry_run:
            save_shader_def(data, filepath)
        
        print(f"  ✅ {shader_id}: Set 4 liquid params")
        fixed += 1
    
    print(f"Fixed {fixed} shaders")
    return fixed

def fix_mouse_reactivity(dry_run: bool = False):
    """Add mouse reactivity to shaders that need it."""
    print("\n=== Adding mouse reactivity ===")
    fixed = 0
    
    for shader_id, features_to_add in NEEDS_MOUSE:
        data, filepath = load_shader_def(shader_id)
        if not data:
            print(f"  ⚠️  Shader not found: {shader_id}")
            continue
        
        features = data.get('features', [])
        added = []
        
        for feat in features_to_add:
            if feat not in features:
                features.append(feat)
                added.append(feat)
        
        if added:
            data['features'] = features
            if not dry_run:
                save_shader_def(data, filepath)
            print(f"  ✅ {shader_id}: Added features {added}")
            fixed += 1
        else:
            print(f"  ✅ {shader_id}: Already has mouse features")
    
    print(f"Fixed {fixed} shaders")
    return fixed

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Fix shader parameters based on audit')
    parser.add_argument('--dry-run', action='store_true', 
                        help='Show what would be changed without modifying files')
    args = parser.parse_args()
    
    if args.dry_run:
        print("🔍 DRY RUN MODE - No files will be modified")
    
    print("Starting Shader Parameter Audit Fix")
    print("=" * 50)
    
    total_fixed = 0
    total_fixed += fix_missing_param4(args.dry_run)
    total_fixed += fix_missing_param3(args.dry_run)
    total_fixed += fix_liquid_shaders(args.dry_run)
    total_fixed += fix_mouse_reactivity(args.dry_run)
    
    print("\n" + "=" * 50)
    print(f"🏁 Complete! Fixed {total_fixed} shaders")
    
    if args.dry_run:
        print("\n💡 This was a dry run. Remove --dry-run to apply changes.")

if __name__ == "__main__":
    main()
