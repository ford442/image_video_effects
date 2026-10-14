import re

with open('public/shaders/gen-radiant-chrono-glass-nautilus.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Radiant Chrono-Glass Nautilus
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: logarithmic chamber septa; birefringent growth lamellae; siphuncle plasma conduit; chamber-sequential plasma tide; septal suture scallops; nacre growth striae; clockwork escapement ticking; chrono-glass shatter
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

tick_orig = """    let tightness = u.zoom_params.x; // 0.1 to 1.0
    let spiral_a = a * tightness + log(r) * 2.0 + t * 0.5;"""
tick_new = """    let tightness = u.zoom_params.x; // 0.1 to 1.0
    // Idea 1: clockwork escapement ticking
    let ticking = floor(t * 4.0) * 0.25 + smoothstep(0.8, 1.0, fract(t * 4.0)) * 0.25;
    let spiral_a = a * tightness + log(r) * 2.0 + ticking * 0.5;"""
code = code.replace(tick_orig, tick_new)

shatter_orig = """        let lobeA = 0.5 + 0.5 * sin(spiralPhase * 6.0 + nDotV * opticalSep);
        let lobeB = 0.5 + 0.5 * sin(spiralPhase * 6.0 - nDotV * opticalSep + 1.2);
        col += vec3<f32>(lobeA, 0.18 * (lobeA + lobeB), lobeB) * f * 0.22;
        col += vec3<f32>(0.95, 0.92, 0.82) * striae * f * 0.12;
        // Mid-frequency chromatic shimmer across the glass
        col += vec3<f32>(0.2, 0.05, 0.3) * f * mids;
    }"""
shatter_new = """        let lobeA = 0.5 + 0.5 * sin(spiralPhase * 6.0 + nDotV * opticalSep);
        let lobeB = 0.5 + 0.5 * sin(spiralPhase * 6.0 - nDotV * opticalSep + 1.2);
        col += vec3<f32>(lobeA, 0.18 * (lobeA + lobeB), lobeB) * f * 0.22;
        col += vec3<f32>(0.95, 0.92, 0.82) * striae * f * 0.12;
        // Mid-frequency chromatic shimmer across the glass
        col += vec3<f32>(0.2, 0.05, 0.3) * f * mids;
        
        // Idea 2: chrono-glass shatter (fracture highlights)
        let shatter = fract(sin(dot(floor(p * 15.0), vec3<f32>(12.9898, 78.233, 37.719))) * 43758.5453);
        let shardEdge = smoothstep(0.48, 0.5, abs(fract(p.x * 10.0 + shatter) - 0.5));
        col += vec3<f32>(0.8, 0.9, 1.0) * shardEdge * f * 0.5;
    }"""
code = code.replace(shatter_orig, shatter_new)

with open('public/shaders/gen-radiant-chrono-glass-nautilus.wgsl', 'w') as f:
    f.write(code)

