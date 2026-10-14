import re

with open('public/shaders/gen-hyper-geometric-void-glass-seraph.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Hyper-Geometric Void-Glass Seraph
//  Category: generative
//  Features: upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: inner void core rotation; chromatic dispersion tied to KIFS iterations
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
"""
code = re.sub(r'// --.*?\n// Hyper-Geometric Void-Glass Seraph.*?\n// --.*?\n#include "_prelude\.wgsl"', header, code, flags=re.DOTALL)

map_orig = """    // Space inversion (rough approximation of bending) near the singularity
    let distToCenter = length(p);
    let warpFactor = 1.0 + (u.zoom_params.z * 0.5) / (distToCenter + 0.1);

    // KIFS Fractal folding
    var pFold = p * warpFactor;"""

map_new = """    // Space inversion (rough approximation of bending) near the singularity
    let distToCenter = length(p);
    let warpFactor = 1.0 + (u.zoom_params.z * 0.5) / (distToCenter + 0.1);

    // Idea 1: Inner void core rotation - twist space based on proximity to the singularity
    let twist = smoothstep(1.5, 0.0, dSing) * time * 2.5;
    let pRot = rot3D(p, vec2<f32>(-twist, twist * 0.5));

    // KIFS Fractal folding
    var pFold = pRot * warpFactor;"""
code = code.replace(map_orig, map_new)

render_orig = """        // Chromatic aberration splits the color slightly based on normal and refrVector
        let ca = u.zoom_params.w * 0.1;

        let colR = 0.5 + 0.5 * cos(6.28 * (dot(refrVector + vec3<f32>(ca, 0.0, 0.0), vec3<f32>(1.0)) * 0.5 + 0.0));
        let colG = 0.5 + 0.5 * cos(6.28 * (dot(refrVector, vec3<f32>(1.0)) * 0.5 + 0.33));
        let colB = 0.5 + 0.5 * cos(6.28 * (dot(refrVector - vec3<f32>(ca, 0.0, 0.0), vec3<f32>(1.0)) * 0.5 + 0.67));

        let glassBase = vec3<f32>(colR, colG, colB);"""

render_new = """        // Idea 2: chromatic dispersion tied to KIFS iterations (fractal depth)
        let kifsDepth = res.y;
        let ca = u.zoom_params.w * 0.1 * (1.0 + kifsDepth * 0.8);

        let colR = 0.5 + 0.5 * cos(6.28 * (dot(refrVector + vec3<f32>(ca, 0.0, 0.0), vec3<f32>(1.0)) * 0.5 + 0.0));
        let colG = 0.5 + 0.5 * cos(6.28 * (dot(refrVector, vec3<f32>(1.0)) * 0.5 + 0.33));
        let colB = 0.5 + 0.5 * cos(6.28 * (dot(refrVector - vec3<f32>(ca, 0.0, 0.0), vec3<f32>(1.0)) * 0.5 + 0.67));

        let rawGlass = vec3<f32>(colR, colG, colB);
        let deepViolet = vec3<f32>(0.4, 0.0, 0.8);
        let glassBase = mix(rawGlass, deepViolet, smoothstep(3.0, 6.0, kifsDepth));"""
code = code.replace(render_orig, render_new)

main_orig = """    // Gamma correction
    let finalCol = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, id.xy, vec4<f32>(finalCol, 1.0));"""

main_new = """    let finalCol = acesToneMap(col);
    let alpha = clamp(length(col), 0.05, 0.98);

    textureStore(dataTextureA, id.xy, vec4<f32>(finalCol, alpha));
    textureStore(writeTexture, id.xy, vec4<f32>(finalCol, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(clamp(1.0 - col.g, 0.0, 1.0), 0.0, 0.0, 0.0));"""
code = code.replace(main_orig, main_new)

with open('public/shaders/gen-hyper-geometric-void-glass-seraph.wgsl', 'w') as f:
    f.write(code)

