// ═══════════════════════════════════════════════════════════════════
//  IFS Attractor Glass — Iterated Function System + Chromatic Glass
//  Category: distortion
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            fractal-attractor, chromatic-aberration, semantic-alpha, ACES
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
  zoom_params: vec4<f32>,  // x=Contraction, y=Rotation, z=Refraction, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

fn ifsAffine(p: vec2<f32>, angle: f32, scale: f32, tx: f32, ty: f32) -> vec2<f32> {
  let c = cos(angle);
  let s = sin(angle);
  return vec2<f32>(scale * (c * p.x - s * p.y) + tx, scale * (s * p.x + c * p.y) + ty);
}

fn ifsAttractorDensity(p: vec2<f32>, contraction: f32, rotation: f32) -> f32 {
  let s  = contraction * 0.55;
  let s2 = contraction * 0.45;
  let r1 = rotation;
  let r2 = rotation + 2.094395;
  let r3 = rotation - 2.094395;

  var q = p;
  var density = 0.0;
  for (var i = 0; i < 8; i = i + 1) {
    let q1 = ifsAffine(q, r1, 1.0 / s,  0.0, 0.5);
    let q2 = ifsAffine(q, r2, 1.0 / s2, 0.5, -0.4);
    let q3 = ifsAffine(q, r3, 1.0 / s2,-0.5, -0.4);
    let q4 = (q - vec2<f32>(0.0, -0.3)) * (1.0 / (s * 0.3));

    let d1 = length(q1);
    let d2 = length(q2);
    let d3 = length(q3);
    let d4 = length(q4);

    if (d1 <= d2 && d1 <= d3 && d1 <= d4) { q = q1; }
    else if (d2 <= d3 && d2 <= d4)        { q = q2; }
    else if (d3 <= d4)                     { q = q3; }
    else                                   { q = q4; }

    density += exp(-length(q) * 3.0);
  }
  return clamp(density / 8.0, 0.0, 1.0);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(global_id.xy);
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
  let mousePinch = exp(-dot((uv - mouse) * vec2<f32>(aspect, 1.0), (uv - mouse) * vec2<f32>(aspect, 1.0)) * 12.0) * held;
  let contraction = mix(0.4, 0.75, u.zoom_params.x) * mix(1.0, 0.82, mousePinch * 0.5);
  let rotation = u.zoom_params.y * 6.2831853 + time * 0.2;
  let refrStr = mix(0.01, 0.12, u.zoom_params.z) * (1.0 + bass * 0.4);
  let aberration = mix(0.005, 0.06, u.zoom_params.w) * (1.0 + treble * 0.5);

  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 1.5;

  let d0 = ifsAttractorDensity(p, contraction, rotation);
  let dx = ifsAttractorDensity(p + vec2<f32>(0.008, 0.0), contraction, rotation);
  let dy = ifsAttractorDensity(p + vec2<f32>(0.0, 0.008), contraction, rotation);
  let grad = vec2<f32>(dx - d0, dy - d0) * refrStr;

  let branchRunner = pow(max(0.0, sin(atan2(grad.y, grad.x) * 6.0 - time * (14.0 + mids * 6.0))), 12.0);
  let attractorRunner = pow(max(0.0, sin(d0 * 24.0 - time * (18.0 + bass * 8.0))), 14.0);

  var clickRing = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.0) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
      clickRing += smoothstep(0.02, 0.0, abs(length(delta) - age * 0.45)) * exp(-age * 1.6);
    }
  }

  let gradBoost = grad * (1.0 + branchRunner * 0.25 + clickRing * 0.3);

  // Live chromatic dispersion using aberration parameter
  let uvR = clamp(uv + gradBoost * (1.0 + aberration * 15.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv + gradBoost, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + gradBoost * (1.0 - aberration * 15.0), vec2<f32>(0.0), vec2<f32>(1.0));

  let sR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0);
  let sG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0);
  let sB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
  var color = vec3<f32>(sR.r, sG.g, sB.b);

  // Exact dataTextureC persistence
  let prevC = textureLoad(dataTextureC, coord, 0).rgb;
  color = mix(color, prevC, 0.08);

  let glow = d0 * d0 * 0.6 * (1.0 + attractorRunner * 0.35);
  let angle = atan2(grad.y, grad.x) / 6.2831853 + 0.5 + treble * 0.15;
  let iridR = 0.5 + 0.5 * sin(angle * 6.2831853 + 0.0);
  let iridG = 0.5 + 0.5 * sin(angle * 6.2831853 + 2.094395);
  let iridB = 0.5 + 0.5 * sin(angle * 6.2831853 + 4.18879);
  color = mix(color, vec3<f32>(iridR, iridG, iridB), glow * 0.4);

  color += vec3<f32>(0.9, 0.95, 1.0) * smoothstep(0.7, 1.0, d0) * 0.5;
  color += vec3<f32>(0.4, 0.6, 1.0) * clickRing * 0.25;

  let finalRGB = aces(color);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let luminance = dot(finalRGB, vec3<f32>(0.299, 0.587, 0.114));
  let alpha = clamp(d0 * 0.5 + length(gradBoost) * 5.0 + glow * 0.5 + luminance * 0.2 + mousePinch * 0.2, 0.2, 1.0);
  let finalPixel = vec4<f32>(finalRGB, alpha);

  textureStore(writeTexture, coord, finalPixel);
  textureStore(dataTextureA, coord, finalPixel);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
