import re

with open('public/shaders/gen-quantum-resonance-lattice.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Quantum Resonance Lattice
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: resonant band-splitting halos around octahedral nodes; nodal-plane standing-wave sheets; probability wave interference; Planck-scale lattice dislocation
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

map_orig = """    // Wave disruption
    let t = u.config.x * (u.zoom_params.z * 5.0); // Travel Speed
    let amp = u.zoom_params.y * 3.0; // Wave Amplitude
    let wave = sin(cell.x * 0.5 + t) * cos(cell.z * 0.5 + t) * amp;

    // Audio disruption
    let audioWave = audioReactive * 2.0 * sin(cell.y * 1.5 - t);

    q += vec3<f32>(0.0, wave + audioWave, 0.0);"""

map_new = """    // Wave disruption
    let t = u.config.x * (u.zoom_params.z * 5.0); // Travel Speed
    let amp = u.zoom_params.y * 3.0; // Wave Amplitude
    let wave = sin(cell.x * 0.5 + t) * cos(cell.z * 0.5 + t) * amp;

    // Audio disruption
    let audioWave = audioReactive * 2.0 * sin(cell.y * 1.5 - t);

    q += vec3<f32>(0.0, wave + audioWave, 0.0);
    
    // Idea 2: Planck-scale lattice dislocation
    let dislocation = step(0.9, fract(cell.y * 0.3 + t * 0.2)) * 0.15;
    q += vec3<f32>(dislocation, 0.0, -dislocation);"""
code = code.replace(map_orig, map_new)

color_orig = """            channelCol = (finalL * ambientCol[c] + sss + halo) * ao;

            // Distance fog
            channelCol = mix(channelCol, 0.0, smoothstep(20.0, 60.0, t));"""

color_new = """            // Idea 1: Probability wave interference
            let probInterference = 0.5 + 0.5 * sin(dot(p, vec3<f32>(1.0, 2.0, 3.0)) * 5.0 - u.config.x * 10.0);
            
            channelCol = (finalL * ambientCol[c] + sss + halo) * ao * (0.8 + 0.4 * probInterference);

            // Distance fog
            channelCol = mix(channelCol, 0.0, smoothstep(20.0, 60.0, t));"""
code = code.replace(color_orig, color_new)

with open('public/shaders/gen-quantum-resonance-lattice.wgsl', 'w') as f:
    f.write(code)

