import os
import re

files = [
    "quantum-foam-lattice.wgsl",
    "spectral-flow-sorting.wgsl",
    "temporal-feedback-zoom-tracer.wgsl",
    "tensor-flow-sculpt.wgsl"
]

for filename in files:
    filepath = f"public/shaders/{filename}"
    with open(filepath, "r") as f:
        content = f.read()
        
    # Find let time = u.config.x; and replace ONLY THE FIRST OCCURRENCE
    content = re.sub(r'(let\s+time\s*=\s*u\.config\.x;)', r'\1\n    let bass = plasmaBuffer[0].x;\n    let mids = plasmaBuffer[0].y;\n    let treble = plasmaBuffer[0].z;', content, count=1)
    
    with open(filepath, "w") as f:
        f.write(content)
