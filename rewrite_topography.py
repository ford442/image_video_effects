import re

with open('public/shaders/gen-thermal-rainbow-topography.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Thermal Rainbow Topography
//  Category: generative
//  Features: thermal, topography, rainbow, audio-reactive, mouse-interactive, semantic-alpha, aces-tone-mapping, chromatic-aberration, temporal-feedback, depth-aware, domain-warped-fbm, curl-noise-flow, worley-cells, thermal-diffusion, ripple-reactive
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: watershed drainage channels; saddle-point thermal eddy blooms; magma caldera sinks; tectonic fault-line shears
//  By: Kimi Agent (Bright batch)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


fault_orig = """    let aspect = res.x / res.y;
    let centeredUV = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);
    let terrainScale = 2.0 + scale * 4.0;
    let warpAmt = 0.35 + scale * 0.9;
    let tp = centeredUV * terrainScale * (1.0 + audio.x * 0.15);"""

fault_new = """    let aspect = res.x / res.y;
    let centeredUV = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);
    let terrainScale = 2.0 + scale * 4.0;
    let warpAmt = 0.35 + scale * 0.9;
    
    // Idea 2: Tectonic fault-line shears
    let fault = step(0.0, centeredUV.x + centeredUV.y * 0.5) * 0.1;
    let shearedUV = centeredUV + vec2<f32>(fault, -fault);
    
    let tp = shearedUV * terrainScale * (1.0 + audio.x * 0.15);"""
code = code.replace(fault_orig, fault_new)


caldera_orig = """    let hotSpot = exp(-mouseDist * 10.0) * 0.4 * select(0.5, 1.5, mouseDown > 0.5) * (1.0 + audio.x * 0.5);
    let heightWithHotspot = heightNorm + hotSpot + rippleHeat * 0.25;"""
caldera_new = """    let hotSpot = exp(-mouseDist * 10.0) * 0.4 * select(0.5, 1.5, mouseDown > 0.5) * (1.0 + audio.x * 0.5);
    
    // Idea 1: Magma caldera sinks (dark center, hot rim)
    let calderaDist = length(tp - vec2<f32>(2.0, 2.0));
    let calderaRim = exp(-abs(calderaDist - 1.0) * 5.0) * 0.5;
    let calderaSink = -exp(-calderaDist * 3.0) * 0.5;
    
    let heightWithHotspot = heightNorm + hotSpot + rippleHeat * 0.25 + calderaRim + calderaSink;"""
code = code.replace(caldera_orig, caldera_new)


with open('public/shaders/gen-thermal-rainbow-topography.wgsl', 'w') as f:
    f.write(code)

