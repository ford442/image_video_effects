import glob
import re

for filepath in glob.glob("batch58a/*.wgsl"):
    with open(filepath, 'r') as f:
        content = f.read()

    for i in range(13):
        if f"@binding({i})" not in content:
            print(f"{filepath} missing @binding({i})")

