import re

with open('public/shaders/gen-isometric-city.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Isometric Cyber-City
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: podium+tower setbacks; window occupancy flicker; neon rooftop signs; traffic light streams
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


signs_orig = """            if (isSide > 0.5 && windowPattern > 0.5) {
                // Window light
                 baseCol += glowCol * glowIntensity * (1.0 + treble * 0.5);
            } else if (n.y > 0.9) {
                // Roof lights or rim
                if (fract(p.x*2.0) < 0.1 || fract(p.z*2.0) < 0.1) {
                     baseCol += glowCol * 0.5 * glowIntensity;
                }
            }"""

signs_new = """            if (isSide > 0.5 && windowPattern > 0.5) {
                // Window light
                 baseCol += glowCol * glowIntensity * (1.0 + treble * 0.5);
                 
                 // Idea 1: Holographic billboards floating on tall building sides
                 if (h_rnd > 0.7 && fract(p.y * 3.0 - time) < 0.15) {
                     baseCol += vec3<f32>(1.0, 0.2, 0.8) * 3.0; // Magenta holo bands
                 }
            } else if (n.y > 0.9) {
                // Roof lights or rim
                if (fract(p.x*2.0) < 0.1 || fract(p.z*2.0) < 0.1) {
                     baseCol += glowCol * 0.5 * glowIntensity;
                }
            }"""
code = code.replace(signs_orig, signs_new)

traffic_orig = """            if (isTraffic > 0.0) {
                col += vec3<f32>(1.0, 0.8, 0.2) * 2.0; // Orange headlights
            }"""
traffic_new = """            if (isTraffic > 0.0) {
                col += vec3<f32>(1.0, 0.8, 0.2) * 2.0; // Orange headlights
            }
            
            // Idea 2: hovercar trails (vertical offset traffic)
            if (edgeDist > 0.45 && fract(time * speed * 2.0 + laneHash * 50.0) > 0.9) {
                // Add blue hover trails slightly above ground
                col += vec3<f32>(0.2, 0.6, 1.0) * 3.0;
            }"""
code = code.replace(traffic_orig, traffic_new)

with open('public/shaders/gen-isometric-city.wgsl', 'w') as f:
    f.write(code)

