import json
import os
import sys

# Mappings for organization
CATEGORY_FOLDERS = {
    'liquid-effects': [
        'liquid', 'liquid-v1', 'liquid-zoom', 'liquid-perspective', 'liquid-viscous',
        'liquid-fast', 'liquid-rgb', 'liquid-metal', 'liquid-jelly', 'liquid-rainbow',
        'liquid-oil', 'liquid-glitch', 'liquid-viscous-simple', 'liquid-displacement',
        'liquid-smear', 'liquid-mirror', 'ambient-liquid'
    ],
    'retro-glitch': [
        'crt-tv', 'neon-edges', 'digital-glitch', 'halftone', 'digital-decay',
        'pixelation-drift', 'holographic-glitch', 'byte-mosh', 'spectrum-bleed',
        'digital-waves', 'vhs-jog', 'rgb-split-glitch'
    ],
    'simulation': [
        'wave-equation', 'photonic-caustics', 'pixel-sand', 'bitonic-sort',
        'flow-sort', 'predator-prey', 'boids', 'navier-stokes-dye', 'chromatographic-separation',
        'multi-turing', 'dla-crystals'
    ],
    'artistic': [
        'chromatic-manifold', 'bioluminescent', 'cosmic-flow', 'astral-veins',
        'radiating-haze', 'radiating-displacement', 'chromatic-infection', 'green-tracer',
        'chromatic-crawler', 'nebulous-dream', 'chromatic-folds', 'chromatic-folds-2',
        'aurora-rift', 'aurora-rift-2', 'stella-orbit', 'rainbow-cloud',
        'astral-kaleidoscope', 'chromatic-manifold-2', 'spectrogram-displace',
        'neon-edge-diffusion', 'plasma'
    ],
    'geometric': [
        'datamosh', 'ascii-glyph', 'time-lag-map'
    ]
}

# Force category to 'image' or 'shader' for UI visibility
# 'shader' = Procedural Generation
# 'image' = Effects / Filters
UI_CATEGORY_OVERRIDE = {
    'plasma': 'shader',
    'galaxy': 'shader',
    'boids': 'shader',
    'predator-prey': 'shader',
    'physarum': 'shader',
    # Most others are image filters
}

def load_old_list(filepath):
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return []

def get_existing_ids(root_dir):
    ids = set()
    for dirpath, dirnames, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.endswith('.json'):
                try:
                    with open(os.path.join(dirpath, filename), 'r') as f:
                        data = json.load(f)
                        if 'id' in data:
                            ids.add(data['id'])
                except:
                    pass
    return ids

def main():
    old_list = load_old_list('old-shader-list.md')
    existing_ids = get_existing_ids('shader_definitions')

    print(f"Found {len(old_list)} shaders in old list.")
    print(f"Found {len(existing_ids)} existing shaders definitions.")

    restored_count = 0

    for shader in old_list:
        sid = shader['id']

        # Skip if already exists
        if sid in existing_ids:
            continue

        # Determine folder
        target_folder = 'artistic' # Default
        for folder, ids in CATEGORY_FOLDERS.items():
            if sid in ids:
                target_folder = folder
                break

        # Determine UI category
        ui_category = UI_CATEGORY_OVERRIDE.get(sid, 'image')

        # Construct new shader definition
        new_def = {
            "id": shader['id'],
            "name": shader['name'],
            "url": shader['url'],
            "category": ui_category,
            "description": shader.get('description', '')
        }

        if 'params' in shader:
            new_def['params'] = shader['params']
        if 'features' in shader:
            new_def['features'] = shader['features']
        if 'advanced_params' in shader:
            # Maybe merge or keep? The current UI only renders 'params' (first 4) mostly.
            # But let's keep it for completeness if the schema allows.
            pass

        # Ensure directory exists
        full_folder_path = os.path.join('shader_definitions', target_folder)
        os.makedirs(full_folder_path, exist_ok=True)

        filepath = os.path.join(full_folder_path, f"{sid}.json")

        # Write file
        try:
            with open(filepath, 'w') as f:
                json.dump(new_def, f, indent=2)
            print(f"Restored: {sid} -> {filepath}")
            restored_count += 1
        except Exception as e:
            print(f"Failed to write {filepath}: {e}")

    print(f"Restored {restored_count} shaders.")

if __name__ == '__main__':
    main()
