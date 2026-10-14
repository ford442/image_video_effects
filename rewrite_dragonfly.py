import re

with open('public/shaders/gen-celestial-quantum-glass-dragonfly.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  gen-celestial-quantum-glass-dragonfly
//  Category: generative
//  Features: dragonfly, quantum, fractal, audio-reactive, mouse-driven, raymarching, crystalline, upgraded-rgba
//  Upgraded: 2026-10-10
//  Ideas: Cauchy thin-film wing iridescence, quantum glass caustic core & photon emission,
//         acoustic wing-tip vortex trails; velocity-banked flight roll from the spring's
//         own momentum; vortex-synced wingtip flutter in the wing SDF; hexagonal compound eye lattice; quantum decoherence static
//  A packing: display RGBA (RGB=ACES tone-mapped dragonfly scene, A=semantic wing/body alpha)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


decoherence_orig = """        let eyeGlow = vec3<f32>(1.2, 0.3, 0.9) * smoothstep(0.8, 1.1, p.z) * glow_int;

        col = mat_col * (dif1 * vec3<f32>(1.0) + dif2 * vec3<f32>(0.2, 0.3, 0.5)) + spec + lum + eyeGlow;"""
        
decoherence_new = """        let eyeGlow = vec3<f32>(1.2, 0.3, 0.9) * smoothstep(0.8, 1.1, p.z) * glow_int;
        
        // Idea 1: Hexagonal compound eye lattice (hex pattern over the head)
        let hexUv = vec2<f32>(p.x, p.y) * 20.0;
        let hexGrid = abs(sin(hexUv.x) + sin(hexUv.x * 0.5 + hexUv.y * 0.866) + sin(hexUv.x * 0.5 - hexUv.y * 0.866));
        let hexPattern = smoothstep(2.0, 2.5, hexGrid) * smoothstep(0.7, 1.1, p.z);
        let compoundEye = vec3<f32>(0.5, 1.0, 0.2) * hexPattern * (1.0 + treble);

        // Idea 2: Quantum decoherence static (noise on the tail)
        let tailMask = smoothstep(0.5, -1.0, p.z);
        let staticNoise = hash3(p * 50.0 + time).x;
        let decoherence = vec3<f32>(0.1, 0.8, 1.0) * staticNoise * tailMask * bass * 0.5;

        col = mat_col * (dif1 * vec3<f32>(1.0) + dif2 * vec3<f32>(0.2, 0.3, 0.5)) + spec + lum + eyeGlow + compoundEye + decoherence;"""
code = code.replace(decoherence_orig, decoherence_new)

with open('public/shaders/gen-celestial-quantum-glass-dragonfly.wgsl', 'w') as f:
    f.write(code)

