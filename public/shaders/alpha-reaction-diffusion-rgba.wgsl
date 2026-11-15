// ═══════════════════════════════════════════════════════════════════
//  Alpha Reaction Diffusion RGBA
//  Category: simulation
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-12, 2026-11-15
//  Ideas: nutrient chemotaxis along photo luma; interface membrane |∇(g−a)|; isotropic 9-point Laplacian (§12.2D); chromatic habitat partitioning & wet-agar meniscus sheen
//  A packing: raw (warm U, warm V, cool U, cool V)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn stateAt(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> { return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1);
  let res = vec2<f32>(size); let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0); let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  var s = stateAt(p, hi);
  let seed = step(0.82, hash21(floor(uv * 41.0)));
  let needsSeed = time < 0.12 || dot(s, s) < 0.000001;
  s = select(s, vec4<f32>(1.0, seed * 0.62, 1.0, seed * 0.38), needsSeed);

  let l = stateAt(p + vec2<i32>(-1, 0), hi); let r = stateAt(p + vec2<i32>(1, 0), hi);
  let t = stateAt(p + vec2<i32>(0, -1), hi); let btm = stateAt(p + vec2<i32>(0, 1), hi);
  // ── Idea 3: continuum-matched isotropic 9-point Laplacian (§12.2D) ──
  // Eliminates horizontal/vertical pixel-axis pinning on Turing spots and coral stripes
  // while keeping identical continuum diffusivity to the 5-point stencil.
  let tl = stateAt(p + vec2<i32>(-1, -1), hi); let tr = stateAt(p + vec2<i32>(1, -1), hi);
  let bl = stateAt(p + vec2<i32>(-1, 1), hi);  let br = stateAt(p + vec2<i32>(1, 1), hi);
  let lap = (10.0 / 3.0) * (0.20 * (l + r + t + btm) + 0.05 * (tl + tr + bl + br) - s);

  let feed = mix(0.018, 0.064, u.zoom_params.x) + audio.y * 0.004;
  let kill = mix(0.041, 0.071, u.zoom_params.y) + audio.x * 0.005;
  let cross = mix(0.01, 0.24, u.zoom_params.z) * (1.0 + audio.y * 0.25);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let nutrient = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let reactAB = s.r * s.g * s.g; let reactCD = s.b * s.a * s.a;
  let ds = vec4<f32>(
    (0.84 + audio.y * 0.08) * lap.r - reactAB + feed * (1.0 - s.r) - cross * s.r * s.a,
    (0.31 + audio.x * 0.05) * lap.g + reactAB - (feed + kill) * s.g,
    (0.76 + audio.z * 0.10) * lap.b - reactCD + feed * (1.0 - s.b) - cross * s.b * s.g,
    (0.27 + audio.x * 0.04) * lap.a + reactCD - (feed + kill * 0.97) * s.a
  );
  s = clamp(s + ds * 0.78, vec4<f32>(0.0), vec4<f32>(1.0));
  // ── Idea 4 (part a): chromatic habitat partitioning ─────────────────
  // Warm vs. cool photo chromaticity selectively enriches the warm (s.r) vs. cool (s.b)
  // substrate so the two ecological species colonize matching chromatic zones of the image.
  let chromaNiche = clamp(src.r - src.b, -0.65, 0.65);
  s.r += clamp(nutrient + chromaNiche * 0.55, 0.0, 1.3) * u.zoom_params.w * 0.012;
  s.b += clamp((1.0 - nutrient) - chromaNiche * 0.55, 0.0, 1.3) * u.zoom_params.w * 0.009;

  // Idea 1 — nutrient chemotaxis: inhibitors step along the photo-luma gradient
  let srcL = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(1.0 / res.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let srcR = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(1.0 / res.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let srcT = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, 1.0 / res.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let srcB = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, 1.0 / res.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let lumL = dot(srcL.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let lumR = dot(srcR.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let lumT = dot(srcT.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let lumBt = dot(srcB.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let nGrad = vec2<f32>(lumR - lumL, lumBt - lumT);
  let fromGx = select(l.g, r.g, nGrad.x > 0.0);
  let fromGy = select(t.g, btm.g, nGrad.y > 0.0);
  let fromAx = select(l.a, r.a, nGrad.x < 0.0);
  let fromAy = select(t.a, btm.a, nGrad.y < 0.0);
  let taxis = u.zoom_params.w * 0.08;
  s.g = clamp(s.g + (fromGx - s.g) * abs(nGrad.x) * taxis + (fromGy - s.g) * abs(nGrad.y) * taxis, 0.0, 1.0);
  s.a = clamp(s.a + (fromAx - s.a) * abs(nGrad.x) * taxis + (fromAy - s.a) * abs(nGrad.y) * taxis, 0.0, 1.0);

  // Idea 2 — interface membrane where warm V meets cool V
  let gradV_warm = vec2<f32>(r.g - l.g, btm.g - t.g);
  let gradV_cool = vec2<f32>(r.a - l.a, btm.a - t.a);
  let gGrad = abs(gradV_warm.x) + abs(gradV_warm.y);
  let aGrad = abs(gradV_cool.x) + abs(gradV_cool.y);
  let membrane = abs(s.g - s.a) * (gGrad + aGrad);
  s.g = clamp(s.g - membrane * 0.04, 0.0, 1.0);
  s.a = clamp(s.a - membrane * 0.04, 0.0, 1.0);

  let md = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0));
  let hover = exp(-md * 18.0); let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  s.g += hover * (0.008 + held * (0.24 + audio.x * 0.12));
  s.a += hover * held * (0.17 + audio.z * 0.10);
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i]; let age = time - event.z;
    let liveMask = f32(age >= 0.0 && age < 1.8);
    let dist = length((uv - event.xy) * vec2<f32>(aspect, 1.0));
    clickEnergy += liveMask * exp(-max(age, 0.0) * 1.8) * exp(-abs(dist - max(age, 0.0) * (0.20 + audio.x * 0.05)) * 70.0);
  }
  s.g += clickEnergy * 0.22; s.a += clickEnergy * 0.14;
  s = clamp(s, vec4<f32>(0.0), vec4<f32>(1.0));
  textureStore(dataTextureA, p, s);

  // ── Idea 4 (part b): 3D wet-agar colony meniscus sheen & refraction ─
  let agarSlope = gradV_warm + gradV_cool;
  let agarNormal = normalize(vec3<f32>(-agarSlope * 5.2, 1.0));
  let lightDir = normalize(vec3<f32>(-0.42, -0.55, 0.72));
  let halfVec = normalize(lightDir + vec3<f32>(0.0, 0.0, 1.0));
  let meniscusSpec = pow(max(dot(agarNormal, halfVec), 0.0), 42.0) * smoothstep(0.04, 0.35, length(agarSlope));
  let refractUV = clamp(uv + agarNormal.xy * 0.009, vec2<f32>(0.0), vec2<f32>(1.0));
  let refractedSrc = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).rgb;

  let boundary = abs(s.r - s.g) + abs(s.b - s.a);
  let instability = clamp(length(ds) * 5.0 + clickEnergy, 0.0, 1.0);
  var hdr = s.r * vec3<f32>(0.08, 0.42, 1.35) + s.g * vec3<f32>(2.10, 0.20, 0.04)
          + s.b * vec3<f32>(0.05, 1.25, 0.40) + s.a * vec3<f32>(1.65, 0.70, 0.05);
  hdr += boundary * boundary * vec3<f32>(0.45, 0.12 + audio.y * 0.15, 0.55);
  hdr += membrane * vec3<f32>(0.85, 0.95, 0.55);
  hdr += vec3<f32>(1.15, 1.08, 0.96) * meniscusSpec * (0.85 + audio.z * 0.35);
  hdr = mix(refractedSrc, hdr, 0.72 + u.zoom_params.w * 0.20);
  let alpha = clamp(src.a * 0.20 + boundary * 0.55 + instability * 0.35 + max(s.g, s.a) * 0.45 + membrane * 0.4 + meniscusSpec * 0.25, 0.0, 1.0);
  let mapped = aces(max(hdr, vec3<f32>(0.0)));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let colonyRelief = clamp(max(s.g, s.a) * 0.45 + boundary * 0.45, 0.0, 1.0);
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha));
  textureStore(writeDepthTexture, p, vec4<f32>(clamp(mix(depth, 1.0 - colonyRelief * 0.7, alpha * 0.55), 0.0, 1.0), 0.0, 0.0, 0.0));
}
