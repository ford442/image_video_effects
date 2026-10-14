import re

with open('public/shaders/gen-hypnotic-vortex-tunnel.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Hypnotic Vortex Tunnel
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: log-depth seam walls; even/odd contra-rotate; event horizon shear; accretion disk glow
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

shear_orig = """  let theta = atan2(pv.y, pv.x);

  let zBase = -log(max(r / zoom, 0.001)) + t * 0.5 * (1.0 + bass * 0.2);"""
shear_new = """  let theta_orig = atan2(pv.y, pv.x);

  // Idea 1: event horizon shear (tear tunnel walls near the center)
  let shearAmount = exp(-r * 8.0) * sin(t * 5.0) * 0.5;
  let theta = theta_orig + shearAmount;

  let zBase = -log(max(r / zoom, 0.001)) + t * 0.5 * (1.0 + bass * 0.2);"""
code = code.replace(shear_orig, shear_new)

disk_orig = """  let iris = 1.0 - smoothstep(0.0, 0.06, r);
  col = mix(col, vec3<f32>(0.0), iris);"""
disk_new = """  let iris = 1.0 - smoothstep(0.0, 0.06, r);
  col = mix(col, vec3<f32>(0.0), iris);
  
  // Idea 2: accretion disk glow (bright rim light at the tunnel boundary)
  let diskGlow = exp(-abs(r - 0.06) * 40.0) * (0.5 + 0.5 * sin(theta * 10.0 - t * 8.0));
  col += vec3<f32>(1.0, 0.4, 0.1) * diskGlow * (1.0 + bass);"""
code = code.replace(disk_orig, disk_new)

with open('public/shaders/gen-hypnotic-vortex-tunnel.wgsl', 'w') as f:
    f.write(code)

