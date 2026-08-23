import os
import re

files = [
    "recursion-mirror-vortex.wgsl",
    "temporal-feedback-zoom-tracer.wgsl"
]

for filename in files:
    filepath = f"public/shaders/{filename}"
    with open(filepath, "r") as f:
        content = f.read()

    # 1. Audio vars
    if "let time = u.config.x;" in content:
        content = re.sub(r'(let\s+time\s*=\s*u\.config\.x;)', r'\1\n    let bass = plasmaBuffer[0].x;\n    let mids = plasmaBuffer[0].y;\n    let treble = plasmaBuffer[0].z;', content, count=1)
        
    # 2. Store replacement
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
        content = re.sub(rf'textureStore\(dataTextureA,\s*(.*?),\s*vec4<f32>\({re.escape(color_var)},\s*{re.escape(alpha_var)}\)\s*\);', rf'textureStore(dataTextureA, \1, vec4<f32>(__finalRGB, {alpha_var}));', content)

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
            content = re.sub(rf'textureStore\(dataTextureA,\s*(.*?),\s*{re.escape(vec4_var)}\s*\);', rf'textureStore(dataTextureA, \1, vec4<f32>(__finalRGB, {vec4_var}.a));', content)

    with open(filepath, "w") as f:
        f.write(content)
