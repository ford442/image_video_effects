import re

with open('public/shaders/gen-chromodynamic-glass-labyrinth.wgsl', 'r') as f:
    code = f.read()

header = """// ----------------------------------------------------------------
// Chromodynamic Glass Labyrinth
// Category: generative
// Upgraded: 2026-10-10
// Ideas: Labyrinth pulse-waves; Fracture fault-lines
// A packing: display RGBA
// ----------------------------------------------------------------"""
code = re.sub(r'// --.*?// ----------------------------------------------------------------', header, code, count=1, flags=re.DOTALL)


crack_orig = """    // Spatial folding
    let s_density = u.zoom_params.x;
    let cell_size = 4.0 / s_density;"""
crack_new = """    // Spatial folding
    // Idea 2: Fracture fault-lines (hard UV shifts simulating glass cracks)
    let fault = step(0.0, sin(p.x * 2.0 + p.z * 1.5)) * 0.15;
    p.y += fault;

    let s_density = u.zoom_params.x;
    let cell_size = 4.0 / s_density;"""
code = code.replace(crack_orig, crack_new)


pulse_orig = """        let mat_color = palette(length(p) * 0.1 + u.config.x * 0.5);"""
pulse_new = """        // Idea 1: Labyrinth pulse-waves (a spherical wave of color sweeping through)
        let pulseWave = smoothstep(0.1, 0.0, abs(fract(length(p) * 0.5 - u.config.x * 0.8) - 0.5));
        let mat_color = palette(length(p) * 0.1 + u.config.x * 0.5) + vec3<f32>(1.0, 0.5, 0.8) * pulseWave * audio_val;"""
code = code.replace(pulse_orig, pulse_new)


with open('public/shaders/gen-chromodynamic-glass-labyrinth.wgsl', 'w') as f:
    f.write(code)

