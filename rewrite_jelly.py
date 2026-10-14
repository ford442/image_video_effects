import re

with open('public/shaders/gen-chromatic-oracle-jelly.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Chromatic Oracle Jelly — drifting bells, watching eyes, and luminous tentacles
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: pulse-swim contraction with thrust/coast surge; pupils track the pointer and
//         blink on seeded schedules; tentacle-anchored luminous wake from a second
//         history sample; click-triggered startle contraction spike; audio-linked pupil dilation; oracle synapse sparks; bioluminescent bell-edge frills
//  A packing: ACES display RGBA (read back as colour history)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


frills_orig = """    let rim = exp(-abs(bellDistance - 0.34) * (35.0 + swarmDensity * 25.0)) * smoothstep(0.30, -0.12, local.y);"""
frills_new = """    // Idea 2: Bioluminescent bell-edge frills
    let frillWave = abs(sin(atan2(local.y, local.x) * 20.0 + time * 5.0)) * 0.02;
    let rim = exp(-abs(bellDistance - 0.34 - frillWave) * (35.0 + swarmDensity * 25.0)) * smoothstep(0.30, -0.12, local.y);"""
code = code.replace(frills_orig, frills_new)


sparks_orig = """    let tentacles = pow(0.5 + 0.5 * cos(tentaclePhase), 12.0) * smoothstep(-0.08, 0.48 + contraction * 0.22, local.y) * exp(-abs(local.x) * 2.2);"""
sparks_new = """    let tentacles = pow(0.5 + 0.5 * cos(tentaclePhase), 12.0) * smoothstep(-0.08, 0.48 + contraction * 0.22, local.y) * exp(-abs(local.x) * 2.2);
    
    // Idea 1: Oracle synapse sparks (flashes on the tentacles)
    let sparkHash = hash21(floor(local * 20.0 + time));
    let synapseSparks = tentacles * step(0.99, sparkHash) * (1.0 + treble * 2.0);"""
code = code.replace(sparks_orig, sparks_new)


color_orig = """    hdr += palette(hue + 0.34) * (rim * 1.7 + tentacles * (0.7 + audio.z));"""
color_new = """    hdr += palette(hue + 0.34) * (rim * 1.7 + tentacles * (0.7 + audio.z)) + vec3<f32>(1.0, 0.9, 0.5) * synapseSparks * 3.0;"""
code = code.replace(color_orig, color_new)

with open('public/shaders/gen-chromatic-oracle-jelly.wgsl', 'w') as f:
    f.write(code)

