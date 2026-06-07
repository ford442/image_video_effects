#!/usr/bin/env python3
"""
Audio Reactivity Script V2 for Phase B - Agent 4B
More aggressive audio reactivity injection for 50+ shaders
"""

import json
import os
import re
from pathlib import Path

BASE_DIR = Path("/workspaces/codepit/projects/image_video_effects")
SHADERS_DIR = BASE_DIR / "public" / "shaders"
DEFINITIONS_DIR = BASE_DIR / "shader_definitions"
OUTPUT_DIR = BASE_DIR / "swarm-outputs"

# The 50+ target shaders from the task specification
TARGET_SHADERS_PRIORITY = {
    # High Priority (10)
    "high": [
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
    # Medium Priority (10)
    "medium": [
        "quantum-superposition",
        "kimi_liquid_glass",
        "crystal-refraction",
        "gen-voronoi-crystal",
        "gen-supernova-remnant",
        "gen-string-theory",
        "plasma",
        # Holographic shaders
        "holographic-projection",
        "holographic-glitch",
        "holographic-contour",
    ],
    # Neon shaders (10)
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
    ],
    # Vortex shaders (5)
    "vortex": [
        "vortex",
        "vortex-distortion",
        "vortex-warp",
        "vortex-prism",
        "velvet-vortex",
    ],
    # Phase B New shaders (10)
    "phase_b": [
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
    # Generative shaders (10)
    "generative": [
        "gen-neural-fractal",
        "gen-mycelium-network",
        "gen-magnetic-field-lines",
        "gen-bifurcation-diagram",
        "gen-quantum-superposition",
        "gen-quantum-mycelium",
        "gen-quasicrystal",
        "gen-cymatic-plasma-mandalas",
        "gen-ethereal-anemone-bloom",
        "gen-singularity-forge",
    ],
}

def find_all_json_files():
    """Find all JSON definition files"""
    json_files = []
    for subdir in DEFINITIONS_DIR.iterdir():
        if subdir.is_dir():
            for json_file in subdir.glob("*.json"):
                json_files.append(json_file)
    return json_files

def find_wgsl_for_json(json_path: Path) -> Path | None:
    """Find WGSL file corresponding to a JSON definition"""
    data = json.loads(json_path.read_text())
    url = data.get('url', '')
    if url.startswith('shaders/'):
        return SHADERS_DIR / url.replace('shaders/', '')
    return None

def has_audio_variables(wgsl_code: str) -> bool:
    """Check if shader has audio variables defined"""
    audio_vars = ['audioOverall', 'audioBass', 'audioMid', 'audioHigh', 
                  'getAudioBass', 'getAudioOverall', 'getAudioMid']
    return any(var in wgsl_code for var in audio_vars)

def has_audio_usage(wgsl_code: str) -> bool:
    """Check if shader actually uses audio data"""
    # Look for audio data being used in calculations
    patterns = [
        r'u\.config\.y\s*\*',  # config.y used in multiplication
        r'u\.config\.z\s*\*',  # config.z used in multiplication
        r'u\.config\.w\s*\*',  # config.w used in multiplication
        r'u\.zoom_config\.x\s*\*',  # zoom_config.x used
        r'audioOverall\s*\*',
        r'audioBass\s*\*',
        r'audioMid\s*\*',
        r'audioHigh\s*\*',
        r'mix\([^)]*audio',
        r'\+\s*audio',
        r'\*\s*\(?\s*1\.0\s*\+\s*audio',
    ]
    return any(re.search(pattern, wgsl_code) for pattern in patterns)

def determine_category(json_data: dict, wgsl_code: str) -> str:
    """Determine shader category"""
    category = json_data.get('category', '')
    if category in ['generative']:
        return 'generative'
    elif category in ['image']:
        return 'image'
    elif category in ['distortion']:
        return 'distortion'
    elif category in ['interactive-mouse']:
        return 'interactive-mouse'
    elif 'textureSample' in wgsl_code:
        return 'image'  # Has texture sampling, likely an image shader
    else:
        return 'generative'  # Default to generative

def add_audio_reactivity(wgsl_code: str, category: str) -> str:
    """Add audio reactivity to WGSL code"""
    lines = wgsl_code.split('\n')
    new_lines = []
    audio_added = False
    
    # Audio input code based on category
    if category == 'generative':
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
    
    for i, line in enumerate(lines):
        new_lines.append(line)
        
        if not audio_added:
            # Insert after time extraction
            if 'let time = u.config.x' in line or 'let time=u.config.x' in line:
                indent = len(line) - len(line.lstrip())
                for ac in audio_code:
                    new_lines.append(' ' * indent + ac.replace('    ', ''))
                audio_added = True
    
    code = '\n'.join(new_lines)
    
    # Add audio modulation to time-based animations
    if 'time' in code and audio_added:
        # Modulate speed with audio
        code = re.sub(
            r'(time\s*\*\s*)([\w.]+)(?!\s*\*\s*audioReactivity)',
            r'\1\2 * audioReactivity',
            code
        )
    
    return code

def add_beat_effects(wgsl_code: str) -> str:
    """Add beat detection and flash effects"""
    if 'isBeat' in wgsl_code or 'textureStore' not in wgsl_code:
        return wgsl_code
    
    lines = wgsl_code.split('\n')
    new_lines = []
    
    # Find the last textureStore line index
    last_texture_store = -1
    for i, line in enumerate(lines):
        if 'textureStore(writeTexture' in line:
            last_texture_store = i
    
    if last_texture_store == -1:
        return wgsl_code
    
    for i, line in enumerate(lines):
        # Add beat flash before the texture store
        if i == last_texture_store and 'final_color' in wgsl_code:
            indent = len(line) - len(line.lstrip())
            new_lines.append(' ' * indent + '// ═══ BEAT SYNC ═══')
            new_lines.append(' ' * indent + 'let isBeat = step(0.7, audioBass);')
            new_lines.append(' ' * indent + 'let beatFlash = isBeat * 0.15;')
            new_lines.append(' ' * indent + 'final_color += vec4<f32>(beatFlash);')
        new_lines.append(line)
    
    return '\n'.join(new_lines)

def update_json(json_data: dict) -> dict:
    """Update JSON with audio-reactive features"""
    if 'features' not in json_data:
        json_data['features'] = []
    
    for feature in ['audio-reactive', 'audio-driven']:
        if feature not in json_data['features']:
            json_data['features'].append(feature)
    
    if 'tags' not in json_data:
        json_data['tags'] = []
    
    for tag in ['audio', 'music', 'reactive']:
        if tag not in json_data['tags']:
            json_data['tags'].append(tag)
    
    return json_data

def process_shader(shader_id: str) -> dict:
    """Process a single shader"""
    result = {
        'shader_id': shader_id,
        'status': 'not_found',
        'has_audio_vars': False,
        'has_audio_usage': False,
        'wgsl_updated': False,
        'json_updated': False,
    }
    
    # Find JSON
    json_path = None
    for subdir in DEFINITIONS_DIR.iterdir():
        if subdir.is_dir():
            candidate = subdir / f"{shader_id}.json"
            if candidate.exists():
                json_path = candidate
                break
    
    if not json_path:
        return result
    
    # Read files
    json_data = json.loads(json_path.read_text())
    wgsl_url = json_data.get('url', '')
    
    if not wgsl_url.startswith('shaders/'):
        result['status'] = 'invalid_url'
        return result
    
    wgsl_path = SHADERS_DIR / wgsl_url.replace('shaders/', '')
    
    if not wgsl_path.exists():
        result['status'] = 'wgsl_not_found'
        return result
    
    wgsl_code = wgsl_path.read_text()
    result['status'] = 'found'
    
    # Check current audio state
    result['has_audio_vars'] = has_audio_variables(wgsl_code)
    result['has_audio_usage'] = has_audio_usage(wgsl_code)
    
    # Skip if already has audio usage
    if result['has_audio_usage']:
        result['status'] = 'already_has_audio'
        # Still update JSON
        json_data = update_json(json_data)
        json_path.write_text(json.dumps(json_data, indent=2) + '\n')
        result['json_updated'] = True
        return result
    
    # Determine category
    category = determine_category(json_data, wgsl_code)
    
    # Add audio reactivity
    new_wgsl = add_audio_reactivity(wgsl_code, category)
    
    # Add beat effects for generative shaders
    if category == 'generative':
        new_wgsl = add_beat_effects(new_wgsl)
    
    # Save WGSL
    wgsl_path.write_text(new_wgsl)
    result['wgsl_updated'] = True
    
    # Update and save JSON
    json_data = update_json(json_data)
    json_path.write_text(json.dumps(json_data, indent=2) + '\n')
    result['json_updated'] = True
    result['status'] = 'updated'
    
    return result

def main():
    """Main function"""
    OUTPUT_DIR.mkdir(exist_ok=True)
    
    # Collect all target shaders
    all_targets = []
    for priority, shaders in TARGET_SHADERS_PRIORITY.items():
        for shader_id in shaders:
            all_targets.append((priority, shader_id))
    
    print(f"Processing {len(all_targets)} target shaders...")
    print("=" * 70)
    
    results = []
    for priority, shader_id in all_targets:
        result = process_shader(shader_id)
        result['priority'] = priority
        results.append(result)
        
        status_icon = {
            'not_found': '✗',
            'invalid_url': '✗',
            'wgsl_not_found': '✗',
            'found': '?',
            'already_has_audio': '○',
            'updated': '✓',
        }.get(result['status'], '?')
        
        print(f"{status_icon} [{priority:8}] {shader_id:40} - {result['status']}")
    
    # Summary
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    
    status_counts = {}
    for r in results:
        status_counts[r['status']] = status_counts.get(r['status'], 0) + 1
    
    for status, count in sorted(status_counts.items()):
        print(f"  {status}: {count}")
    
    wgsl_updated = sum(1 for r in results if r['wgsl_updated'])
    json_updated = sum(1 for r in results if r['json_updated'])
    
    print(f"\nWGSL files updated: {wgsl_updated}")
    print(f"JSON files updated: {json_updated}")
    
    # Save detailed report
    report = {
        'total': len(results),
        'wgsl_updated': wgsl_updated,
        'json_updated': json_updated,
        'status_counts': status_counts,
        'results': results,
    }
    
    report_path = OUTPUT_DIR / 'audio-reactivity-report-v2.json'
    report_path.write_text(json.dumps(report, indent=2))
    print(f"\nDetailed report: {report_path}")

if __name__ == '__main__':
    main()
