// ═══════════════════════════════════════════════════════════════════
//  Liquid Fast
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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(gid.xy); let uv = vec2<f32>(gid.xy) / resolution; let time = u.config.x;
  let response = mix(0.45, 1.4, u.zoom_params.x); let turbulence = u.zoom_params.y;
  let rippleStrength = mix(0.002, 0.028, u.zoom_params.z); let highlightShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let ambient = vec2<f32>(sin(uv.y * (12.0 + turbulence * 18.0) + time * response), cos(uv.x * 14.0 - time * response * 1.2));
  var displacement = ambient * turbulence * 0.0025 * mix(1.0, 0.35, depth);
  var rippleEnergy = 0.0; let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age > 0.0 && age < 1.6) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0); let dist = max(length(delta), 0.0001);
      let dir = delta / dist; let life = 1.0 - smoothstep(0.0, 1.6, age);
      let wave = sin(dist * mix(35.0, 58.0, turbulence) - age * (12.0 + audio.x * 10.0));
      let energy = wave * exp(-dist * 11.0) * life;
      displacement += vec2<f32>(dir.x / aspect, dir.y) * energy * rippleStrength * (1.0 + audio.x * 0.8);
      rippleEnergy += abs(energy);
    }
  }
  let velocity = length(displacement); let direction = displacement / max(velocity, 0.0001);
  let motionTap = direction * min(velocity, 0.03) * (0.5 + response * 0.5);
  let uv0 = clamp(uv + displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let c0 = textureSampleLevel(readTexture, u_sampler, uv0, 0.0);
  let c1 = textureSampleLevel(readTexture, u_sampler, clamp(uv0 - motionTap, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let c2 = textureSampleLevel(readTexture, u_sampler, clamp(uv0 - motionTap * 2.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let blurred = c0 * 0.56 + c1 * 0.29 + c2 * 0.15;
  let edgeLight = clamp(rippleEnergy * 0.18 + velocity * 25.0, 0.0, 1.0);
  let tint = mix(vec3<f32>(0.0, 0.1, 0.16), vec3<f32>(0.2, 0.55, 1.0), highlightShift);
  let rgb = blurred.rgb + tint * edgeLight * (0.18 + audio.z * 0.55);
  let alpha = clamp(blurred.a * (0.9 - velocity * 2.0) + edgeLight * 0.18, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);
  textureStore(writeTexture, coord, outputColor); textureStore(dataTextureA, coord, outputColor);
  let displacedDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv0, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(displacedDepth, 0.0, 0.0, 0.0));
}
