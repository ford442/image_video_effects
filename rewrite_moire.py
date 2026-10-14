import re

with open('public/shaders/gen-interference-moire-field.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Interference Moire Field
//  Category: generative
//  Features: analytic-lines, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: 6.8% density detune beat; two-source Young path-difference; polarization color banding; sub-wavelength micro-fringes
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

line_orig = """  let beat = 0.5 + 0.5 * cos((lineA - lineB) * 4.0 + treble * 2.0);
  let srcB = mix(vec2<f32>(0.18, 0.0), mouse, held);
  let young = 0.5 + 0.5 * cos((length(p) - length(p - srcB)) * density * 0.32);"""

line_new = """  let beat = 0.5 + 0.5 * cos((lineA - lineB) * 4.0 + treble * 2.0);
  let srcB = mix(vec2<f32>(0.18, 0.0), mouse, held);
  let young = 0.5 + 0.5 * cos((length(p) - length(p - srcB)) * density * 0.32);
  
  // Idea 1: polarization color banding - shift colors tightly based on local phase difference
  let phaseDiff = abs(lineA - lineB);
  let polarization = palette(phaseDiff * 2.5 + colorPhase);
  
  // Idea 2: sub-wavelength micro-fringes - dense interference when main ridges overlap
  let microFringes = sin(q1.x * density * 5.0) * sin(q2.x * density * 5.0) * smoothstep(0.7, 1.0, abs(crossed));"""
code = code.replace(line_orig, line_new)

color_orig = """  var raw = palette(crossed * 0.18 + colorPhase + time * 0.025 + pulse * 0.12) * (0.16 + ridges * 1.25);
  raw += palette(beat * 0.2 + colorPhase + 0.32) * beat * (0.18 + treble * 0.22);
  raw += palette(colorPhase + 0.55) * abs(detuneBeat) * 0.42;
  raw += palette(colorPhase + 0.08) * young * (0.16 + held * 0.12 + treble * 0.08);"""

color_new = """  var raw = polarization * (0.16 + ridges * 1.25);
  raw += palette(beat * 0.2 + colorPhase + 0.32) * beat * (0.18 + treble * 0.22);
  raw += palette(colorPhase + 0.55) * abs(detuneBeat) * 0.42;
  raw += palette(colorPhase + 0.08) * young * (0.16 + held * 0.12 + treble * 0.08);
  raw += vec3<f32>(1.0, 1.5, 2.0) * microFringes * 0.35;"""
code = code.replace(color_orig, color_new)

with open('public/shaders/gen-interference-moire-field.wgsl', 'w') as f:
    f.write(code)
