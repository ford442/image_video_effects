import re

# 1. gen-depth-refracted-liquid-stained-glass
with open('public/shaders/gen-depth-refracted-liquid-stained-glass.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Depth-Refracted Liquid Stained Glass
//  Category: generative
//  Features: facet-refraction, depth-aware, chromatic-aberration, upgraded-rgba,
//            temporal-rotation, audio-refraction, chromatic-edge-dispersion
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: leaded-came specular highlight along facet seams; depth-driven caustic
//         focus glow where steep bevels concentrate the refraction; lead came structural lattice; solder joint nodes
//  A packing: A/C = final ACES display RGBA; exact stained-glass tint history
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

lattice_orig = """    // Idea 1 — leaded-came highlight: a sharp specular line right on the facet
    // seam, brighter where the key light grazes it, like metal holding the glass.
    let seamKey = max(dot(normal, normalize(vec3<f32>(0.55, 0.75, 0.8))), 0.0);"""

lattice_new = """    // Idea 3: Lead came structural lattice: Thick dark borders drawn between Voronoi cells.
    let cameLattice = smoothstep(0.012, 0.0, edgeDistance);
    col *= 1.0 - cameLattice;
    // Idea 4: Solder joint nodes: Small circular metallic blobs at the intersections
    let nodeDist = length(fract(vec2<f32>(sector * facetCount, r * (4.0 + facetCount * 0.45))) - 0.5);
    let solderNode = smoothstep(0.12, 0.08, nodeDist) * cameLattice;
    col += vec3<f32>(0.6, 0.65, 0.7) * solderNode * (0.5 + seamKey * 0.5);
    
    // Idea 1 — leaded-came highlight: a sharp specular line right on the facet
    // seam, brighter where the key light grazes it, like metal holding the glass.
    let seamKey = max(dot(normal, normalize(vec3<f32>(0.55, 0.75, 0.8))), 0.0);"""
# wait, seamKey is defined *after* we use it in the new code.
# let's fix that.
lattice_new = """    let seamKey = max(dot(normal, normalize(vec3<f32>(0.55, 0.75, 0.8))), 0.0);

    // Idea 3: Lead came structural lattice: Thick dark borders drawn between Voronoi cells.
    let cameLattice = smoothstep(0.012, 0.0, edgeDistance);
    col *= 1.0 - cameLattice;
    // Idea 4: Solder joint nodes: Small circular metallic blobs at the intersections
    let nodeDist = length(fract(vec2<f32>(sector * facetCount, r * (4.0 + facetCount * 0.45))) - 0.5);
    let solderNode = smoothstep(0.12, 0.08, nodeDist) * cameLattice;
    col += vec3<f32>(0.6, 0.65, 0.7) * solderNode * (0.5 + seamKey * 0.5);
    
    // Idea 1 — leaded-came highlight: a sharp specular line right on the facet
    // seam, brighter where the key light grazes it, like metal holding the glass."""
code = code.replace(lattice_orig, lattice_new)

with open('public/shaders/gen-depth-refracted-liquid-stained-glass.wgsl', 'w') as f:
    f.write(code)

# 9. gen-cymatic-quantum-silk-loom
with open('public/shaders/gen-cymatic-quantum-silk-loom.wgsl', 'r') as f:
    code = f.read()

header2 = """// ═══════════════════════════════════════════════════════════════════
//  Cymatic Quantum-Silk Loom
//  Category: generative
//  Features: raymarched, cymatic, silk-ribbons, iridescent,
//            audio-reactive, mouse-driven, click-reactive, upgraded-rgba,
//            depth-aware, flowing, neon-spectrum
//  Complexity: Very High
//  Upgraded: 2026-10-10
//  Ideas: Chladni plate nodal nodes; quantum interference fringe
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header2, code, flags=re.DOTALL)

fringe_orig = """      // Treble sparkles on silk edges
      let sparkle = pow(sat(1.0 - abs(viewAngle)), 8.0) * treble * 2.0;
      col = col + vec3<f32>(1.0, 0.9, 0.7) * sparkle;"""
fringe_new = """      // Treble sparkles on silk edges
      let sparkle = pow(sat(1.0 - abs(viewAngle)), 8.0) * treble * 2.0;
      col = col + vec3<f32>(1.0, 0.9, 0.7) * sparkle;
      
      // Idea 1: Chladni plate nodal nodes
      let cymaticValue = sin(p.x * cymFreq * 5.0 + time * 2.0) * cos(p.y * cymFreq * 3.0 + time * 1.5);
      let nodalNode = smoothstep(0.05, 0.0, abs(cymaticValue)) * exp(-abs(p.z) * 2.0);
      col += vec3<f32>(1.0, 0.9, 0.4) * nodalNode * hitGlow * (2.0 + treble * 4.0);

      // Idea 2: Quantum interference fringe
      let fringe = sin(p.z * 20.0 - time * 5.0) * bass * 0.2;
      col.r += fringe;
      col.b -= fringe;"""
code = code.replace(fringe_orig, fringe_new)

with open('public/shaders/gen-cymatic-quantum-silk-loom.wgsl', 'w') as f:
    f.write(code)

