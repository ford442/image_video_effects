import re

with open('public/shaders/gen-iris-bloom-fractal.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Iris Bloom Fractal
//  Category: generative
//  Features: fractal, polar-geometry, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: collarette zigzag; Fuchs crypt pits near the pupil; ciliary muscle tension ringing; stroma layer parallax
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

loop_orig = """  for (var i = 0; i < 6; i++) {
    if (f32(i) >= bloomDepth) { break; }
    let fi = f32(i);
    let ringR = aperture + 0.07 + fi * 0.085;
    let lobe = cos(angle * (petalCount + fi * 2.0) + time * (0.08 + fi * 0.025) + mids * 0.18);
    let contour = ringR + lobe * (0.035 + fi * 0.006);
    let layer = exp(-abs(r - contour) * (52.0 - fi * 4.0));
    petals += layer / (1.0 + fi * 0.28);
    recursive += layer * (fi + 1.0) / 6.0;
  }"""

loop_new = """  for (var i = 0; i < 6; i++) {
    if (f32(i) >= bloomDepth) { break; }
    let fi = f32(i);
    // Idea 2: stroma layer parallax - offset deeper iterations by mouse
    let q_layer = q - mouse * held * 0.05 * fi;
    let r_layer = length(q_layer);
    let angle_layer = atan2(q_layer.y, q_layer.x);
    let ringR = aperture + 0.07 + fi * 0.085;
    let lobe = cos(angle_layer * (petalCount + fi * 2.0) + time * (0.08 + fi * 0.025) + mids * 0.18);
    let contour = ringR + lobe * (0.035 + fi * 0.006);
    let layer = exp(-abs(r_layer - contour) * (52.0 - fi * 4.0));
    petals += layer / (1.0 + fi * 0.28);
    recursive += layer * (fi + 1.0) / 6.0;
  }"""
code = code.replace(loop_orig, loop_new)

tension_orig = """  let cryptRing = smoothstep(aperture, aperture * 1.45, r) * (1.0 - smoothstep(aperture * 1.7, aperture * 2.15, r));
  let crypts = pow(0.5 + 0.5 * cos(angle * petalCount + r * 38.0), 16.0) * cryptRing * irisMask;"""

tension_new = """  let cryptRing = smoothstep(aperture, aperture * 1.45, r) * (1.0 - smoothstep(aperture * 1.7, aperture * 2.15, r));
  let crypts = pow(0.5 + 0.5 * cos(angle * petalCount + r * 38.0), 16.0) * cryptRing * irisMask;
  
  // Idea 1: ciliary muscle tension ringing - radial contraction waves
  let tensionRings = max(0.0, cos((r - aperture) * 110.0 - time * 3.0)) * exp(-abs(r - aperture * 1.1) * 25.0) * held * irisMask;"""
code = code.replace(tension_orig, tension_new)

color_orig = """  raw += vec3<f32>(0.22, 0.58, 1.25) * limbal * (0.6 + mids * 0.3);
  raw += palette(colorCycle + clickBloom * 0.2) * clickBloom * 0.7;
  raw *= 1.0 - crypts * 0.62;"""

color_new = """  raw += vec3<f32>(0.22, 0.58, 1.25) * limbal * (0.6 + mids * 0.3);
  raw += vec3<f32>(0.8, 0.7, 0.4) * tensionRings * 0.45;
  raw += palette(colorCycle + clickBloom * 0.2) * clickBloom * 0.7;
  raw *= 1.0 - crypts * 0.62;"""
code = code.replace(color_orig, color_new)


with open('public/shaders/gen-iris-bloom-fractal.wgsl', 'w') as f:
    f.write(code)
