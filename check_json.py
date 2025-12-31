import json
import sys

try:
    with open('public/shader-list.json', 'r') as f:
        data = json.load(f)
    print("JSON is valid.")
    print(f"Number of entries: {len(data)}")

    # Check for duplicates
    ids = [entry['id'] for entry in data]
    if len(ids) != len(set(ids)):
        print("Duplicate IDs found!")
        from collections import Counter
        print(Counter(ids).most_common(5))
    else:
        print("No duplicate IDs.")

except Exception as e:
    print(f"JSON Invalid: {e}")
    sys.exit(1)
