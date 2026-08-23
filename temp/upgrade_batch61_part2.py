import os
import re

files = [
    "liquid-chrome-ripple.wgsl",
    "quantum-foam-lattice.wgsl",
    "recursion-mirror-vortex.wgsl",
    "spectral-flow-sorting.wgsl",
    "temporal-feedback-zoom-tracer.wgsl",
    "tensor-flow-sculpt.wgsl",
    "volumetric-depth-zoom.wgsl"
]

for filename in files:
    filepath = f"public/shaders/{filename}"
    if not os.path.exists(filepath):
        print(f"Skipping {filename}, not found.")
        continue
        
    with open(filepath, "r") as f:
        content = f.read()
        
    if "plasmaBuffer[0].z" in content and "clickFront" in content:
        print(f"Already upgraded {filename}")
        continue
        
    print(f"Upgrading {filename}...")
    
    # 1. Inject plasma variables
    if "let time = u.config.x;" in content:
        content = content.replace("let time = u.config.x;", "let time = u.config.x;\n    let bass = plasmaBuffer[0].x;\n    let mids = plasmaBuffer[0].y;\n    let treble = plasmaBuffer[0].z;")
    elif "let zoom_time = u.zoom_config.x;" in content: # volumetric-depth-zoom
        content = content.replace("let zoom_time = u.zoom_config.x;", "let zoom_time = u.zoom_config.x;\n    let time = u.config.x;\n    let bass = plasmaBuffer[0].x;\n    let mids = plasmaBuffer[0].y;\n    let treble = plasmaBuffer[0].z;")
    elif "let time = u.config.x" in content:
        content = re.sub(r'(let\s+time\s*=\s*u\.config\.x;)', r'\1\n    let bass = plasmaBuffer[0].x;\n    let mids = plasmaBuffer[0].y;\n    let treble = plasmaBuffer[0].z;', content)

    # 2. Add audio reactivity randomly to an interesting parameter (optional but good)
    # 3. Add spectral and ripples before textureStore
    
    # Find textureStore
    match = re.search(r'textureStore\(\s*writeTexture\s*,\s*(.*?)\s*,\s*vec4<f32>\((.*?),\s*(.*?)\)\s*\);', content)
    if match:
        coord = match.group(1)
        color_var = match.group(2)
        alpha_var = match.group(3)
        
        replacement = f"""
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {{
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(u.config.z/u.config.w, 1.0)) - age * 0.38) * 58.0);
    }}
    
    let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let __finalRGB = {color_var} + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, {coord}, vec4<f32>(__finalRGB, {alpha_var}));"""
        
        content = content[:match.start()] + replacement + content[match.end():]
        
    else:
        # Check for direct vec4 store
        match2 = re.search(r'textureStore\(\s*writeTexture\s*,\s*(.*?)\s*,\s*(.*?)\s*\);', content)
        if match2:
            coord = match2.group(1)
            vec4_var = match2.group(2)
            
            replacement = f"""
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {{
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(u.config.z/u.config.w, 1.0)) - age * 0.38) * 58.0);
    }}
    
    let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let __finalRGB = {vec4_var}.rgb + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, {coord}, vec4<f32>(__finalRGB, {vec4_var}.a));"""
            
            content = content[:match2.start()] + replacement + content[match2.end():]

    # Handle dataTextureA update so the feedback trails include the spectral color
    # E.g. textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
    # Just blindly replace the color part there if it exists, but it's simpler to just replace all `vec4<f32>({color_var}, {alpha_var})` after the store?
    # Usually dataTextureA is stored right after.
    # We can regex replace the dataTextureA call with __finalRGB.
    if match:
        content = re.sub(rf'textureStore\(dataTextureA,\s*(.*?),\s*vec4<f32>\({re.escape(color_var)},\s*{re.escape(alpha_var)}\)\s*\);', rf'textureStore(dataTextureA, \1, vec4<f32>(__finalRGB, {alpha_var}));', content)
    elif match2:
        content = re.sub(rf'textureStore\(dataTextureA,\s*(.*?),\s*{re.escape(vec4_var)}\s*\);', rf'textureStore(dataTextureA, \1, vec4<f32>(__finalRGB, {vec4_var}.a));', content)

    with open(filepath, "w") as f:
        f.write(content)

print("Done part 2")
