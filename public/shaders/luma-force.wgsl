// ═══════════════════════════════════════════════════════════════════
//  Luma Force v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Strategy: Luma-gradient particle advection + curl noise + spectral CA
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: aces_tone_map ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 2D curl noise: returns divergence-free velocity field
fn curl_noise(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let s = p * 3.0 + t * 0.3;
  let n0 = hash12(s);
  let nx = hash12(s + vec2<f32>(eps, 0.0));
  let ny = hash12(s + vec2<f32>(0.0, eps));
  let dndx = (nx - n0) / eps;
  let dndy = (ny - n0) / eps;
  return vec2<f32>(dndy, -dndx);
}

// Sample luma at UV
fn sample_luma(uv: vec2<f32>) -> f32 {
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  return dot(c.rgb, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let forceMag = u.zoom_params.x * (1.0 + bass * 0.5);
  let radius = u.zoom_params.y;
  let curlWeight = u.zoom_params.z;
  let lumaWeight = u.zoom_params.w;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthParallax = mix(0.5, 1.5, depth);

  // Compute luma gradient from neighbors
  let px = vec2<f32>(1.0 / resolution.x, 0.0);
  let py = vec2<f32>(0.0, 1.0 / resolution.y);
  let lC = sample_luma(uv);
  let lR = sample_luma(uv + px);
  let lL = sample_luma(uv - px);
  let lU = sample_luma(uv + py);
  let lD = sample_luma(uv - py);
  let grad = vec2<f32>(lR - lL, lU - lD) * 0.5;
  let lumaContrast = abs(lR - lL) + abs(lU - lD);

  // Physics: bright repels, dark attracts along gradient
  let repelDir = -normalize(grad + vec2<f32>(0.0001));
  let lumaForce = repelDir * forceMag * lumaWeight * (lC - 0.3) * 0.15 * depthParallax;

  // Mouse vortex force
  let aspect = resolution.x / resolution.y;
  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let mouseAspect = vec2<f32>(mouse.x * aspect, mouse.y);
  let toMouse = uvAspect - mouseAspect;
  let distMouse = length(toMouse);
  let vortexFalloff = smoothstep(radius, 0.0, distMouse);
  let vortexDir = vec2<f32>(-toMouse.y, toMouse.x);
  let vortexForce = normalize(vortexDir + vec2<f32>(0.0001)) * vortexFalloff * forceMag * 0.08;

  // Curl noise advection (divergence-free)
  let curl = curl_noise(uv, time) * curlWeight * 0.02 * (1.0 + treble * 0.5);

  // Total displacement
  let totalDisp = lumaForce + vec2<f32>(vortexForce.x / aspect, vortexForce.y) + curl;
  let velMag = length(totalDisp);

  // Spectral chromatic aberration based on velocity
  let chromaShift = velMag * 0.03;
  let rUV = clamp(uv + totalDisp + vec2<f32>(chromaShift / aspect, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let gUV = clamp(uv + totalDisp, vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv + totalDisp - vec2<f32>(chromaShift / aspect, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let colR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
  let colG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0);
  let colB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);
  var advected = vec3<f32>(colR.r, colG.g, colB.b);

  // HDR glow on high-velocity regions
  let glow = vec3<f32>(0.6 + mids * 0.3, 0.5 + treble * 0.3, 0.8) * velMag * velMag * 3.0 * (1.0 + bass * 0.4);
  advected = advected + glow;

  let finalRGB = aces_tonemap(advected);

  // Alpha = velocity magnitude × luma_contrast × depth
  let alpha = clamp(velMag * 4.0 * lumaContrast * depth + 0.15, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(totalDisp * 10.0, velMag * 10.0, alpha));
}
