import os
import re

files = [
    "elastic-surface.wgsl",
    "infinite-fractal-feedback.wgsl",
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
        
    # Check if already upgraded
    if "plasmaBuffer[0].z" in content and "clickFront" in content:
        print(f"Already upgraded {filename}")
        continue
        
    print(f"Upgrading {filename}...")
    
    # 1. Inject plasma variables right after time
    if "let time = u.config.x;" in content:
        content = content.replace("let time = u.config.x;", "let time = u.config.x;\n    let bass = plasmaBuffer[0].x;\n    let mids = plasmaBuffer[0].y;\n    let treble = plasmaBuffer[0].z;")
    elif "let time = u.config.x" in content:
        # fuzzy match
        content = re.sub(r'(let\s+time\s*=\s*u\.config\.x;)', r'\1\n    let bass = plasmaBuffer[0].x;\n    let mids = plasmaBuffer[0].y;\n    let treble = plasmaBuffer[0].z;', content)
    
    # 2. Inject audio and click ripples right before the final textureStore(writeTexture
    # Need to be careful. Let's find the last occurrence of textureStore(writeTexture
    
    # If the file is elastic-surface.wgsl:
    if filename == "elastic-surface.wgsl":
        target = "let finalColor = vec4<f32>(color.rgb * lighting, color.a + stretch * 0.3);"
        replacement = """
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(u.config.z/u.config.w, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0)) * stretch;
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let finalColor = vec4<f32>(color.rgb * lighting + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25), color.a + stretch * 0.3);"""
        content = content.replace(target, replacement)
        
    elif filename == "infinite-fractal-feedback.wgsl":
        # It already has some click logic `if (timeSinceClick > 0.0 ...)`
        # Let's replace its click logic with the standard one
        target = """    // Mouse click creates shockwave distortion
    let timeSinceClick = time - u.zoom_config.x;
    if (timeSinceClick > 0.0 && timeSinceClick < 2.0) {
        let clickDist = length(uv - (mousePos - vec2<f32>(0.5, 0.5)) * 2.0);
        let shockwave = sin(clickDist * 20.0 - timeSinceClick * 10.0) * (1.0 - timeSinceClick * 0.5);
        finalColor = finalColor * (1.0 + shockwave * 0.5);
    }"""
        replacement = """    // Ripple click interaction
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(resolution.x/resolution.y, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));
    finalColor = finalColor + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25);"""
        content = content.replace(target, replacement)
        
    with open(filepath, "w") as f:
        f.write(content)

print("Done part 1")
