import json
import os
import sys

def load_old_list(filepath):
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return []

def load_new_definitions(root_dir):
    definitions = {}
    for dirpath, dirnames, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.endswith('.json'):
                filepath = os.path.join(dirpath, filename)
                try:
                    with open(filepath, 'r') as f:
                        data = json.load(f)
                        if 'id' in data:
                            definitions[data['id']] = data
                            definitions[data['id']]['_filepath'] = filepath
                except Exception as e:
                    print(f"Error reading {filepath}: {e}")
    return definitions

def compare_params(old_params, new_params):
    if not old_params and not new_params:
        return True
    if not old_params or not new_params:
        return False

    if len(old_params) != len(new_params):
        return False

    # Simple comparison by ID and some key attributes
    old_map = {p['id']: p for p in old_params}
    new_map = {p['id']: p for p in new_params}

    if set(old_map.keys()) != set(new_map.keys()):
        return False

    for pid, old_p in old_map.items():
        new_p = new_map[pid]
        # Compare commonly used fields
        for field in ['default', 'min', 'max']:
            if old_p.get(field) != new_p.get(field):
                return False

    return True

def main():
    old_list = load_old_list('old-shader-list.md')
    new_defs = load_new_definitions('shader_definitions')

    print(f"Total old shaders: {len(old_list)}")
    print(f"Total new definitions: {len(new_defs)}")

    missing_ids = []
    param_mismatches = []

    for old_shader in old_list:
        sid = old_shader['id']
        if sid not in new_defs:
            missing_ids.append(old_shader)
        else:
            new_shader = new_defs[sid]
            old_params = old_shader.get('params', [])
            new_params = new_shader.get('params', [])

            if not compare_params(old_params, new_params):
                param_mismatches.append({
                    'id': sid,
                    'old_params': old_params,
                    'new_params': new_params,
                    'filepath': new_shader['_filepath']
                })

    print("\n=== MISSING SHADERS ===")
    for s in missing_ids:
        print(f"{s['id']} ({s.get('name', 'Unknown')})")

    print("\n=== PARAMETER MISMATCHES ===")
    for m in param_mismatches:
        print(f"{m['id']}: Params differ")
        # print(f"  Old: {m['old_params']}")
        # print(f"  New: {m['new_params']}")

if __name__ == '__main__':
    main()
