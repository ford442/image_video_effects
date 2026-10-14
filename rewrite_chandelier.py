import re

with open('public/shaders/gen-vitreous-chrono-chandelier.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Vitreous Chrono-Chandelier
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive,
//            upgraded-rgba, aces-tone-map, temporal-feedback, chromatic-aberration
//  Complexity: High
//  Chunks From: gen-protocell-division.wgsl (upgraded-rgba stack)
//  Upgraded: 2026-10-10
//  Ideas: pendular phase-locked chime clusters; floor-bound caustic web lattice; chronometric tick-marks; crystal cleavage planes
//  A packing: ACES display RGBA
//  By: Claude Code Batch 3B
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

tick_orig = """    let d1 = min(crystal, mount);
    let d2 = min(d1, linkBox);
    return d2 - audioBass * 0.02;"""
tick_new = """    // Idea 2: crystal cleavage planes
    let cleavage = dot(crystalPos, normalize(vec3<f32>(1.0, 1.0, 1.0))) - 0.2;
    let facetedCrystal = max(crystal, cleavage);
    
    // Idea 1: chronometric tick-marks floating around chimes
    let tickRot = p.x * 2.0 + p.y * 5.0 + time;
    let tickMarks = max(length(vec2<f32>(p.x, p.z)) - 0.6, abs(fract(tickRot) - 0.5) - 0.05);

    let d1 = min(facetedCrystal, mount);
    let d2 = min(d1, linkBox);
    return min(d2 - audioBass * 0.02, max(tickMarks, abs(p.y) - 0.02));"""
code = code.replace(tick_orig, tick_new)

with open('public/shaders/gen-vitreous-chrono-chandelier.wgsl', 'w') as f:
    f.write(code)

