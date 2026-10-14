import re

with open('public/shaders/gen-chrono-kitsune-prism-weaver.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Chrono-Kitsune Prism Weaver
//  Category: generative
//  Features: raymarch, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: body-as-prism tail spectrum; heartbeat transfer; tail unfurl; kitsune spirit fireballs; prismatic temporal shockwaves
//  A packing: HDR linear RGB (pre-ACES) + semantic alpha; C read exactly as HDR radial echo
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


orbs_orig = """    let is_body = d_body < d_tails;
    return vec4<f32>(smin(d_body, d_tails, BODY_SMIN), select(2.0, 1.0, is_body), best_band, best_pulse);"""
orbs_new = """    // Idea 1: Kitsune spirit fireballs (floating orbs revolving around the body)
    var orbP = p - BODY_POS;
    let orbRot = rot2(time * 2.0);
    orbP = vec3<f32>(orbRot.x * orbP.x - orbRot.y * orbP.z, orbP.y, orbRot.y * orbP.x + orbRot.x * orbP.z);
    let d_orbs = length(orbP - vec3<f32>(3.0, 0.0, 0.0)) - 0.5;

    let d_all = smin(smin(d_body, d_tails, BODY_SMIN), d_orbs, 0.2);
    let is_body = d_body < d_tails && d_body < d_orbs;
    return vec4<f32>(d_all, select(2.0, 1.0, is_body), best_band, best_pulse);"""
code = code.replace(orbs_orig, orbs_new)


shockwaves_orig = """    // Volumetric glow and space dust — treble/FFT shimmer
    let hue_glow = p_prism_hue - time * 0.2;
    let glow_col = vec3<f32>(0.5 + 0.5 * sin(hue_glow * TAU + vec3<f32>(0.0, 2.0, 4.0)));
    let glow_mix = glow_col * glow * 0.25 + glow_rgb * 0.75; // Idea 1: spectral fan halo
    col += glow_mix * (1.5 + treble * 0.8 + fft * 0.4);"""
    
shockwaves_new = """    // Volumetric glow and space dust — treble/FFT shimmer
    let hue_glow = p_prism_hue - time * 0.2;
    let glow_col = vec3<f32>(0.5 + 0.5 * sin(hue_glow * TAU + vec3<f32>(0.0, 2.0, 4.0)));
    let glow_mix = glow_col * glow * 0.25 + glow_rgb * 0.75; // Idea 1: spectral fan halo
    col += glow_mix * (1.5 + treble * 0.8 + fft * 0.4);
    
    // Idea 2: Prismatic temporal shockwaves (expanding rings from the tail roots)
    let shockDist = length(p.xy - vec2<f32>(BODY_POS.x, BODY_POS.y));
    let shockRing = exp(-abs(shockDist - fract(time * 0.5) * 20.0) * 5.0) * (0.5 + bass);
    col += spectralBand(fract(shockDist * 0.1 - time)) * shockRing * 0.5;"""
code = code.replace(shockwaves_orig, shockwaves_new)

with open('public/shaders/gen-chrono-kitsune-prism-weaver.wgsl', 'w') as f:
    f.write(code)

