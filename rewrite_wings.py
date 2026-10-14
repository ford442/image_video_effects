import re

with open('public/shaders/gen-celestial-aether-seraphim-wings.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Celestial Aether-Seraphim Wings
//  Category: generative
//  Features: upgraded-rgba, temporal-feedback, audio-reactive, mouse-driven, raymarched
//  Complexity: High
//  Enrichment: Aerodynamic lift (Wolfram Alpha)
//    C_L = 2πα (thin airfoil, small angle α in radians)
//    Stall angle: ~15° (0.262 rad)
//    C_D ≈ C_D0 + C_L²/(π A R e)
//    Lift drives brightness; stall = turbulent breakdown
//  Upgraded: 2026-10-10
//  Ideas: stall-vortex shedding perturbs the feather fold geometry past the
//         stall angle (turbulent breakup, not just a color tint); lift-direction
//         hue shift tints the leading edge warm/cool by the sign of AOA; aether plumage contour lines; angelic halo refraction
//  A packing: display RGBA (same as writeTexture), exact history read fixed
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


contour_orig = """    // Wing feather structures
    let feather = length(p.xz) - u.zoom_params.y * (1.0 - f32(i) * 0.15);
    d = smin(d, feather, 0.3);
  }"""
contour_new = """    // Wing feather structures
    let feather = length(p.xz) - u.zoom_params.y * (1.0 - f32(i) * 0.15);
    
    // Idea 1: Aether plumage contour lines
    let contour = abs(fract(feather * 10.0 - time * 2.0) - 0.5) * 0.1;
    d = smin(d, max(feather, -contour), 0.3);
  }"""
code = code.replace(contour_orig, contour_new)


halo_orig = """  // Atmospheric Fog
  col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.05 * t));"""
halo_new = """  // Idea 2: Angelic halo refraction (a giant floating ring above)
  let haloDist = length(uv - vec2<f32>(0.0, 0.6)) - 0.5;
  let haloRing = smoothstep(0.05, 0.0, abs(haloDist));
  col += vec3<f32>(1.0, 0.9, 0.4) * haloRing * (0.5 + treble);

  // Atmospheric Fog
  col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.05 * t));"""
code = code.replace(halo_orig, halo_new)

with open('public/shaders/gen-celestial-aether-seraphim-wings.wgsl', 'w') as f:
    f.write(code)

