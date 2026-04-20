#!/usr/bin/env python3
"""
Batch 3: Add audio reactivity to more shaders to reach 50+
"""

import json
import re
from pathlib import Path

BASE_DIR = Path("/workspaces/codepit/projects/image_video_effects")
SHADERS_DIR = BASE_DIR / "public" / "shaders"
DEFINITIONS_DIR = BASE_DIR / "shader_definitions"

# Additional shaders to process
ADDITIONAL_SHADERS = [
    # More neon
    "neon-strings", "neon-fluid-warp", "neon-topology", "neon-flashlight",
    "neon-cursor-trace", "neon-pulse-edge", "neon-pulse-stream",
    "neon-contour-drag", "neon-contour-interactive", "neon-edge-diffusion",
    "neon-edge-radar",
    # More vortex
    "chroma-vortex",
    # More generative
    "gen-cosmic-web-filament", "gen-crystal-caverns", "gen-chromatic-metamorphosis",
    "gen-chronos-labyrinth", "gen-hyper-labyrinth", "gen-fractal-clockwork",
    "gen-astro-kinetic-chrono-orrery", "gen-temporal-motion-smear",
    "gen-velocity-bloom", "gen-topology-flow", "gen-hyperbolic-tessellation",
    "gen-inverse-mandelbrot", "gen-cyber-terminal", "gen-biomechanical-hive",
    "gen-bismuth-crystal-citadel", "gen-brutalist-monument", "gen-celestial-forge",
    "gen-holographic-data-core", "gen-fractured-monolith", "gen-gravitational-strain",
    "gen-isometric-city", "gen-lenia-2", "gen-micro-cosmos", "gen-raptor-mini",
    "gen-feedback-echo-chamber", "gen-alien-flora", "gen-art-deco-sky",
    # Artistic
    "bioluminescent", "breathing-kaleidoscope", "cosmic-flow", "dla-crystals",
    "galaxy", "nebula-gyroid", "quantum-fractal", "reaction-diffusion",
    "physarum", "stella-orbit", "temporal-echo",
    # Distortion
    "fractal-kaleidoscope", "julia-warp", "kaleidoscope", "liquid-swirl",
    "vortex-warp", "elastic-surface", "fluid-grid",
]

def has_audio_reactivity(wgsl_code):
    return 'audioReactivity' in wgsl_code or 'audioOverall' in wgsl_code

def add_audio(wgsl_code, category):
    if has_audio_reactivity(wgsl_code):
        return wgsl_code, False
    
    lines = wgsl_code.split('\n')
    new_lines = []
    added = False
    
    if category in ['generative', 'artistic']:
        audio_code = [
            '    // ═══ AUDIO REACTIVITY ═══',
            '    let audioOverall = u.config.y;',
            '    let audioBass = u.config.y * 1.2;',
            '    let audioMid = u.config.z;',
            '    let audioHigh = u.config.w;',
            '    let audioReactivity = 1.0 + audioOverall * 0.5;',
        ]
    else:
        audio_code = [
            '    // ═══ AUDIO REACTIVITY ═══',
            '    let audioOverall = u.zoom_config.x;',
            '    let audioBass = audioOverall * 1.5;',
            '    let audioReactivity = 1.0 + audioOverall * 0.3;',
        ]
    
    for line in lines:
        new_lines.append(line)
        if not added and 'let time = u.config.x' in line:
            indent = len(line) - len(line.lstrip())
            for ac in audio_code:
                new_lines.append(' ' * indent + ac.replace('    ', ''))
            added = True
    
    if not added:
        return wgsl_code, False
    
    code = '\n'.join(new_lines)
    
    # Modulate time-based animations
    code = re.sub(
        r'(time\s*\*\s*)([\w.]+)(?!\s*\*\s*audioReactivity)',
        r'\1\2 * audioReactivity',
        code
    )
    
    return code, True

def update_json(json_data):
    if 'features' not in json_data:
        json_data['features'] = []
    for f in ['audio-reactive', 'audio-driven']:
        if f not in json_data['features']:
            json_data['features'].append(f)
    
    if 'tags' not in json_data:
        json_data['tags'] = []
    for t in ['audio', 'music', 'reactive']:
        if t not in json_data['tags']:
            json_data['tags'].append(t)
    return json_data

def find_files(shader_id):
    for subdir in DEFINITIONS_DIR.iterdir():
        if subdir.is_dir():
            json_path = subdir / f"{shader_id}.json"
            if json_path.exists():
                wgsl_path = SHADERS_DIR / f"{shader_id}.wgsl"
                if wgsl_path.exists():
                    return json_path, wgsl_path
    return None, None

def main():
    updated = 0
    already_have = 0
    not_found = 0
    
    print(f"Processing {len(ADDITIONAL_SHADERS)} additional shaders...")
    print("=" * 60)
    
    for shader_id in ADDITIONAL_SHADERS:
        json_path, wgsl_path = find_files(shader_id)
        
        if not json_path:
            print(f"✗ {shader_id}: not found")
            not_found += 1
            continue
        
        wgsl_code = wgsl_path.read_text()
        json_data = json.loads(json_path.read_text())
        
        if has_audio_reactivity(wgsl_code):
            print(f"○ {shader_id}: already has audio")
            already_have += 1
            # Still update JSON
            json_data = update_json(json_data)
            json_path.write_text(json.dumps(json_data, indent=2) + '\n')
            continue
        
        category = json_data.get('category', 'generative')
        new_code, success = add_audio(wgsl_code, category)
        
        if success:
            wgsl_path.write_text(new_code)
            json_data = update_json(json_data)
            json_path.write_text(json.dumps(json_data, indent=2) + '\n')
            print(f"✓ {shader_id}: updated")
            updated += 1
        else:
            print(f"? {shader_id}: could not add audio")
    
    print("=" * 60)
    print(f"Updated: {updated}")
    print(f"Already had audio: {already_have}")
    print(f"Not found: {not_found}")
    
    # Count total with audioReactivity
    import subprocess
    result = subprocess.run(
        ['grep', '-l', 'audioReactivity', str(SHADERS_DIR)],
        capture_output=True, text=True
    )
    total_with_audio = len([l for l in result.stdout.split('\n') if l.strip()])
    print(f"\nTotal shaders with audioReactivity: {total_with_audio}")

if __name__ == '__main__':
    main()
