import re

with open('public/shaders/gen-translucent-nebula.wgsl', 'r') as f:
    code = f.read()

header = """// ═══════════════════════════════════════════════════════════════════
//  Translucent Nebula
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba, chromatic-aberration, distance-lod
//  Complexity: High
//  Description: Volumetric gas clouds with density-based alpha
//    translucency. FBM and Worley noise create nebula structure.
//    Dense cores are opaque while edges fade to transparent.
//    Star sparkle reacts to treble; nebula pulses with bass.
//  Upgraded: 2026-10-10
//  Ideas: Rayleigh-Taylor plume fingers; ionization-front shell bands; protostar accretion disks; supernova shockwave bow-shocks
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════"""
code = re.sub(r'// ═══.*?// ═══════════════════════════════════════════════════════════════════', header, code, flags=re.DOTALL)


stars_orig = """  // ═══ STAR FIELD ═══
  let stars = starField(uv, 42.0, treble) * starDensity;
  let starVisibility = 1.0 - accumDensity * 0.85;
  accumColor = accumColor + stars * starVisibility;"""

stars_new = """  // ═══ STAR FIELD ═══
  let stars = starField(uv, 42.0, treble) * starDensity;
  let starVisibility = 1.0 - accumDensity * 0.85;
  accumColor = accumColor + stars * starVisibility;
  
  // Idea 1: protostar accretion disks (tiny glowing rings scattered in the gas)
  let protoUV = uv * 30.0 + vec2<f32>(time * 0.1);
  let protoHash = hash12(floor(protoUV));
  let protoDist = length(fract(protoUV) - 0.5);
  let protoRing = smoothstep(0.3, 0.4, protoDist) * smoothstep(0.5, 0.4, protoDist);
  let protoStar = step(0.98, protoHash) * protoRing * (0.5 + 0.5 * sin(time * 5.0 + protoHash * 10.0));
  accumColor += vec3<f32>(1.0, 0.5, 0.2) * protoStar * 2.0;
  
  // Idea 2: supernova shockwave bow-shocks (fast sweeping arc)
  let shockDist = length(uv - 0.5);
  let shockRadius = fract(time * 0.2) * 2.0;
  let bowShock = exp(-abs(shockDist - shockRadius) * 50.0) * smoothstep(0.8, 1.0, sin(atan2(uv.y - 0.5, uv.x - 0.5) + time));
  accumColor += vec3<f32>(0.2, 0.6, 1.0) * bowShock * (1.0 + bass);"""
code = code.replace(stars_orig, stars_new)

with open('public/shaders/gen-translucent-nebula.wgsl', 'w') as f:
    f.write(code)

