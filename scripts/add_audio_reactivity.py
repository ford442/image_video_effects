#!/usr/bin/env python3
"""
Audio Reactivity Script for Phase B - Agent 4B
Adds audio reactivity to 50+ shaders
"""

import json
import os
import re
from pathlib import Path

BASE_DIR = Path("/workspaces/codepit/projects/image_video_effects")
SHADERS_DIR = BASE_DIR / "public" / "shaders"
DEFINITIONS_DIR = BASE_DIR / "shader_definitions"

# Shader categories and their audio input locations
AUDIO_INPUT_PATTERNS = {
    "generative": "u.config.y",  # config.y = AudioLow
    "image": "u.zoom_config.x",  # zoom_config.x = audio for image shaders
    "distortion": "u.zoom_config.x",
    "interactive-mouse": "u.zoom_config.x",
}

# Target shaders organized by priority
TARGET_SHADERS = {
    "high_priority": [
        "stellar-plasma",
        "gen-xeno-botanical-synth-flora",
        "tensor-flow-sculpting",
        "hyperbolic-dreamweaver",
        "liquid-metal",
        "voronoi-glass",
        "chromatic-manifold",
        "infinite-fractal-feedback",
        "ethereal-swirl",
        "gen-audio-spirograph",
    ],
    "medium_priority": [
        "quantum-superposition",
        "kimi_liquid_glass",
        "crystal-refraction",
        "gen-voronoi-crystal",
        "gen-supernova-remnant",
        "gen-string-theory",
        "plasma",
    ],
    "holographic": [
        "holographic-projection",
        "holographic-projection-gpt52",
        "holographic-projection-failure",
        "holographic-glitch",
        "holographic-contour",
        "holographic-sticker",
        "holographic-prism",
        "holographic-shatter",
        "holographic-edge-ripple",
    ],
    "neon": [
        "neon-pulse",
        "neon-light",
        "neon-edges",
        "neon-echo",
        "neon-warp",
        "neon-strings",
        "neon-fluid-warp",
        "neon-topology",
        "neon-edge-pulse",
        "neon-edge-reveal",
        "neon-pulse-edge",
        "neon-pulse-stream",
        "neon-contour-drag",
        "neon-contour-interactive",
        "neon-edge-diffusion",
        "neon-edge-radar",
        "neon-flashlight",
        "neon-cursor-trace",
    ],
    "vortex": [
        "vortex",
        "vortex-distortion",
        "vortex-warp",
        "vortex-prism",
        "vortex-drag",
        "velvet-vortex",
        "chroma-vortex",
    ],
    "phase_b_new": [
        "hyper-tensor-fluid",
        "neural-raymarcher",
        "chromatic-reaction-diffusion",
        "audio-voronoi-displacement",
        "fractal-boids-field",
        "holographic-interferometry",
        "gravitational-lensing",
        "cellular-automata-3d",
        "spectral-flow-sorting",
        "multi-fractal-compositor",
    ],
    "generative": [
        "gen-neural-fractal",
        "gen-mycelium-network",
        "gen-magnetic-field-lines",
        "gen-bifurcation-diagram",
        "gen-quantum-superposition",
        "gen-quantum-mycelium",
        "gen-quantum-neural-lace",
        "gen-quasicrystal",
        "gen-cosmic-web-filament",
        "gen-crystal-caverns",
        "gen-cymatic-plasma-mandalas",
        "gen-ethereal-anemone-bloom",
        "gen-stellar-web-loom",
        "gen-singularity-forge",
        "gen-liquid-crystal-hive-mind",
        "gen-magnetic-ferrofluid",
        "gen-prismatic-bismuth-lattice",
        "gen-chromatic-metamorphosis",
        "gen-chronos-labyrinth",
        "gen-hyper-labyrinth",
        "gen-fractal-clockwork",
        "gen-astro-kinetic-chrono-orrery",
        "gen-temporal-motion-smear",
        "gen-velocity-bloom",
        "gen-topology-flow",
        "gen-hyperbolic-tessellation",
        "gen-inverse-mandelbrot",
        "gen-cyber-terminal",
        "gen-biomechanical-hive",
        "gen-bismuth-crystal-citadel",
        "gen-brutalist-monument",
        "gen-celestial-forge",
        "gen-holographic-data-core",
        "gen-fractured-monolith",
        "gen-gravitational-strain",
        "gen-isometric-city",
        "gen-lenia-2",
        "gen-micro-cosmos",
        "gen-raptor-mini",
        "gen-silica-tsunami",
        "gen-feedback-echo-chamber",
        "gen-alien-flora",
        "gen-art-deco-sky",
    ],
}

def find_shader_json(shader_id: str) -> tuple[Path, Path] | None:
    """Find shader WGSL and JSON paths"""
    wgsl_path = SHADERS_DIR / f"{shader_id}.wgsl"
    
    # Search for JSON in all subdirectories
    for subdir in DEFINITIONS_DIR.iterdir():
        if subdir.is_dir():
            json_path = subdir / f"{shader_id}.json"
            if json_path.exists():
                return wgsl_path, json_path
    return None

def read_wgsl(wgsl_path: Path) -> str:
    """Read WGSL file"""
    if not wgsl_path.exists():
        return ""
    return wgsl_path.read_text()

def read_json(json_path: Path) -> dict:
    """Read JSON file"""
    if not json_path.exists():
        return {}
    return json.loads(json_path.read_text())

def save_wgsl(wgsl_path: Path, content: str):
    """Save WGSL file"""
    wgsl_path.write_text(content)

def save_json(json_path: Path, data: dict):
    """Save JSON file with proper formatting"""
    json_path.write_text(json.dumps(data, indent=2) + "\n")

def has_audio_reactivity(wgsl_code: str) -> bool:
    """Check if shader already has audio reactivity"""
    audio_patterns = [
        r'u\.config\.y',  # config.y (audio)
        r'u\.config\.z',  # config.z (audio mid)
        r'u\.config\.w',  # config.w (audio high)
        r'u\.zoom_config\.x',  # zoom_config.x (audio for image shaders)
        r'audio',
        r'Audio',
        r'extraBuffer\[0\]',  # bass
        r'extraBuffer\[1\]',  # mid
        r'extraBuffer\[2\]',  # treble
    ]
    return any(re.search(pattern, wgsl_code) for pattern in audio_patterns)

def add_audio_to_generative(wgsl_code: str) -> str:
    """Add audio reactivity to generative shader"""
    if has_audio_reactivity(wgsl_code):
        return wgsl_code
    
    # Find the main function and add audio input
    lines = wgsl_code.split('\n')
    new_lines = []
    added_audio = False
    
    for i, line in enumerate(lines):
        new_lines.append(line)
        
        # Add audio input after time is extracted
        if not added_audio and ('let time = u.config.x' in line or 'let time= u.config.x' in line):
            indent = len(line) - len(line.lstrip())
            new_lines.append(' ' * indent + '// ═══ AUDIO INPUT ═══')
            new_lines.append(' ' * indent + 'let audioOverall = u.config.y;')
            new_lines.append(' ' * indent + 'let audioBass = u.config.y;')
            new_lines.append(' ' * indent + 'let audioMid = u.config.z;')
            new_lines.append(' ' * indent + 'let audioHigh = u.config.w;')
            added_audio = True
    
    return '\n'.join(new_lines)

def add_audio_to_image(wgsl_code: str) -> str:
    """Add audio reactivity to image/video shader"""
    if has_audio_reactivity(wgsl_code):
        return wgsl_code
    
    lines = wgsl_code.split('\n')
    new_lines = []
    added_audio = False
    
    for i, line in enumerate(lines):
        new_lines.append(line)
        
        # Add audio input after time or uv extraction
        if not added_audio and ('let time = u.config.x' in line or 'let uv = ' in line):
            indent = len(line) - len(line.lstrip())
            new_lines.append(' ' * indent + '// ═══ AUDIO INPUT ═══')
            new_lines.append(' ' * indent + 'let audioOverall = u.zoom_config.x;')
            new_lines.append(' ' * indent + 'let audioBass = audioOverall * 1.5;')
            added_audio = True
    
    return '\n'.join(new_lines)

def modulate_time_with_audio(wgsl_code: str) -> str:
    """Modulate time-based animations with audio"""
    # Pattern: time * speed -> time * speed * (1.0 + audioOverall * 0.5)
    wgsl_code = re.sub(
        r'(time\s*\*\s*\w+)(?!\s*\*\s*\(1\.0\s*\+\s*audio)',
        r'\1 * (1.0 + audioOverall * 0.3)',
        wgsl_code
    )
    return wgsl_code

def add_beat_flash(wgsl_code: str) -> str:
    """Add beat flash effect before final color output"""
    if 'isBeat' in wgsl_code:
        return wgsl_code
    
    # Find the final color output and add beat flash before it
    lines = wgsl_code.split('\n')
    new_lines = []
    
    for line in lines:
        # Add beat detection before textureStore for writeTexture
        if 'textureStore(writeTexture' in line and 'final_color' in line:
            indent = len(line) - len(line.lstrip())
            new_lines.append(' ' * indent + '// ═══ BEAT FLASH ═══')
            new_lines.append(' ' * indent + 'let isBeat = step(0.7, audioBass);')
            new_lines.append(' ' * indent + 'final_color += vec4<f32>(isBeat * 0.15);')
        new_lines.append(line)
    
    return '\n'.join(new_lines)

def update_json_features(json_data: dict) -> dict:
    """Update JSON with audio-reactive features"""
    if 'features' not in json_data:
        json_data['features'] = []
    
    if 'audio-reactive' not in json_data['features']:
        json_data['features'].append('audio-reactive')
    
    if 'audio-driven' not in json_data['features']:
        json_data['features'].append('audio-driven')
    
    if 'tags' not in json_data:
        json_data['tags'] = []
    
    if 'audio' not in json_data['tags']:
        json_data['tags'].append('audio')
    
    if 'music' not in json_data['tags']:
        json_data['tags'].append('music')
    
    return json_data

def process_shader(shader_id: str, category_hint: str = None) -> dict:
    """Process a single shader"""
    result = {
        'shader_id': shader_id,
        'wgsl_updated': False,
        'json_updated': False,
        'error': None
    }
    
    # Find shader files
    paths = find_shader_json(shader_id)
    if not paths:
        result['error'] = f"Shader {shader_id} not found"
        return result
    
    wgsl_path, json_path = paths
    
    # Read files
    wgsl_code = read_wgsl(wgsl_path)
    json_data = read_json(json_path)
    
    if not wgsl_code:
        result['error'] = f"WGSL file not found: {wgsl_path}"
        return result
    
    # Determine category
    category = category_hint or json_data.get('category', 'generative')
    
    # Skip if already has audio reactivity in code
    if has_audio_reactivity(wgsl_code):
        # Just update JSON
        json_data = update_json_features(json_data)
        save_json(json_path, json_data)
        result['json_updated'] = True
        result['wgsl_updated'] = False
        return result
    
    # Add audio based on category
    if category in ['generative', 'artistic', 'hybrid']:
        wgsl_code = add_audio_to_generative(wgsl_code)
    else:
        wgsl_code = add_audio_to_image(wgsl_code)
    
    # Modulate time-based animations
    wgsl_code = modulate_time_with_audio(wgsl_code)
    
    # Add beat flash for generative shaders
    if category in ['generative', 'artistic']:
        wgsl_code = add_beat_flash(wgsl_code)
    
    # Update JSON
    json_data = update_json_features(json_data)
    
    # Save files
    save_wgsl(wgsl_path, wgsl_code)
    save_json(json_path, json_data)
    
    result['wgsl_updated'] = True
    result['json_updated'] = True
    
    return result

def main():
    """Main processing function"""
    results = []
    all_shaders = []
    
    # Collect all shaders
    for category, shaders in TARGET_SHADERS.items():
        for shader_id in shaders:
            all_shaders.append((shader_id, category))
    
    print(f"Processing {len(all_shaders)} shaders...")
    print("=" * 60)
    
    # Process each shader
    for shader_id, category in all_shaders:
        result = process_shader(shader_id, category)
        results.append(result)
        
        status = "✓" if result['wgsl_updated'] or result['json_updated'] else "○"
        if result['error']:
            status = "✗"
            print(f"{status} {shader_id}: {result['error']}")
        else:
            updates = []
            if result['wgsl_updated']:
                updates.append("WGSL")
            if result['json_updated']:
                updates.append("JSON")
            print(f"{status} {shader_id}: {', '.join(updates) if updates else 'Already has audio'}")
    
    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    
    wgsl_updated = sum(1 for r in results if r['wgsl_updated'])
    json_updated = sum(1 for r in results if r['json_updated'])
    errors = sum(1 for r in results if r['error'])
    
    print(f"Total shaders processed: {len(results)}")
    print(f"WGSL files updated: {wgsl_updated}")
    print(f"JSON files updated: {json_updated}")
    print(f"Errors: {errors}")
    
    # Save report
    report = {
        'total_processed': len(results),
        'wgsl_updated': wgsl_updated,
        'json_updated': json_updated,
        'errors': errors,
        'results': results
    }
    
    report_path = BASE_DIR / 'swarm-outputs' / 'audio-reactivity-report.json'
    report_path.parent.mkdir(exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2))
    print(f"\nReport saved to: {report_path}")

if __name__ == '__main__':
    main()
