import re

with open('public/shaders/gen-vitreous-quantum-lotus-singularity.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Vitreous Quantum-Lotus Singularity  (visualist upgrade b31)
//  Category: generative
//  Tags: ["organic", "quantum", "cosmic", "fractal", "flower", "refraction", "audio-reactive", "sdf", "thin-film"]
//  Upgrade: canonical uniforms fix, slider mapping fix, thin-film
//           iridescent glass petals, per-petal cell variation, radial
//           vein inlay, 3-point lighting + Fresnel, ACES, real depth.
//  Upgraded: 2026-10-10
//  Ideas: petal torsion chirality bands; photon-sphere shear arcs; quantum fluctuation core; pistil stamen filaments
//  A packing: raw normal/material fields in A
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


fluct_orig = """    // Central Singularity Sphere
    let singularity = length(p) - (singularityMass * 0.5);"""
fluct_new = """    // Central Singularity Sphere
    // Idea 1: quantum fluctuation core
    let quantumFluct = hash31(p * 10.0 + time) * 0.05 * (u.zoom_params.w + 0.1);
    let singularity = length(p) - (singularityMass * 0.5) + quantumFluct;"""
code = code.replace(fluct_orig, fluct_new)


stamens_orig = """    let combined = smin(d, singularity, 0.5);
    let matId = select(1.0, 2.0, singularity < d);
    return vec2<f32>(combined, matId);"""
stamens_new = """    let combined = smin(d, singularity, 0.5);
    
    // Idea 2: pistil stamen filaments
    let stamenAng = atan2(p.y, p.x) * 8.0;
    let stamenRad = length(p.xy);
    let stamen = max(abs(fract(stamenAng) - 0.5) * 0.1, abs(p.z) - 0.5) + abs(stamenRad - 0.4) * 0.5;
    
    let finalDist = min(combined, stamen);
    var matId = 1.0;
    if (singularity < d) { matId = 2.0; }
    if (stamen < combined) { matId = 3.0; }
    
    return vec2<f32>(finalDist, matId);"""
code = code.replace(stamens_orig, stamens_new)


with open('public/shaders/gen-vitreous-quantum-lotus-singularity.wgsl', 'w') as f:
    f.write(code)

