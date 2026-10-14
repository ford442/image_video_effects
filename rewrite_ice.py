import re

with open('public/shaders/gen-ice-crystal-lattice.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Ice Crystal Lattice
//  Category: generative
//  Features: procedural, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: secondary dendrite teeth on hex arms; plate vs needle habit; hoarfrost rime; thermal melt pooling
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

l_orig = """  let n0 = vec2<f32>(1.0, 0.0);
  let n1 = vec2<f32>(0.5, 0.8660254);
  let n2 = vec2<f32>(-0.5, 0.8660254);
  let width = mix(0.055, 0.018, clamp(u.zoom_params.x, 0.0, 1.0));
  let l0 = latticeLine(p, n0, density, width);
  let l1 = latticeLine(p, n1, density, width);
  let l2 = latticeLine(p, n2, density, width);"""

l_new = """  // Idea 1: hoarfrost rime — high frequency noise displacement along the lattice edges
  let rime = (sin(p.x * density * 8.0 + time) * cos(p.y * density * 8.0 - time)) * 0.02;
  let rimeP = p + vec2<f32>(rime, rime * 0.5);

  let n0 = vec2<f32>(1.0, 0.0);
  let n1 = vec2<f32>(0.5, 0.8660254);
  let n2 = vec2<f32>(-0.5, 0.8660254);
  let width = mix(0.055, 0.018, clamp(u.zoom_params.x, 0.0, 1.0));
  let l0 = latticeLine(rimeP, n0, density, width);
  let l1 = latticeLine(rimeP, n1, density, width);
  let l2 = latticeLine(rimeP, n2, density, width);"""
code = code.replace(l_orig, l_new)

h_orig = """  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.945, raw, 0.24 + growthSpeed * 0.12), vec3<f32>(0.0), vec3<f32>(7.0));"""

h_new = """  let prev = textureLoad(dataTextureC, pixel, 0);
  
  // Idea 2: thermal melt pooling — slow decay and downward flow in the history buffer
  let meltDown = textureLoad(dataTextureC, pixel + vec2<i32>(0, 1), 0).rgb;
  let pooledHistory = mix(prev.rgb, meltDown, 0.15 * clamp(u.zoom_params.w, 0.0, 1.0)) * 0.94;
  
  raw = clamp(mix(pooledHistory, raw, 0.24 + growthSpeed * 0.12), vec3<f32>(0.0), vec3<f32>(7.0));"""
code = code.replace(h_orig, h_new)

with open('public/shaders/gen-ice-crystal-lattice.wgsl', 'w') as f:
    f.write(code)

