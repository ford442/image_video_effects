// ═══════════════════════════════════════════════════════════════════
//  Liquid RGB
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-07-21
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
struct Uniforms { config: vec4<f32>, zoom_config: vec4<f32>, zoom_params: vec4<f32>, ripples: array<vec4<f32>, 50>, };

fn fresnel(c: f32) -> f32 { return 0.025 + 0.975 * pow(1.0 - clamp(c, 0.0, 1.0), 5.0); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(gid.xy); let uv = vec2<f32>(gid.xy) / resolution; let time = u.config.x;
  let viscosity = mix(0.15, 0.95, u.zoom_params.x); let turbulence = u.zoom_params.y;
  let rippleStrength = mix(0.002, 0.032, u.zoom_params.z); let separation = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let aspect = resolution.x / max(resolution.y, 1.0);
  var displacement = vec2<f32>(sin(uv.y * (10.0 + turbulence * 20.0) + time * 0.5), cos(uv.x * (12.0 + turbulence * 16.0) - time * 0.45));
  displacement *= turbulence * 0.0025 * mix(1.0, 0.3, depth) * mix(1.2, 0.55, viscosity);
  var caustic = 0.0; let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age > 0.0 && age < 3.0) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0); let dist = max(length(delta), 0.0001);
      let dir = delta / dist; let life = 1.0 - smoothstep(0.0, 3.0, age);
      let wave = sin(dist * 30.0 - age * (4.0 + audio.x * 5.0)); let envelope = exp(-dist * 8.0) * life;
      displacement += vec2<f32>(dir.x / aspect, dir.y) * wave * envelope * rippleStrength * (1.0 + audio.x * 0.65);
      caustic += pow(max(wave, 0.0), 6.0) * envelope;
    }
  }
  let magnitude = length(displacement); let split = displacement * (1.0 + separation * 5.0 + audio.y * 1.5);
  let uvR = clamp(uv + displacement + split, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvG = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let uvB = clamp(uv + displacement - split, vec2<f32>(0.0), vec2<f32>(1.0));
  let cR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0); let cG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0); let cB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
  let thickness = magnitude * (18.0 + viscosity * 30.0);
  let absorption = exp(-thickness * vec3<f32>(0.75, 1.0, 1.3));
  var rgb = vec3<f32>(cR.r, cG.g, cB.b) * absorption;
  let normal = normalize(vec3<f32>(-displacement * 28.0, 1.0)); let rim = fresnel(normal.z);
  rgb += vec3<f32>(1.0, 0.35 + separation * 0.35, 0.75) * caustic * (0.08 + audio.z * 0.25) + rim * vec3<f32>(0.05, 0.1, 0.16);
  let sourceAlpha = max(cR.a, max(cG.a, cB.a)); let energy = clamp(caustic * 0.2 + magnitude * 22.0, 0.0, 1.0);
  let alpha = clamp(sourceAlpha * mix(0.78, 0.98, viscosity) + energy * 0.2, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);
  textureStore(writeTexture, coord, outputColor); textureStore(dataTextureA, coord, outputColor);
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uvG, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
