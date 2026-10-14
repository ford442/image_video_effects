import re

with open('public/shaders/gen-kaleidoscopic-synapse-bloom.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Kaleidoscopic Synapse Bloom
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: axon runner fronts; counter-rotating dendrite web; myelin sheath insulation; astrocyte glia network
//  A packing: ACES display RGBA (C read as colour history)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

nodes_orig = """    let refractory = 1.0 - 0.65 * pow(behindFront, 2.0 + audio.x * 2.0) * (1.0 - runner);
    let nodes = (pow(axon, 12.0) * (0.35 + branch * 1.8) + branch * (0.18 + runner * 1.5)) * refractory;"""
nodes_new = """    let refractory = 1.0 - 0.65 * pow(behindFront, 2.0 + audio.x * 2.0) * (1.0 - runner);
    let nodes = (pow(axon, 12.0) * (0.35 + branch * 1.8) + branch * (0.18 + runner * 1.5)) * refractory;
    
    // Idea 1: myelin sheath insulation (beaded structures on axon)
    let myelinPhase = fract(radius * 12.0 - time * pulseSpeed * 0.5);
    let myelin = smoothstep(0.4, 0.6, abs(myelinPhase - 0.5) * 2.0) * branch * exp(-radius * 3.0);"""
code = code.replace(nodes_orig, nodes_new)

ves_orig = """    let vesicles = quantum * release * clamp(dendrites * 1.6 + synapseBridge * 2.0, 0.0, 1.0) * (1.0 + audio.z * 1.5);"""
ves_new = """    let vesicles = quantum * release * clamp(dendrites * 1.6 + synapseBridge * 2.0, 0.0, 1.0) * (1.0 + audio.z * 1.5);
    
    // Idea 2: astrocyte glia network (secondary support background)
    let gliaPhase = angle * (sectors * 0.5) + radius * 5.0 + time * 0.1;
    let astrocyte = pow(0.5 + 0.5 * sin(gliaPhase) * cos(gliaPhase * 2.3), 14.0) * 0.25;"""
code = code.replace(ves_orig, ves_new)

color_orig = """    hdr += palette(hue + 0.18) * vesicles * (1.6 + colorFlux);
    hdr += palette(hue + 0.6) * dragMask * (0.5 + neuralWarp * 1.5);"""
color_new = """    hdr += palette(hue + 0.18) * vesicles * (1.6 + colorFlux);
    hdr += palette(hue + 0.6) * dragMask * (0.5 + neuralWarp * 1.5);
    hdr += vec3<f32>(0.2, 0.8, 0.4) * myelin * 1.5;
    hdr += vec3<f32>(0.1, 0.1, 0.3) * astrocyte * (0.5 + audio.y);"""
code = code.replace(color_orig, color_new)

with open('public/shaders/gen-kaleidoscopic-synapse-bloom.wgsl', 'w') as f:
    f.write(code)

