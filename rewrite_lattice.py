import re

with open('public/shaders/gen-chromatic-glass-lattice.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  gen-chromatic-glass-lattice
//  Category: generative
//  Features: raymarched, chromatic-dispersion, audio-reactive, mouse-driven, glass-refraction, upgraded-rgba, depth-aware, aces-tone-map
//  Upgraded: 2026-10-10
//  Ideas: Cauchy multi-order dispersion with internal TIR caustic ribs, acoustic resonance stress birefringence, micro-fracture edge sparkle glints; prismatic node flares; crystalline growth spurs
//  A packing: display RGBA (RGB=ACES tone-mapped glass color, A=alpha/presence)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


spur_orig = """  let q2 = opRep(p + vec3<f32>(cellSize * 0.5), vec3<f32>(cellSize));
  let dBrace = sdBox(q2, vec3<f32>(boxSize * 0.15, boxSize * 0.6, boxSize * 0.15));
  d = smin(d, dBrace, 0.08);"""
  
spur_new = """  let q2 = opRep(p + vec3<f32>(cellSize * 0.5), vec3<f32>(cellSize));
  let dBrace = sdBox(q2, vec3<f32>(boxSize * 0.15, boxSize * 0.6, boxSize * 0.15));
  
  // Idea 2: Crystalline growth spurs (small boxes branching off the struts)
  let qSpur = opRep(p + vec3<f32>(cellSize * 0.25), vec3<f32>(cellSize * 0.5));
  let dSpur = sdBox(qSpur, vec3<f32>(boxSize * 0.08, boxSize * 0.2, boxSize * 0.08));
  
  d = smin(d, smin(dBrace, dSpur, 0.04), 0.08);"""
code = code.replace(spur_orig, spur_new)


flare_orig = """      // Core glow
      let coreCol = vec3<f32>(0.8, 0.3, 0.9) * hitGlow * 2.0
                  + vec3<f32>(0.2, 0.6, 1.0) * hitGlow * audio;"""

flare_new = """      // Core glow
      // Idea 1: Prismatic node flares (starbursts at the lattice intersections)
      let nodeCoord = opRep(p, vec3<f32>(2.2 / latticeDensity));
      let nodeAngle = atan2(nodeCoord.y, nodeCoord.x);
      let flare = pow(abs(sin(nodeAngle * 8.0 + time * 3.0)), 16.0) * hitGlow;
      let flareCol = vec3<f32>(1.0, 0.8, 0.4) * flare * (1.0 + treble * 2.0);
      
      let coreCol = vec3<f32>(0.8, 0.3, 0.9) * hitGlow * 2.0
                  + vec3<f32>(0.2, 0.6, 1.0) * hitGlow * audio
                  + flareCol;"""
code = code.replace(flare_orig, flare_new)

with open('public/shaders/gen-chromatic-glass-lattice.wgsl', 'w') as f:
    f.write(code)

