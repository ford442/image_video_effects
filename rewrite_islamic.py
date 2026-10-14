import re

with open('public/shaders/gen-islamic-geometric-tiling.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Islamic Geometric Tiling
//  Category: generative
//  Features: star-polygons, rosette, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: over-under strap shadow at crossings; half-angle girih dart; gold leaf specular glints; ceramic tile glaze imperfections
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

geom_orig = """  let overlap = starLine * interlace;
  let underShadow = overlap * crossingMask;"""

geom_new = """  let overlap = starLine * interlace;
  let underShadow = overlap * crossingMask;
  
  // Idea 1: gold leaf specular glints at star vertices
  let vertexPhase = cos(angle * points);
  let glint = smoothstep(0.96, 1.0, vertexPhase) * exp(-abs(radius - starRadius) / max(lineWidth * 0.5, 0.001));
  
  // Idea 2: ceramic tile glaze imperfections
  let glazeNoise = (sin(grid.x * 4.1 + time * 0.2) * cos(grid.y * 3.7 - time * 0.15)) * 0.5 + 0.5;
  let glaze = glazeNoise * 0.08;"""
code = code.replace(geom_orig, geom_new)

color_orig = """  var raw = vec3<f32>(0.012, 0.018, 0.035);
  raw += palette(hue) * geometry * (0.55 + bass * 0.3);
  raw += vec3<f32>(1.65 + bass * 0.25, 0.92 + mids * 0.22, 0.25 + treble * 0.15) * (starLine * 0.45 + gildedWave * 1.15);
  raw += palette(hue + 0.42) * interlace * treble * 0.48;
  raw += vec3<f32>(1.55, 1.05, 0.32) * dart * 0.38;
  raw *= 1.0 - underShadow * 0.42;"""

color_new = """  var raw = vec3<f32>(0.012, 0.018, 0.035) + glaze * vec3<f32>(0.1, 0.15, 0.2);
  raw += palette(hue) * geometry * (0.55 + bass * 0.3);
  raw += vec3<f32>(1.65 + bass * 0.25, 0.92 + mids * 0.22, 0.25 + treble * 0.15) * (starLine * 0.45 + gildedWave * 1.15 + glint * 2.5);
  raw += palette(hue + 0.42) * interlace * treble * 0.48;
  raw += vec3<f32>(1.55, 1.05, 0.32) * dart * 0.38;
  raw *= 1.0 - underShadow * 0.42;"""
code = code.replace(color_orig, color_new)

alpha_orig = """  let alpha = clamp(0.035 + geometry * 0.5 + dart * 0.12 + gildedWave * 0.2, 0.035, 0.98);"""
alpha_new = """  let alpha = clamp(0.035 + geometry * 0.5 + dart * 0.12 + gildedWave * 0.2 + glint * 0.2 + glaze, 0.035, 0.98);"""
code = code.replace(alpha_orig, alpha_new)

with open('public/shaders/gen-islamic-geometric-tiling.wgsl', 'w') as f:
    f.write(code)

