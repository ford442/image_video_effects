import re

# 3. gen-ethereal-quantum-glass-nautilus
with open('public/shaders/gen-ethereal-quantum-glass-nautilus.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Ethereal Quantum-Glass Nautilus
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: chamber septa walls between adjacent spiral chambers; pearl nacre luster on inner chamber ridges; siphuncle canal; aperture lip on the outer chamber; bioluminescent siphon jet; abyssal pressure fractures
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

fractures_orig = """        let onLip = smoothstep(0.62, 0.9, chamberP) * smoothstep(0.22, 0.0, abs(rP - rOuter) / max(rOuter, 0.001));
        col += vec3<f32>(0.75, 0.9, 1.0) * edge * onLip * refrIndex * 0.18;"""
fractures_new = """        let onLip = smoothstep(0.62, 0.9, chamberP) * smoothstep(0.22, 0.0, abs(rP - rOuter) / max(rOuter, 0.001));
        col += vec3<f32>(0.75, 0.9, 1.0) * edge * onLip * refrIndex * 0.18;
        
        // Idea 1: Bioluminescent siphon jet (glowing particles emitting from the nautilus opening)
        let siphonDist = length(p - vec3<f32>(1.5, 0.0, 0.0));
        let siphonNoise = voronoi(p * 50.0 - vec3<f32>(time * 5.0, 0.0, 0.0));
        let siphonJet = smoothstep(0.5, 0.0, siphonDist) * siphonNoise;
        col += vec3<f32>(0.2, 0.9, 1.0) * siphonJet * (1.0 + treble * 2.0);

        // Idea 2: Abyssal pressure fractures (crack lines on the outer shell)
        let fracNoise = voronoi(p * 10.0);
        let fracture = smoothstep(0.03, 0.0, abs(fracNoise - 0.5));
        col += vec3<f32>(1.0, 0.2, 0.6) * fracture * (0.2 + bass * 0.8) * NdotV;"""
code = code.replace(fractures_orig, fractures_new)

with open('public/shaders/gen-ethereal-quantum-glass-nautilus.wgsl', 'w') as f:
    f.write(code)


# 8. gen-ethereal-aurora-ghost-orchid
with open('public/shaders/gen-ethereal-aurora-ghost-orchid.wgsl', 'r') as f:
    code = f.read()

header2 = """// ═══════════════════════════════════════════════════════════════════
//  Ethereal-Aurora Ghost-Orchid
//  Category: generative
//  Features: mouse-driven, audio-reactive, click-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: spring-eased magnetic pole so the orchid's
//         field-line spiral lags and overshoots the cursor; persistent bass
//         bloom envelope unfurls petals and lifts the red
//         630 nm oxygen band ceiling; raymarch hit distance written as depth; pollinator nectar guides; spectral root tendrils
//  A packing: ACES display RGB blended with exact C read; alpha = aurora
//             emission/shock/held coverage (semantic, never 1.0)
//  Enrichment: aurora altitude physics (557.7 / 630.0 / 427.8 nm bands)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header2, code, flags=re.DOTALL)

roots_orig = """            // Solar wind intensity = bass-driven particle density
            let solarWindInt = 1.0 + bass * 3.0;
            emission += aurora_col * 0.05 * aurora_int * solarWindInt / (1.0 + abs(d) * 10.0);"""
roots_new = """            // Solar wind intensity = bass-driven particle density
            let solarWindInt = 1.0 + bass * 3.0;
            emission += aurora_col * 0.05 * aurora_int * solarWindInt / (1.0 + abs(d) * 10.0);
            
            // Idea 1: Pollinator nectar guides (UV-reactive stripes converging on the center)
            let guideAngle = atan2(p.z, p.x);
            let guideRadius = length(p.xz);
            let nectarGuides = abs(sin(guideAngle * 10.0)) * smoothstep(0.8, 0.2, guideRadius) * smoothstep(-0.2, 0.2, p.y);
            emission += vec3<f32>(0.8, 0.2, 1.0) * nectarGuides * 0.2 * (0.5 + treble);

            // Idea 2: Spectral root tendrils (thin glowing lines extending downward)
            let rootNoise = snoise(p * 5.0 + vec3<f32>(0.0, time * 2.0, 0.0));
            let rootTendrils = smoothstep(0.02, 0.0, abs(p.x + rootNoise * 0.1)) * smoothstep(0.0, -1.5, p.y);
            emission += vec3<f32>(0.2, 0.8, 1.0) * rootTendrils * 0.1 * (0.5 + bass);"""
code = code.replace(roots_orig, roots_new)

with open('public/shaders/gen-ethereal-aurora-ghost-orchid.wgsl', 'w') as f:
    f.write(code)

