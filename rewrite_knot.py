import re

with open('public/shaders/gen-torus-knot-rainbow.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Torus Knot Rainbow — Algorithmist Upgrade
//  Category: generative
//  Features: audio-reactive, temporal-feedback, analytic-sdf-tube,
//            smooth-union-capsules, multi-orbit-julia-trap,
//            fbm-domain-warp, psychedelic-halo, depth-output, aces-tone-map
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-10-10
//  Ideas: Kelvin wave packets along the knot; braid-crossing flare bursts; magnetic flux tube core; plasma pinch instabilities
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

pinch_orig = """        // Harmonic tube-radius modulation
        let rad = baseRad * (1.0 + 0.22 * sin(t0 * 5.0 - time * 0.4) + 0.12 * bass);

        // Smooth-min union creates a continuous analytic tube
        dMin = smin(dMin, dseg - rad, smoothK);"""

pinch_new = """        // Harmonic tube-radius modulation
        // Idea 2: plasma pinch instabilities
        let pinch = 0.5 + 0.5 * cos(t0 * 15.0 - time * 2.0);
        let rad = baseRad * (1.0 + 0.22 * sin(t0 * 5.0 - time * 0.4) + 0.12 * bass) * (0.8 + 0.4 * pinch);

        // Smooth-min union creates a continuous analytic tube
        dMin = smin(dMin, dseg - rad, smoothK);"""
code = code.replace(pinch_orig, pinch_new)


core_orig = """    let haloCol = psychedelicPalette(bestT * 3.0 + time * 0.06 + jTrap);
    let field = exp(-max(dMin, 0.0) * (8.0 + treble * 6.0));
    knotCol = mix(knotCol, haloCol, clamp(jTrap * 2.0 + field * 0.3, 0.0, 0.55));"""

core_new = """    let haloCol = psychedelicPalette(bestT * 3.0 + time * 0.06 + jTrap);
    let field = exp(-max(dMin, 0.0) * (8.0 + treble * 6.0));
    knotCol = mix(knotCol, haloCol, clamp(jTrap * 2.0 + field * 0.3, 0.0, 0.55));
    
    // Idea 1: Magnetic flux tube core
    let fluxCore = exp(-abs(bestD) * 40.0) * (0.5 + bass);
    knotCol += vec3<f32>(1.0, 1.0, 1.0) * fluxCore;"""
code = code.replace(core_orig, core_new)


with open('public/shaders/gen-torus-knot-rainbow.wgsl', 'w') as f:
    f.write(code)

