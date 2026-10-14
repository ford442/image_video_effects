import re

# 2. gen-ethereal-glass-flora-terrarium
with open('public/shaders/gen-ethereal-glass-flora-terrarium.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Ethereal Glass-Flora Terrarium
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-10-10
//  Ideas: condensation droplet beads on terrarium glass shell; dew meniscus highlights on leaf-tip normals; terrarium base moss; firefly spark swarms
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

moss_orig = """  // Condensation beads on the outer terrarium glass shell.
  let shellProbe = ro + rd * 7.8;
  let condense = condensationDroplets(shellProbe, time);
  col += vec3<f32>(0.75, 0.92, 1.0) * condense * (0.2 + mids * 0.15);
  alpha = sat(alpha + condense * 0.12);"""
  
moss_new = """  // Condensation beads on the outer terrarium glass shell.
  let shellProbe = ro + rd * 7.8;
  let condense = condensationDroplets(shellProbe, time);
  col += vec3<f32>(0.75, 0.92, 1.0) * condense * (0.2 + mids * 0.15);
  alpha = sat(alpha + condense * 0.12);
  
  // Idea 1: Terrarium base moss: Green fuzzy noise texture along the bottom of the glass sphere.
  let mossDist = max(0.0, -shellProbe.y - 2.5);
  let mossNoise = fbm3(shellProbe * 5.0, 4);
  let moss = smoothstep(0.0, 1.0, mossDist * mossNoise * 4.0);
  col = mix(col, vec3<f32>(0.1, 0.6, 0.2), moss * 0.8);
  alpha = sat(alpha + moss);
  
  // Idea 2: Firefly spark swarms: Bright glowing dots drifting inside the terrarium space.
  let fireflyP = shellProbe * 3.0 + vec3<f32>(time, sin(time)*0.5, time * 0.5);
  let fireflyNoise = hash3(floor(fireflyP));
  let firefly = step(0.995, fireflyNoise) * exp(-length(fract(fireflyP) - 0.5) * 10.0) * (1.0 - smoothstep(3.5, 4.0, length(shellProbe)));
  col += vec3<f32>(1.0, 0.9, 0.4) * firefly * (2.0 + treble * 5.0);"""
code = code.replace(moss_orig, moss_new)

with open('public/shaders/gen-ethereal-glass-flora-terrarium.wgsl', 'w') as f:
    f.write(code)

# 10. gen-ethereal-chrono-flora-loom
with open('public/shaders/gen-ethereal-chrono-flora-loom.wgsl', 'r') as f:
    code = f.read()

header2 = """// ═══════════════════════════════════════════════════════════════════
//  Ethereal Chrono-Flora Loom
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-10
//  Ideas: warp-thread helices along the loom axis; weft shuttle bead at flow speed; chrono-petal clock face; temporal gear-tooth rims
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header2, code, flags=re.DOTALL)

gear_orig = """    // Flora structure (capsule/cylinder)
    let d_stem = length(p_folded.xy - vec2<f32>(0.5, 0.0)) - 0.1 * density * (1.0 + fft_mod);"""
gear_new = """    // Idea 2: Temporal gear-tooth rims
    let gearTeeth = abs(sin(p_mod.z * 10.0 - t * 2.0)) * 0.03 * density;
    
    // Flora structure (capsule/cylinder)
    let d_stem = length(p_folded.xy - vec2<f32>(0.5, 0.0)) - (0.1 * density * (1.0 + fft_mod) + gearTeeth);"""
code = code.replace(gear_orig, gear_new)


clock_orig = """    var d = smin(d_stem, d_orb, 0.5);
    d = smin(d, d_warp, 0.22);"""
clock_new = """    // Idea 1: Chrono-petal clock face
    let clockRadius = length(p_mod.xy);
    let clockAngle = atan2(p_mod.y, p_mod.x);
    let clockTicks = abs(sin(clockAngle * 6.0)) * 0.1;
    let d_clock = max(abs(clockRadius - 2.0) - 0.05, -clockTicks);

    var d = smin(d_stem, d_orb, 0.5);
    d = smin(d, d_warp, 0.22);
    d = smin(d, d_clock, 0.15);"""
code = code.replace(clock_orig, clock_new)

clockmat_orig = """    } else if (d_warp < d_stem && d_warp < d_orb) {
        mat = 2.0;
    }"""
clockmat_new = """    } else if (d_clock < d_stem && d_clock < d_orb && d_clock < d_warp && d_clock < d_shuttle) {
        mat = 4.0;
    } else if (d_warp < d_stem && d_warp < d_orb) {
        mat = 2.0;
    }"""
code = code.replace(clockmat_orig, clockmat_new)


colormat_orig = """        if (mat > 2.5) {
            col += vec3<f32>(1.0, 0.92, 0.75) * (1.2 + audioBass);
        } else if (mat > 1.5) {
            col += palette(u.zoom_params.w + 0.35) * 0.45;
        }"""
colormat_new = """        if (mat > 3.5) {
            col += vec3<f32>(0.5, 0.8, 1.0) * (0.8 + mids);
        } else if (mat > 2.5) {
            col += vec3<f32>(1.0, 0.92, 0.75) * (1.2 + audioBass);
        } else if (mat > 1.5) {
            col += palette(u.zoom_params.w + 0.35) * 0.45;
        }"""
code = code.replace(colormat_orig, colormat_new)

with open('public/shaders/gen-ethereal-chrono-flora-loom.wgsl', 'w') as f:
    f.write(code)

