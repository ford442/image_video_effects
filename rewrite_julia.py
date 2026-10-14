import re

with open('public/shaders/gen-julia-set-classic.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Julia Set Classic
//  Category: generative
//  Features: escape-time, orbit-trap, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: exterior distance estimate; log|z| stripe coloring; spiral orbit traps; pseudo-3D orbit slice twist
//  A packing: raw HDR display RGBA (ACES on writeTexture)
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

loop_orig = """    let r2 = dot(z, z);
    trap = min(trap, min(abs(z.x), abs(length(z) - 0.5)));
    orbit += exp(-abs(length(z) - 1.0) * 8.0) / f32(iterations);
    stripeAcc += 0.5 + 0.5 * sin(log(max(r2, 0.0001)) * 4.2);"""

loop_new = """    let r2 = dot(z, z);
    
    // Idea 1: spiral orbit traps instead of simple lines
    let spiral = abs(sin(atan2(z.y, z.x) * 3.0 + length(z) * 5.0 - time * 2.0));
    trap = min(trap, min(spiral * 0.3, abs(length(z) - 0.5)));
    
    // Idea 2: pseudo-3D orbit slice twist
    let twist = sin(f32(i) * 0.1 + time) * 0.02;
    z = vec2<f32>(z.x * cos(twist) - z.y * sin(twist), z.x * sin(twist) + z.y * cos(twist));
    
    orbit += exp(-abs(length(z) - 1.0) * 8.0) / f32(iterations);
    stripeAcc += 0.5 + 0.5 * sin(log(max(r2, 0.0001)) * 4.2);"""
code = code.replace(loop_orig, loop_new)

with open('public/shaders/gen-julia-set-classic.wgsl', 'w') as f:
    f.write(code)

