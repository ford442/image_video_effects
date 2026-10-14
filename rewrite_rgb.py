import re

with open('public/shaders/gen-rgb-diffraction.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  RGB Diffraction
//  Category: generative
//  Features: audio-reactive, mouse-driven, psychedelic, procedural, temporal, chromatic, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: single-slit diffraction envelope over the multi-slit fringes; blaze-angle steering of principal maxima by mouse; Talbot self-imaging replicas; order-selective grating lobes; hexagonal diffraction grating; zero-order central bright spot
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

hex_orig = """  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  p = applySymmetry(p, SYMMETRY);

  // Wavelengths for R G B (relative)"""

hex_new = """  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  p = applySymmetry(p, SYMMETRY);
  
  // Idea 1: hexagonal diffraction grating mask
  let hexMask = 0.8 + 0.2 * sin(p.x * 50.0) * sin((p.x * 0.5 + p.y * 0.866) * 50.0) * sin((p.x * 0.5 - p.y * 0.866) * 50.0);
  p *= hexMask;

  // Wavelengths for R G B (relative)"""
code = code.replace(hex_orig, hex_new)

zero_orig = """  // Idea 4 — order-selective grating lobes with rolloff by order index.
  var lobes = 0.0;"""
zero_new = """  // Idea 2: Zero-order central bright spot (intense bloom at origin)
  let zeroOrder = exp(-axisRad * 40.0) * 2.5 * (1.0 + bass);
  color += vec3<f32>(1.0, 0.9, 0.8) * zeroOrder;

  // Idea 4 — order-selective grating lobes with rolloff by order index.
  var lobes = 0.0;"""
code = code.replace(zero_orig, zero_new)


with open('public/shaders/gen-rgb-diffraction.wgsl', 'w') as f:
    f.write(code)

