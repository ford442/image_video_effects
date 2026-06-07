// ═══════════════════════════════════════════════════════════════════
//  Pixel Repel v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, curl-noise, spectral-ca
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
  var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let n = dot(i, vec2<f32>(127.1, 311.7));
  return mix(mix(fract(sin(n) * 43758.5453), fract(sin(n + 127.1) * 43758.5453), u.x),
             mix(fract(sin(n + 311.7) * 43758.5453), fract(sin(n + 438.8) * 43758.5453), u.x), u.y);
}

fn curl2(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n0 = noise2(p + t * 0.3);
  return vec2<f32>(-(noise2(p + vec2<f32>(0.0, eps) + t * 0.3) - n0) / eps,
                    (noise2(p + vec2<f32>(eps, 0.0) + t * 0.3) - n0) / eps);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51); let b = vec3<f32>(0.03);
  let c = vec3<f32>(2.43); let d = vec3<f32>(0.59); let e = vec3<f32>(0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sellipse(d: vec2<f32>, r: f32, e: f32) -> f32 {
  let p = pow(abs(d.x), e) + pow(abs(d.y), e);
  return 1.0 - smoothstep(0.0, pow(r, e), p);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let res = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (global_id.x >= res.x || global_id.y >= res.y) { return; }

  let uv = vec2<f32>(global_id.xy) / vec2<f32>(res);
  let aspect = u.config.z / u.config.w;
  let mouse = u.zoom_config.yz;
  let time = u.config.x;
  let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;

  let radius = max(u.zoom_params.x * 0.5, 0.05);
  let strength = u.zoom_params.y;
  let aberration = u.zoom_params.z * 0.25;
  let smoothing = u.zoom_params.w;

  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  var disp = vec2<f32>(0.0);
  for (var i: u32 = 0u; i < 4u; i = i + 1u) {
    let fi = f32(i);
    let angle = time * (0.4 + fi * 0.15) + fi * 1.570796;
    let off = vec2<f32>(cos(angle), sin(angle)) * radius * (0.6 + fi * 0.25);
    let sd = (uv - mouse - off) * vec2<f32>(aspect, 1.0);
    let liss = vec2<f32>(sin(time * (1.1 + fi * 0.3) + fi) * 0.08, cos(time * (0.9 + fi * 0.2) + fi) * 0.06);
    let mask = sellipse(sd + liss, radius * (0.5 - fi * 0.08), 2.4 + fi * 0.4);
    let distL = length(sd + liss);
    let dir = select(vec2<f32>(0.0), (sd + liss) / max(distL, 0.0001), distL > 0.0001);
    disp = disp + dir * (1.0 - smoothstep(0.0, radius, distL)) * mask * strength * 0.12 * (1.0 + bass * 0.6);
  }

  disp = disp + curl2(uv * 6.0 + mouse * 3.0, time * 0.5) * mids * 0.06 * (1.0 + bass);
  let dUV = (uv - mouse) * vec2<f32>(aspect, 1.0);
  let mainFalloff = 1.0 - smoothstep(radius * 0.3, radius * (1.0 - smoothing * 0.4), length(dUV));
  let mouseVel = vec2<f32>(cos(time * 2.3), sin(time * 1.7)) * 0.02;
  disp = disp + mouseVel * mainFalloff * strength * (1.0 + bass);
  disp = disp * (1.0 + (1.0 - depth) * 0.5);

  let effStr = clamp(length(disp) * 15.0, 0.0, 1.0);
  if (effStr < 0.003) {
    let outA = mix(0.3 + depth * 0.4, c0.a, c0.a);
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(c0.rgb, outA));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(c0.rgb, outA));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    return;
  }

  var caRGB = vec3<f32>(0.0);
  for (var i: i32 = 0; i < 7; i = i + 1) {
    let fi = (f32(i) - 3.0) / 3.0;
    let samp = textureSampleLevel(readTexture, u_sampler, clamp(uv - disp * (1.0 + fi * aberration * effStr), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    caRGB = caRGB + samp.rgb * (1.0 - abs(fi));
  }
  caRGB = caRGB * 0.25;

  let lum = dot(c0.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let fresnel = pow(1.0 - effStr, 3.0);
  let rim = vec3<f32>(1.0, 0.85, 0.5) * fresnel * treble * 2.0;
  let spectral = mix(c0.rgb, caRGB, aberration * c0.a * 2.0);
  let boosted = spectral + rim + vec3<f32>(lum * 0.08 * mids);
  let tone = aces_tonemap(boosted * (1.0 + bass * 0.3));
  let alpha = mix(0.35 + depth * 0.35, 0.9, effStr);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(tone, alpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(tone, alpha));
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
