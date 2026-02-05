import urllib.request
import json
import sys

url = "http://localhost:3000/shader-lists/image.json"

try:
    with urllib.request.urlopen(url) as response:
        if response.status == 200:
            data = json.loads(response.read().decode())
            print(f"Successfully fetched image.json. Entries: {len(data)}")

            ids = [entry['id'] for entry in data]

            targets = ['plastic-bricks', 'page-curl-interactive', 'concentric-spin', 'gamma-ray-burst']
            missing = []

            for t in targets:
                if t in ids:
                    print(f"Found {t}")
                else:
                    missing.append(t)

            if missing:
                print(f"Missing: {missing}")
                sys.exit(1)
            else:
                print("All target shaders found in JSON.")
        else:
            print(f"Failed to fetch JSON: {response.status}")
            sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
