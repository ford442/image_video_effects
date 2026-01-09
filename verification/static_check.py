import json
import os
import sys
from playwright.sync_api import sync_playwright

def verify_shader_presence():
    # 1. Verify files exist
    shaders = [
        "public/shaders/spiral-lens.wgsl",
        "public/shaders/glass-brick-distortion.wgsl"
    ]
    definitions = [
        "shader_definitions/distortion/spiral-lens.json",
        "shader_definitions/distortion/glass-brick-distortion.json"
    ]

    for f in shaders + definitions:
        if not os.path.exists(f):
            print(f"ERROR: File missing: {f}")
            sys.exit(1)

    # 2. Verify JSON content
    for d in definitions:
        with open(d, 'r') as f:
            data = json.load(f)
            if data['category'] != 'image':
                 print(f"ERROR: {d} must have category 'image' to be visible in Controls.")
                 sys.exit(1)
            print(f"Verified {d}: {data['label']}")

    # 3. Simulate UI check (Headless Playwright with mocked WebGPU)
    # Since we can't run real WebGPU, we rely on the fact that the app loads the generated JSON
    # and populates the dropdown.
    # But first we need the app to generate the shader list.
    # The 'npm start' command usually does this via 'scripts/generate_shader_lists.js'.

    print("Static verification passed.")

if __name__ == "__main__":
    verify_shader_presence()
