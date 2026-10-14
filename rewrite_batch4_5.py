import re

# 5. gen-ethereal-quantum-medusa
with open('public/shaders/gen-ethereal-quantum-medusa.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Ethereal Quantum-Medusa
//  Category: generative
//  Features: raymarched, audio-reactive, mouse-gravity-well, feedback-loops,
//            upgraded-rgba, chromatic-tentacles, temporal-bioluminescence,
//            audio-sway, depth-output, gravity-attractor, mouse-trail
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: nematocyst stinger dots along tentacle rim from edge SDF; bell contraction wave from radial phase tied to bass; gonadal ring clover; abyssal snow particulates
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)

gonadal_orig = """        // Nematocyst stinger dots along tentacle rim from edge SDF
        let rimDist = length(p.xz);
        let tentRim = smoothstep(0.12, 0.32, rimDist) * smoothstep(2.2, 0.7, rimDist) * smoothstep(0.4, -0.1, p.y);"""
gonadal_new = """        // Idea 1: Gonadal ring clover: Four bright luminescent rings visible through the medusa bell
        let gonadAngle = atan2(p.z, p.x);
        let gonadDist = length(p.xz);
        let gonadRings = smoothstep(0.05, 0.0, abs(length(vec2<f32>(gonadDist - 0.4, p.y + 0.3)) - 0.2)) * abs(cos(gonadAngle * 2.0));
        col += vec3<f32>(1.0, 0.4, 0.8) * gonadRings * (1.0 + treble * 2.0) * hit;

        // Nematocyst stinger dots along tentacle rim from edge SDF
        let rimDist = length(p.xz);
        let tentRim = smoothstep(0.12, 0.32, rimDist) * smoothstep(2.2, 0.7, rimDist) * smoothstep(0.4, -0.1, p.y);"""
code = code.replace(gonadal_orig, gonadal_new)

snow_orig = """    // Feedback loop: blend with previous frame for motion trails
    col = mix(col, prevFrame.rgb * 0.95, 0.08 + bass * 0.03);"""
snow_new = """    // Idea 2: Abyssal snow particulates
    let snowUV = uv * 3.0 + vec2<f32>(0.0, time * 0.1);
    let snowP = vec3<f32>(snowUV, time * 0.05);
    let snowNoise = fract(sin(dot(floor(snowP * 20.0), vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
    let snow = step(0.995, snowNoise) * exp(-length(fract(snowP * 20.0) - 0.5) * 10.0);
    col += vec3<f32>(0.8, 0.9, 1.0) * snow * (0.2 + bass * 0.5) * (1.0 - hit);

    // Feedback loop: blend with previous frame for motion trails
    col = mix(col, prevFrame.rgb * 0.95, 0.08 + bass * 0.03);"""
code = code.replace(snow_orig, snow_new)

with open('public/shaders/gen-ethereal-quantum-medusa.wgsl', 'w') as f:
    f.write(code)


# 6. gen-ethereal-silk-veil
with open('public/shaders/gen-ethereal-silk-veil.wgsl', 'r') as f:
    code = f.read()

header2 = """// ═══════════════════════════════════════════════════════════════════
//  Ethereal Silk Veil
//  Category: generative
//  Features: generative, audio-reactive, mouse-driven, temporal, depth-aware,
//            upgraded-rgba, aces-tone-map, chromatic-aberration
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: selvage fray noise along ribbon width edges; held-crease memory blended from exact C when mouse down; silk moire interference; warp thread glints
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header2, code, flags=re.DOTALL)

moire_orig = """    // Sheen on fold peaks (where derivative crosses zero going up)
    let sheenMask = pow(smoothstep(0.4, 0.6, foldDepth), 3.0) * sheenAmount;
    layerColor = mix(layerColor, goldSheen, sheenMask * (0.5 + bass * 0.3));
    layerColor += goldSheen * selvageZone * 0.22;"""
moire_new = """    // Sheen on fold peaks (where derivative crosses zero going up)
    let sheenMask = pow(smoothstep(0.4, 0.6, foldDepth), 3.0) * sheenAmount;
    layerColor = mix(layerColor, goldSheen, sheenMask * (0.5 + bass * 0.3));
    layerColor += goldSheen * selvageZone * 0.22;
    
    // Idea 1: Silk moire interference
    let moire = sin((uv.x - gatherX) * 200.0 + uv.y * 50.0) * sin((uv.x - gatherX) * 150.0 - uv.y * 100.0);
    layerColor += layerColor * moire * 0.15 * (1.0 + treble);

    // Idea 2: Warp thread glints
    let warpThreads = pow(max(0.0, sin(distToRibbon * 300.0)), 12.0);
    layerColor += goldSheen * warpThreads * sheenMask * 0.8 * (0.5 + mids);"""
code = code.replace(moire_orig, moire_new)

with open('public/shaders/gen-ethereal-silk-veil.wgsl', 'w') as f:
    f.write(code)

