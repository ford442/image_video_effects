import re

with open('public/shaders/gen-celestial-prism-orchid.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  gen-celestial-prism-orchid
//  Category: generative
//  Features: prism-orchid, celestial-floral, audio-light, mouse-pollinator, depth-petals, iridescent-bloom, semantic-alpha
//  Upgraded: 2026-10-10
//  Ideas: Cauchy prismatic petal-edge dispersion, micro-venation bioluminescent nutrient flow, starlight corona diffraction starburst; starlight stamen dust; chromatic petal veining
//  A packing: display RGBA (RGB=ACES tone-mapped orchid bloom, A=semantic petal transmission)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


stamen_orig = """            let core_illum = vec3<f32>(1.0, 0.6, 0.2) * (1.0 / (1.0 + dist_to_core * dist_to_core)) * coreIntensity;
            col += core_illum * (0.5 + bass * 0.4 + shimmer * 0.3);"""
stamen_new = """            let core_illum = vec3<f32>(1.0, 0.6, 0.2) * (1.0 / (1.0 + dist_to_core * dist_to_core)) * coreIntensity;
            col += core_illum * (0.5 + bass * 0.4 + shimmer * 0.3);
            
            // Idea 1: Starlight stamen dust (sparkling particles near core)
            let stamenNoise = hash31(floor(p * 10.0 + time));
            let stamenSparkle = step(0.98, stamenNoise) * exp(-dist_to_core * 5.0);
            col += vec3<f32>(1.0, 0.9, 0.5) * stamenSparkle * (2.0 + treble * 3.0);
            
            // Idea 2: Chromatic petal veining (fractal noise lines along the petals)
            let veinNoise = fbm(p * 5.0 + vec3<f32>(0.0, time * 0.2, 0.0));
            let veinLines = smoothstep(0.48, 0.5, veinNoise) * smoothstep(0.52, 0.5, veinNoise);
            col += vec3<f32>(0.3, 0.8, 1.2) * veinLines * (0.5 + mids);"""
code = code.replace(stamen_orig, stamen_new)

with open('public/shaders/gen-celestial-prism-orchid.wgsl', 'w') as f:
    f.write(code)

