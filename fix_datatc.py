import glob
import re

for filepath in glob.glob("batch58a/*.wgsl"):
    with open(filepath, 'r') as f:
        content = f.read()

    # exact textureLoad from dataTextureC
    content = re.sub(
        r'textureSampleLevel\(\s*dataTextureC\s*,\s*[^,]+\s*,\s*(.*?),\s*0\.0\s*\)',
        r'textureLoad(dataTextureC, vec2<i32>((\1) * vec2<f32>(textureDimensions(dataTextureC))), 0)',
        content
    )
    
    with open(filepath, 'w') as f:
        f.write(content)
