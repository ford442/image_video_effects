// ═══════════════════════════════════════════════════════════════════
//  Glass Shatter Morph
//  Category: advanced-hybrid
//  Features: audio-reactive, mouse-driven, click-reactive, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-06
//  Ideas: sub-cellular micro-fracture spiderweb cracks; grazing prismatic TIR facet glints; photoelastic stress birefringence fringes
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

struct VoronoiResult {
  dist: f32,
  id: vec2<f32>,
  center: vec2<f32>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn voronoi(uv: vec2<f32>, scale: f32) -> VoronoiResult {
  let g = floor(uv * scale);
  let f = fract(uv * scale);
  var res = VoronoiResult(8.0, vec2<f32>(0.0), vec2<f32>(0.0));

  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let lattice = vec2<f32>(f32(x), f32(y));
      let offset = hash22(g + lattice);
      let p = lattice + offset - f;
      let d = dot(p, p);

      if (d < res.dist) {
        res.dist = d;
        res.id = g + lattice;
        res.center = (g + lattice + offset) / scale;
      }
    }
  }

  res.dist = sqrt(res.dist);
  return res;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Sliders: exact parameter contracts
  let shardScaleParam = u.zoom_params.x; // 0..1, def 0.5
  let displaceParam = u.zoom_params.y;   // 0..1, def 0.5
  let morphParam = u.zoom_params.z;      // 0..1, def 0.5
  let edgeWidthParam = u.zoom_params.w;  // 0..1, def 0.3

  let shardScale = (shardScaleParam * 18.0 + 3.5) * (1.0 + bass * 0.35);
  let displaceStr = displaceParam * 0.45 * (1.0 + mids * 0.45);
  let morphBlend = clamp(morphParam + treble * 0.2, 0.0, 1.0);
  let edgeWidth = edgeWidthParam * 0.08 + 0.005;

  // Critically damped spring cursor in extraBuffer[133..138]
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.1);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 36.0;
    let damping = 12.0;
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel = sVel + accel * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Voronoi shards with aspect compensation
  let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
  let v = voronoi(aspectUV, shardScale);

  // Calculate mouse displacement on shard center
  let mouseAspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let mouseVec = v.center - mouseAspect;
  let mouseDist = length(mouseVec);

  var shatterOffset = vec2<f32>(0.0);
  if (mouseDist < 0.55 && mouseDist > 0.001) {
    let force = (1.0 - smoothstep(0.0, 0.55, mouseDist)) * displaceStr * (0.6 + held * 0.4);
    shatterOffset = normalize(mouseVec) * force;
  }

  // Click shockwave displacement
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleForce = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age < 0.0 || age > 2.0) { continue; }
    let rDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
    let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
    let rDir = normalize(uv - ripple.xy + vec2<f32>(0.0001));
    rippleForce += rDir * wave * 0.08;
  }

  let randTilt = (hash22(v.id) - 0.5) * 0.03 * displaceStr;
  let finalUV = clamp(uv - vec2<f32>(shatterOffset.x / aspect, shatterOffset.y) - randTilt - rippleForce, vec2<f32>(0.0), vec2<f32>(1.0));

  // Morphological erosion/dilation on shard boundaries
  let pixelSize = 1.0 / resolution;
  let kRadius = clamp(i32(edgeWidth * resolution.y * 0.15), 1, 4);

  var minVal = vec3<f32>(999.0);
  var maxVal = vec3<f32>(-999.0);

  for (var dy = -kRadius; dy <= kRadius; dy = dy + 1) {
    for (var dx = -kRadius; dx <= kRadius; dx = dx + 1) {
      let sUV = clamp(finalUV + vec2<f32>(f32(dx), f32(dy)) * pixelSize, vec2<f32>(0.0), vec2<f32>(1.0));
      let sample = textureSampleLevel(readTexture, u_sampler, sUV, 0.0).rgb;
      minVal = min(minVal, sample);
      maxVal = max(maxVal, sample);
    }
  }

  let erosion = minVal;
  let dilation = maxVal;
  let morphGradient = dilation - erosion;
  let morphRGB = mix(erosion, dilation, morphBlend);

  // Shard facet normal and Fresnel reflection
  let shardTilt = normalize(shatterOffset + randTilt * 10.0 + rippleForce * 5.0 + vec2<f32>(0.001));
  let normal = normalize(vec3<f32>(shardTilt * 2.0, 1.0));
  let cosTheta = clamp(normal.z, 0.0, 1.0);
  let R0 = 0.045;
  let fresnel = R0 + (1.0 - R0) * pow(1.0 - cosTheta, 5.0);

  // Chromatic refraction per shard
  let aberration = edgeWidth * 0.35 * (1.0 + treble * 0.5);
  let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

  let glassTint = vec3<f32>(0.94, 0.98, 0.96);
  var color = vec3<f32>(r, g, b) * glassTint;

  // ─── Native Idea 1: Sub-Cellular Micro-Fracture Spiderweb Cracks ───
  let subUv = aspectUV * shardScale * 2.5;
  let subCell = floor(subUv);
  let subFract = fract(subUv) - vec2<f32>(0.5);
  let crackNoise = hash22(subCell + v.id * 13.0);
  let crackDir = normalize(crackNoise - vec2<f32>(0.5) + vec2<f32>(1e-4));
  let crackLine = abs(dot(subFract, crackDir));
  let microCracks = smoothstep(0.05, 0.008, crackLine) * smoothstep(0.05, 0.25, v.dist) * (0.35 + displaceParam * 0.45);
  color = mix(color, vec3<f32>(0.98, 1.0, 1.0), microCracks * 0.6);

  // Shard crack edge proximity
  let edgeProx = smoothstep(0.0, 0.12, v.dist) * (1.0 - smoothstep(0.12, 0.3, v.dist));
  color = mix(color, morphRGB + morphGradient * 0.35, edgeProx * 0.5);

  // Facet specular glint
  let lightDir = normalize(vec2<f32>(0.6, -0.6));
  let specular = pow(max(dot(shardTilt, lightDir), 0.0), 12.0) * fresnel * 2.0;

  // ─── Native Idea 2: Grazing Prismatic TIR Facet Glints ───
  let tirAngle = acos(clamp(normal.z, 0.0, 1.0));
  let tirCondition = smoothstep(0.65, 0.95, tirAngle / 1.570796);
  let tirSpectrum = vec3<f32>(
    sin(tirAngle * 7.0) * 0.5 + 0.5,
    sin(tirAngle * 7.0 + 2.094) * 0.5 + 0.5,
    sin(tirAngle * 7.0 + 4.189) * 0.5 + 0.5
  );
  let tirGlint = tirSpectrum * tirCondition * (specular * 1.5 + 0.2) * (1.0 + treble * 0.6);
  color += tirGlint;
  color += vec3<f32>(1.0, 0.98, 0.95) * specular;

  // ─── Native Idea 3: Photoelastic Stress Birefringence Fringes ───
  let stress = (edgeProx + microCracks * 0.9) * (displaceStr * 3.5 + bass * 0.65);
  let retardance = stress * 16.0 - time * 2.2;
  let isochromaticFringe = vec3<f32>(
    sin(retardance) * 0.5 + 0.5,
    sin(retardance + 2.094) * 0.5 + 0.5,
    sin(retardance + 4.189) * 0.5 + 0.5
  );
  color = mix(color, isochromaticFringe * 1.25, clamp(stress * 0.38, 0.0, 0.7));

  // Exact dataTextureC shard trail persistence
  let prev = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prev, 0.08 + held * 0.06);

  let finalRGB = aces(color);

  // Semantic transmittance alpha
  let transmission = (1.0 - fresnel) * 0.85;
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let alpha = clamp(mix(srcA, transmission + edgeProx * 0.3 + microCracks * 0.2, 0.8) + specular * 0.2, 0.25, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
