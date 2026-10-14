import re

with open('public/shaders/gen-celestial-weave.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Celestial Weave
//  Category: generative
//  Features: procedural, audio-reactive, temporal, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: shimmer-driven traveling thread glint; void-depth star parallax; constellation pulse-travel timed to bass; astral dust motes; gravity-lens spacetime warping
//  A packing: display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


dust_orig = """  color = color + starCol * starGlowVal * glowAmp * (0.6 + treble);"""
dust_new = """  color = color + starCol * starGlowVal * glowAmp * (0.6 + treble);
  
  // Idea 1: Astral dust motes
  let dustCoord = uv * 50.0 + vec2<f32>(time * 0.5, time * 0.2);
  let dustNoise = hash21(floor(dustCoord));
  let dustMote = step(0.98, dustNoise) * exp(-length(fract(dustCoord) - 0.5) * 10.0);
  color += vec3<f32>(1.0, 0.8, 0.6) * dustMote * (0.2 + bass);"""
code = code.replace(dust_orig, dust_new)


gravity_orig = """  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * 0.2;"""
gravity_new = """  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  
  // Idea 2: Gravity-lens spacetime warping
  let mouseDelta = p - mouse;
  let mouseDist = length(mouseDelta);
  let gravLens = exp(-mouseDist * 5.0) * 0.5;
  p += mouseDelta * gravLens;
  
  p = p + mouse * 0.2;"""
code = code.replace(gravity_orig, gravity_new)


with open('public/shaders/gen-celestial-weave.wgsl', 'w') as f:
    f.write(code)

