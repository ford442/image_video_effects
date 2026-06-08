with open("public/shaders/gen-resonant-quantum-obsidian-scarab-engine.wgsl", "r") as f:
    content = f.read()

# Fix the dust density mapping to use zoom_config.w as intended by the JSON definition
content = content.replace("let dustDensity = u.config.w * 0.1; // mapping quantum dust density to zoom_config.w wasn't working, mapping to u.config.w for now based on what I can see",
                          "let dustDensity = u.zoom_config.w * 0.1;")

# Add Audio Reactivity
# We can add an audio modifier to the corePulseRate
content = content.replace("let corePulseRate = u.zoom_params.w;",
                          "let audioLevel = u.config.y;\n    let corePulseRate = u.zoom_params.w + audioLevel * 2.0;")

# Make the exoskeleton KIFS fold audio reactive as well
content = content.replace("let r = rot(u.config.x * 0.5 + f32(i));",
                          "let r = rot(u.config.x * 0.5 + f32(i) + u.config.y * 0.5);")

with open("public/shaders/gen-resonant-quantum-obsidian-scarab-engine.wgsl", "w") as f:
    f.write(content)
