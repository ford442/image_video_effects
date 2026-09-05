// ═══════════════════════════════════════════════════════════════════
//  Voronoi Faceted Glass — Prismatic Cellular Refraction & Highlights
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba,
//            voronoi-cells, faceted-refraction, semantic-alpha, ACES
//  Complexity: High
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Density, y=Refraction, z=Shimmer, w=EdgeSoftness
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
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

  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);

  // Critically damped spring cursor in extraBuffer[133..138]
  let isWriter = (global_id.x == 0u && global_id.y == 0u);
  let hasState = (arrayLength(&extraBuffer) > 138u);

  var mouse = rawMouse;
  if (hasState && extraBuffer[138] > 0.5) {
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  if (isWriter && hasState) {
    let lastTime = extraBuffer[137];
    let dt = clamp(time - lastTime, 0.0, 0.05);
    var sPos = mouse;
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] < 0.5) {
      sPos = rawMouse;
      sVel = vec2<f32>(0.0);
    }
    let stiffness = 42.0;
    let damping = 12.96; // 2 * sqrt(42)
    let accel = (rawMouse - sPos) * stiffness - sVel * damping;
    sVel += accel * dt;
    sPos += sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
  }

  // Exact parameter contracts
  let density = 8.0 + u.zoom_params.x * 28.0 * (1.0 + bass * 0.25);
  let refraction = 0.015 + u.zoom_params.y * 0.08 * (1.0 + mids * 0.3);
  let shimmer = u.zoom_params.z;
  let edgeSoftness = u.zoom_params.w;

  let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
  let gridUV = uvCorrected * density;
  let gridIndex = floor(gridUV);
  let gridFract = fract(gridUV);

  var minDist = 10.0;
  var secondMinDist = 10.0;
  var cellCenter = vec2<f32>(0.0);
  var cellId = vec2<f32>(0.0);

  let mousePosCorrected = vec2<f32>(mouse.x * aspect, mouse.y);

  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let neighbor = vec2<f32>(f32(x), f32(y));
      let p = gridIndex + neighbor;
      var point = hash22(p);
      point = 0.5 + 0.5 * sin(time * 0.5 + 6.2831853 * point);

      let worldPoint = (p + point) / density;
      let distToMouse = distance(worldPoint, mousePosCorrected);

      if (distToMouse < 0.5) {
        let pushVec = worldPoint - mousePosCorrected;
        let pushLen = max(length(pushVec), 0.0001);
        let push = (pushVec / pushLen) * (0.5 - distToMouse) * (0.2 + 0.25 * treble + held * 0.2);
        point += push * (0.35 + shimmer * 0.35);
      }

      let diff = neighbor + point - gridFract;
      let dist = length(diff);

      if (dist < minDist) {
        secondMinDist = minDist;
        minDist = dist;
        cellId = p;
        cellCenter = (p + point) / density;
      } else if (dist < secondMinDist) {
        secondMinDist = dist;
      }
    }
  }

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleDistort = vec2<f32>(0.0);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.6) * 35.0) * exp(-rDist * 4.0) * exp(-age * 1.5);
      let rDir = normalize(uv - r.xy + vec2<f32>(0.0001));
      rippleDistort += rDir * wave * 0.03;
    }
  }

  let mouseHighlight = 1.0 - smoothstep(0.08, 0.4, distance(uv, mouse));
  var sampleUV = vec2<f32>(cellCenter.x / aspect, cellCenter.y);
  sampleUV = clamp(
    mix(sampleUV, uv + (sampleUV - uv) * refraction + rippleDistort, 0.6 + mids * 0.2),
    vec2<f32>(0.001),
    vec2<f32>(0.999)
  );

  let sampled = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

  let shade = 1.0 - smoothstep(0.25 + edgeSoftness * 0.15, 0.6, minDist);
  let facetEdge = smoothstep(0.01, 0.08, secondMinDist - minDist);

  let spectral = vec3<f32>(0.05 + treble * 0.15, 0.08 + mids * 0.1, 0.15 + bass * 0.12);
  var color = sampled * (0.82 + 0.22 * shade) * facetEdge + spectral * (mouseHighlight * 0.4 + (1.0 - shade) * 0.15);

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prevC, 0.08);

  let finalRGB = aces(color);
  let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r + shade * 0.04, 0.0, 1.0);
  let finalAlpha = clamp(0.28 + shade * 0.25 + mouseHighlight * 0.2 + bass * 0.08 + held * 0.1, 0.18, 0.95);
  let finalPixel = vec4<f32>(finalRGB, finalAlpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
