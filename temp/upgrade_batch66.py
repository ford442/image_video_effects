import os
import re

files = [
    "aurora-curtain.wgsl",
    "bioluminescent-blackbody.wgsl",
    "cosmic-web.wgsl",
    "crystal-illuminator.wgsl",
    "deep-sea-thermal-vent.wgsl",
    "holographic-prism.wgsl",
    "hyper-tensor-fluid.wgsl",
    "neural-dreamscape.wgsl",
    "plasma-orb.wgsl",
    "quantum-superposition.wgsl"
]

for filename in files:
    filepath = f"public/shaders/{filename}"
    if not os.path.exists(filepath):
        print(f"Skipping {filename} - file not found")
        continue

    with open(filepath, "r") as f:
        content = f.read()

    if "clickFront +=" in content or "clickFront+=" in content:
        print(f"Skipping {filename} - already has click ripples")
        continue

    print(f"Processing {filename}...")

    # Inject missing variables safely
    has_bass = "let bass" in content
    has_mids = "let mids" in content
    has_treble = "let treble" in content
    has_time = bool(re.search(r'let\s+time\s*=', content))
    
    injections = []
    if not has_time: injections.append("let time = u.config.x;")
    if not has_bass: injections.append("let bass = plasmaBuffer[0].x;")
    if not has_mids: injections.append("let mids = plasmaBuffer[0].y;")
    if not has_treble: injections.append("let treble = plasmaBuffer[0].z;")
    
    if injections:
        inj_str = "\n    " + "\n    ".join(injections) + "\n"
        
        # Determine injection point
        if re.search(r'(let\s+time\s*=\s*u\.config\.x;)', content):
            content = re.sub(r'(let\s+time\s*=\s*u\.config\.x;)', f'\\1{inj_str}', content, count=1)
        elif re.search(r'(let\s+t\s*=\s*u\.config\.x;)', content):
            content = re.sub(r'(let\s+t\s*=\s*u\.config\.x;)', f'\\1{inj_str}', content, count=1)
        else:
            # Inject at the top of main function
            content = re.sub(r'(fn\s+main.*?\{)', f'\\1{inj_str}', content, count=1)

    # Find textureStore matches
    matches1 = list(re.finditer(r'textureStore\(\s*writeTexture\s*,\s*(.*?)\s*,\s*vec4(?:<[a-zA-Z0-9]+>)?\((.*?),\s*(.*?)\)\s*\);', content))
    matches2 = list(re.finditer(r'textureStore\(\s*writeTexture\s*,\s*(.*?)\s*,\s*(.*?)\s*\);', content))
    
    target_match = None
    is_match1 = False
    
    if matches1 and (not matches2 or matches1[-1].start() > matches2[-1].start() or (matches1[-1].start() == matches2[-1].start())):
        target_match = matches1[-1]
        is_match1 = True
    elif matches2:
        target_match = matches2[-1]
        
    if target_match:
        coord = target_match.group(1)
        
        ripple_logic = f"""
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    let aspect = u.config.z / max(u.config.w, 1.0);
    let screenUV = vec2<f32>({coord}) / vec2<f32>(u.config.z, u.config.w);
    for (var i = 0u; i < rippleCount; i = i + 1u) {{
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((screenUV - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 58.0);
    }}
    
    let clockRings = sin(length(screenUV - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));
"""
        if is_match1:
            color_var = target_match.group(2)
            alpha_var = target_match.group(3)
            replacement = ripple_logic + f"""
    let __finalRGB = {color_var} + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, {coord}, vec4<f32>(__finalRGB, {alpha_var}));"""
            
            content = content[:target_match.start()] + replacement + content[target_match.end():]
            
            content = re.sub(rf'textureStore\(dataTextureA,\s*(.*?),\s*vec4(?:<[a-zA-Z0-9]+>)?\({re.escape(color_var)},\s*{re.escape(alpha_var)}\)\s*\);', rf'textureStore(dataTextureA, \1, vec4<f32>(__finalRGB, {alpha_var}));', content)
            
        else:
            vec4_var = target_match.group(2)
                
            replacement = ripple_logic + f"""
    let __finalRGB = {vec4_var}.rgb + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);
    textureStore(writeTexture, {coord}, vec4<f32>(__finalRGB, {vec4_var}.a));"""
            
            content = content[:target_match.start()] + replacement + content[target_match.end():]
            content = re.sub(rf'textureStore\(dataTextureA,\s*(.*?),\s*{re.escape(vec4_var)}\s*\);', rf'textureStore(dataTextureA, \1, vec4<f32>(__finalRGB, {vec4_var}.a));', content)

    with open(filepath, "w") as f:
        f.write(content)

print("Batch 66 done.")
