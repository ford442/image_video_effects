// ═══════════════════════════════════════════════════════════════════
//  Magnetic Edge v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, canny-edges,
//            magnetic-dipole, chromatic-aberration, aces-tone-map
//  Complexity: High
//  Upgraded: 2026-05-30
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

fn luminance(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51);
  let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43);
  let d = vec3<f32>(0.59);
  let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(vec2<f32>(n, n * 1.618));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let mouse = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let time = u.config.x;

  let pullStrength = (0.05 + u.zoom_params.x * 0.25) * (1.0 + bass * 0.4);
  let radius = 0.25 + u.zoom_params.y * 0.55;
  let edgeLow = 0.04 + u.zoom_params.z * 0.18;
  let edgeHigh = edgeLow * 2.5;
  let glowAmt = u.zoom_params.w * (1.0 + mids * 0.6);

  let texel = 1.0 / resolution;
  let c  = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let cl = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(-texel.x, 0.0), 0.0).rgb;
  let cr = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>( texel.x, 0.0), 0.0).rgb;
  let ct = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, -texel.y), 0.0).rgb;
  let cb = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0,  texel.y), 0.0).rgb;

  let dX = luminance(cr) - luminance(cl);
  let dY = luminance(cb) - luminance(ct);
  let gradMag = sqrt(dX * dX + dY * dY);

  let edgeStrong = select(0.0, 1.0, gradMag >= edgeHigh);
  let edgeWeak   = select(0.0, 1.0, gradMag >= edgeLow && gradMag < edgeHigh);
  let edgeConf = clamp(edgeStrong + edgeWeak * 0.5, 0.0, 1.0);

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let parallax = depth * 0.04 * (1.0 + bass * 0.2);

  let aspect = resolution.x / resolution.y;
  let dVec = mouse - uv;
  let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
  let influence = smoothstep(radius, 0.0, dist);
  let clickBoost = select(1.0, 2.5, mouseDown);

  let fieldDir = normalize(dVec + 1e-5);
  let fieldAlign = abs(dX * fieldDir.x + dY * fieldDir.y) / max(gradMag, 1e-4);

  let displacement = fieldDir * influence * pullStrength * clickBoost * edgeConf * (1.0 + bass * 0.3);
  let dispUV = clamp(uv + displacement + vec2<f32>(parallax * dX, parallax * dY), vec2<f32>(0.0), vec2<f32>(1.0));

  let caOffset = glowAmt * 0.008 * influence * edgeConf;
  let uvR = clamp(dispUV + vec2<f32>( caOffset, -caOffset * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(dispUV + vec2<f32>(0.0,  caOffset * 0.3), vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(dispUV + vec2<f32>(-caOffset, -caOffset * 0.5), vec2<f32>(0.0), vec2<f32>(1.0));

  var colR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
  var colG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
  var colB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

  let neon = vec3<f32>(0.12, 0.85, 1.0) * edgeConf * influence * glowAmt * (1.0 + bass * 0.5);
  let accum = hash22(uv * resolution + time).x * edgeConf * influence * 0.08;

  var finalColor = vec3<f32>(colR, colG, colB);
  finalColor = finalColor + neon + vec3<f32>(accum);
  finalColor = aces_tonemap(finalColor * (1.0 + glowAmt * 0.4));

  let alpha = clamp(edgeConf * fieldAlign * depth * (0.6 + influence * 0.4) + glowAmt * influence * 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(finalColor, alpha));
}
