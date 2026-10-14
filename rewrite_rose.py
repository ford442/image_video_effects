import re

with open('public/shaders/gen-islamic-star-rose.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Islamic Geometric Star-Rose
//  Category: generative
//  Features: upgraded-rgba, temporal, audio-reactive, mouse-driven,
//    islamic, star, rose, geometric, girih, tessellation
//  Complexity: Very High
//  Upgraded: 2026-10-10
//  Ideas: nested φ pentagrams; 10-fold rose from 36° sectors; overlapping star point shadows; central rose bloom
//  A packing: ACES display RGBA
//  Wolfram Data: Regular pentagon — interior angle 108° = 3π/5 rad;
//    central angle 72° = 2π/5 rad; diagonal/edge ratio φ = (1+√5)/2 ≈ 1.618;
//    height = √(5+2√5)/2 × s ≈ 1.539s;
//    star polygon {n/k} where k=2 for pentagram
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


rose_orig = """  let roseDist = sd_pentagon_rosette(ruv, 0.12 * zoom * (1.0 + mouseMorph * 2.0));"""
rose_new = """  // Idea 2: central rose bloom - pulse expansion on bass
  let roseDist = sd_pentagon_rosette(ruv, 0.12 * zoom * (1.0 + mouseMorph * 2.0 + bass * 0.6));"""
code = code.replace(rose_orig, rose_new)

shadow_orig = """  // Background pattern (subtle repeating motif)
  let bg_pattern = sin(p_uv.x * 20.0) * sin(p_uv.y * 20.0) * 0.5 + 0.5;
  color += vec3<f32>(0.03, 0.05, 0.08) * bg_pattern * 0.1;"""
shadow_new = """  // Background pattern (subtle repeating motif)
  let bg_pattern = sin(p_uv.x * 20.0) * sin(p_uv.y * 20.0) * 0.5 + 0.5;
  color += vec3<f32>(0.03, 0.05, 0.08) * bg_pattern * 0.1;
  
  // Idea 1: overlapping star point shadows - using the edge_dist gradient
  let shadowOffset = vec2<f32>(0.02, 0.03) * zoom;
  let shadow = smoothstep(0.0, 0.08, edge_dist - 0.015);
  color *= 0.65 + 0.35 * shadow;"""
code = code.replace(shadow_orig, shadow_new)

with open('public/shaders/gen-islamic-star-rose.wgsl', 'w') as f:
    f.write(code)

