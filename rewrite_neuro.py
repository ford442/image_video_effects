import re

with open('public/shaders/gen-sentient-holographic-neuro-lace-matrix.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Sentient Holographic Neuro-Lace Matrix
//  Category: generative
//  Features: raymarching, audio-reactive, mouse-driven, held-drag, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: breathing lace wave (bass-driven thickness swell travelling down the flight axis); bioluminescent depth fog (step-count-lit haze); held-mouse neuron bloom (camera-borne pull node with glow); re-entrant synaptic vortex loops; myelin-like conduction bead trains; cybernetic grid scanning line; data corruption block glitches
//  A packing: ACES display RGBA (alpha = fogged lace coverage raised by node glow); C is not read
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

glitch_orig = """    let mUv = vec2<f32>((u.zoom_config.y - 0.5) * res.x / res.y, 0.5 - u.zoom_config.z);
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let pullC = ro + normalize(vec3<f32>(mUv, 1.0)) * PULL_DEPTH;"""
glitch_new = """    // Idea 2: data corruption block glitches (shift UV periodically)
    let glitch = step(0.98, fract(u.config.x * 5.0 + uv.y * 10.0)) * 0.1 * step(0.9, fract(u.config.x * 12.0));
    let mUv = vec2<f32>((u.zoom_config.y - 0.5) * res.x / res.y, 0.5 - u.zoom_config.z) + vec2<f32>(glitch, 0.0);
    
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let pullC = ro + normalize(vec3<f32>(mUv, 1.0)) * PULL_DEPTH;"""
code = code.replace(glitch_orig, glitch_new)

scan_orig = """    // Post-processing (holographic scanlines)
    col *= 0.9 + 0.1 * sin(uv.y * 100.0 + u.config.x * 5.0);"""
scan_new = """    // Post-processing (holographic scanlines)
    col *= 0.9 + 0.1 * sin(uv.y * 100.0 + u.config.x * 5.0);
    
    // Idea 1: cybernetic grid scanning line
    let scanline = smoothstep(0.95, 1.0, fract(uv.y * 2.0 - u.config.x * 1.5)) * 0.5;
    col += vec3<f32>(0.2, 0.8, 1.0) * scanline * (1.0 + bass);"""
code = code.replace(scan_orig, scan_new)

with open('public/shaders/gen-sentient-holographic-neuro-lace-matrix.wgsl', 'w') as f:
    f.write(code)

