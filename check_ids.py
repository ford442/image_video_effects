import os
import json

target_ids = ['galaxy', 'imageVideo', 'liquid-render']

for root, dirs, files in os.walk('public/'): # check public/ where built lists might be? No, check shader_definitions
    pass

for root, dirs, files in os.walk('shader_definitions'):
    for file in files:
        if file.endswith('.json'):
            path = os.path.join(root, file)
            try:
                with open(path, 'r') as f:
                    data = json.load(f)
                    # Handle if it's a list or single object
                    if isinstance(data, list):
                        items = data
                    else:
                        items = [data]

                    for item in items:
                        if item.get('id') in target_ids:
                            print(f"Found {item.get('id')} in {path}")
                        if item.get('id') == 'liquid':
                             print(f"Found liquid in {path}")
            except Exception as e:
                print(f"Error reading {path}: {e}")
