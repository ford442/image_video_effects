import re

with open('public/shaders/gen-voronoi-crystal.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Voronoi Crystal
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: triple-junction grain corners; L∞ facet flats; dislocation glide lines; annealing front bloom; crystalline structural faults; piezoelectric charge flashes
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


fault_orig = """    // Aspect correction
    let aspect = resolution.x / resolution.y;
    var p = uv * vec2<f32>(aspect, 1.0);"""

fault_new = """    // Aspect correction
    let aspect = resolution.x / resolution.y;
    var p = uv * vec2<f32>(aspect, 1.0);
    
    // Idea 1: crystalline structural faults (diagonal coordinate shift)
    let fault = step(0.0, p.x + p.y - 1.0) * 0.1;
    p += vec2<f32>(fault, -fault);"""
code = code.replace(fault_orig, fault_new)


flash_orig = """    // Add depth shading
    col = col * (0.7 + 0.3 * depth);"""
    
flash_new = """    // Add depth shading
    col = col * (0.7 + 0.3 * depth);
    
    // Idea 2: piezoelectric charge flashes (bright flashes on random cells)
    let flash = step(0.98, fract(cellHash * 100.0 + t * 5.0)) * interior * (1.0 + treble);
    col += vec3<f32>(0.8, 0.9, 1.0) * flash * 2.0;"""
code = code.replace(flash_orig, flash_new)

with open('public/shaders/gen-voronoi-crystal.wgsl', 'w') as f:
    f.write(code)

