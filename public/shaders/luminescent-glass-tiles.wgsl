// ═══════════════════════════════════════════════════════════════════
//  Luminescent Glass Tiles — Luminance-Warped Glass Matrix
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba,
//            fresnel, beer-lambert, luminescent-glow, semantic-alpha, ACES
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,  // x=GridDensity, y=Refraction, z=MouseRadius, w=MouseChaos
  ripples: array<vec4<f32>, 50>,
};

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let pixel = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let rawMouse = u.zoom_config.yz;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  let aspect = resolution.x / max(resolution.y, 1.0);
  let time = u.config.x;

  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

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
    let stiffness = 45.0;
    let damping = 13.416; // 2 * sqrt(45)
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
  let density = max(u.zoom_params.x * 50.0 * (1.0 + bass * 0.15), 1.0);
  let refractStr = u.zoom_params.y * 0.5 * (1.0 + mids * 0.25);
  let radius = max(u.zoom_params.z, 0.01);
  let turbulence = u.zoom_params.w * (1.0 + treble * 0.35);
  let glassDensity = 1.0 + turbulence * 1.5;

  let gridUV = uv * vec2<f32>(density * aspect, density);
  let cellID = floor(gridUV);
  let cellUV = fract(gridUV);

  let cellCenterGrid = cellID + vec2<f32>(0.5);
  let cellCenterUV = cellCenterGrid / vec2<f32>(density * aspect, density);

  let centerColor = textureSampleLevel(readTexture, u_sampler, cellCenterUV, 0.0);
  let luma = dot(centerColor.rgb, vec3<f32>(0.299, 0.587, 0.114));

  let diff = cellCenterUV - mouse;
  let dist = length(vec2<f32>(diff.x * aspect, diff.y));
  let mouseFactor = smoothstep(radius * (1.0 + held * 0.4), 0.0, dist);

  // Click ripple shocks
  let rippleCount = min(u32(u.config.y), 50u);
  var rippleTwist = 0.0;
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age >= 0.0 && age < 2.0) {
      let rDist = length((cellCenterUV - r.xy) * vec2<f32>(aspect, 1.0));
      let wave = sin((rDist - age * 0.5) * 30.0) * exp(-rDist * 3.5) * exp(-age * 1.4);
      rippleTwist += wave * 0.4;
    }
  }

  var distUV = cellUV - 0.5;
  var scale = 1.0 - (luma * refractStr * 2.0);

  if (mouseFactor > 0.0 || abs(rippleTwist) > 0.01) {
    scale = scale * (1.0 - mouseFactor * turbulence);
    let angle = (mouseFactor * turbulence + rippleTwist * 0.3) * 3.14159265;
    let s = sin(angle);
    let c = cos(angle);
    distUV = vec2<f32>(distUV.x * c - distUV.y * s, distUV.x * s + distUV.y * c);
  }

  distUV = distUV * scale + 0.5;

  let finalUV = clamp(
    (cellID + distUV) / vec2<f32>(density * aspect, density),
    vec2<f32>(0.001),
    vec2<f32>(0.999)
  );

  let border = max(abs(distUV.x - 0.5), abs(distUV.y - 0.5));
  let distortionVec = (finalUV - uv) * density;
  let normal = normalize(vec3<f32>(-distortionVec * 2.0, 1.0));
  let viewDir = vec3<f32>(0.0, 0.0, 1.0);

  let cos_theta = max(dot(viewDir, normal), 0.0);
  let R0 = 0.04;
  let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);

  let tileThickness = 0.05 + (1.0 - scale) * 0.1;
  let edgeThickness = smoothstep(0.4, 0.5, border) * 0.05;
  let thickness = tileThickness + edgeThickness;

  let baseGlassColor = vec3<f32>(0.92, 0.96, 1.0);
  let luminescentTint = vec3<f32>(0.8 + luma * 0.4, 0.9 + luma * 0.2, 1.0);
  let glassColor = mix(baseGlassColor, luminescentTint, luma * 0.5) + vec3<f32>(0.03 * bass, 0.05 * mids, 0.08 * treble);

  let absorption = exp(-(vec3<f32>(1.0) - glassColor) * thickness * glassDensity);
  var transmission = (1.0 - fresnel) * dot(absorption, vec3<f32>(0.3333));
  transmission = mix(transmission * 0.6, transmission, 1.0 - smoothstep(0.45, 0.48, border));

  var src = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0).rgb;

  if (border > 0.45) {
    src = src * 0.5;
    transmission = transmission * 0.5;
  }

  var color = src * glassColor;
  let glow = luma * (0.2 + bass * 0.12) * mouseFactor;
  color += vec3<f32>(glow) + vec3<f32>(0.3, 0.6, 1.0) * abs(rippleTwist) * 0.3;

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, pixel, 0).rgb;
  color = mix(color, prevC, 0.07);

  let finalRGB = aces(color);

  let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, finalUV, 0.0).r + fresnel * 0.03, 0.0, 1.0);
  let alpha = clamp(transmission + glow * 0.5 + mouseFactor * 0.15, 0.1, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, pixel, finalPixel);
  textureStore(dataTextureA, pixel, finalPixel);
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
