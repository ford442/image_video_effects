import re

with open('public/shaders/gen-celestial-glass-tornado.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  gen-celestial-glass-tornado
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, spring-dynamics, depth-aware
//  Upgraded: 2026-10-10
//  Ideas: Cauchy prismatic facet TIR glints, helical plasma funnel discharge arcs, centrifugal glass dust accretion disk; meteor streak impacts; plasma confinement rings
//  A packing: display RGBA (RGB=ACES tone-mapped glass tornado, A=glow opacity)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


meteor_orig = """    // IDEA 3: Centrifugal glass dust accretion disk"""
meteor_new = """    // IDEA 1: Meteor streak impacts (falling radially)
    let meteorDist = length(nuv);
    let meteorAngle = atan2(nuv.y, nuv.x);
    let meteorTrail = smoothstep(0.95, 1.0, fract(meteorAngle * 4.0 - time * 5.0 + meteorDist * 2.0));
    let meteorFlash = meteorTrail * exp(-abs(meteorDist - fract(time * 3.0)) * 20.0);
    col += vec3<f32>(1.0, 0.8, 0.5) * meteorFlash * (1.0 + treble * 2.0);

    // IDEA 2: Plasma confinement rings (horizontal glowing rings wrapping the tornado)
    let confinement = smoothstep(0.05, 0.0, abs(fract(nuv.y * 10.0 + time) - 0.5));
    let ringMask = exp(-abs(length(nuv.x) - (0.2 - nuv.y * 0.1)) * 30.0);
    col += vec3<f32>(0.2, 1.0, 0.8) * confinement * ringMask * (0.5 + bass);

    // IDEA 3: Centrifugal glass dust accretion disk"""
code = code.replace(meteor_orig, meteor_new)

with open('public/shaders/gen-celestial-glass-tornado.wgsl', 'w') as f:
    f.write(code)


