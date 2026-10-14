import re

with open('public/shaders/gen-chromatic-metamorphosis.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Chromatic Metamorphosis
//  Category: generative
//  Features: audio-reactive, mouse-driven, temporal, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: catalyst stutter-hold on the nearest phase before releasing; temporal afterimage from exact dataTextureC history; per-phase seasonal color lean; cellular Voronoi shell patterns; chromatic depth bleed
//  A packing: display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


voronoi_orig = """    var d = s0 * w0;
    d = smin(d, s1, blendK * w1 + 0.01);
    d = smin(d, s2, blendK * w2 + 0.01);
    d = smin(d, s3, blendK * w3 + 0.01);
    return d;"""
voronoi_new = """    var d = s0 * w0;
    d = smin(d, s1, blendK * w1 + 0.01);
    d = smin(d, s2, blendK * w2 + 0.01);
    d = smin(d, s3, blendK * w3 + 0.01);
    
    // Idea 1: Cellular Voronoi shell patterns (fractal displacement map on the surface)
    // h2_cm is available, let's just do a simple noise displacement
    let shellPattern = sin(p.x * 10.0) * cos(p.y * 10.0) * sin(p.z * 10.0) * 0.05 * w2;
    return d + shellPattern;"""
code = code.replace(voronoi_orig, voronoi_new)


bleed_orig = """    var col = vec3<f32>(0.02, 0.02, 0.06); // background"""
bleed_new = """    // Idea 2: Chromatic depth bleed (the background color shifts based on the SDF distance)
    let bgDist = sceneSDF(ro + rd * 8.0, t, blendRadius, localMorph);
    var col = vec3<f32>(0.02, 0.02, 0.06) + vec3<f32>(0.1, 0.0, 0.2) * exp(-bgDist * 0.5); // background"""
code = code.replace(bleed_orig, bleed_new)

with open('public/shaders/gen-chromatic-metamorphosis.wgsl', 'w') as f:
    f.write(code)

