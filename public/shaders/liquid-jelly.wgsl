// ═══════════════════════════════════════════════════════════════════
//  Liquid Jelly
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, depth-aware, temporal, upgraded-rgba
//  Complexity: High
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

fn fresnel(c: f32) -> f32 { return 0.04 + 0.96 * pow(1.0 - clamp(c, 0.0, 1.0), 5.0); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(gid.xy); let uv = vec2<f32>(gid.xy) / resolution; let time = u.config.x;
  let damping = mix(1.2, 4.5, u.zoom_params.x); let elasticity = mix(3.0, 12.0, u.zoom_params.y);
  let wobbleStrength = mix(0.004, 0.065, u.zoom_params.z); let tintShift = u.zoom_params.w;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
  let centerDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let foreground = 1.0 - smoothstep(0.75, 0.96, centerDepth); let aspect = resolution.x / max(resolution.y, 1.0);
  var displacement = vec2<f32>(0.0); var wobbleEnergy = 0.0; var edgeEnergy = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i]; let age = time - ripple.z;
    if (age > 0.0 && age < 3.5) {
      let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0); let dist = max(length(delta), 0.0001); let dir = delta / dist;
      let spring = sin(age * (elasticity + audio.x * 4.0) - dist * 16.0) * exp(-age * damping);
      let shape = exp(-dist * mix(18.0, 5.0, u.zoom_params.z)); let local = spring * shape;
      displacement += vec2<f32>(dir.x / aspect, dir.y) * local * wobbleStrength * (1.0 + audio.x * 0.5);
      wobbleEnergy += abs(local); edgeEnergy += abs(spring) * pow(clamp(1.0 - abs(dist - 0.15) * 8.0, 0.0, 1.0), 3.0);
    }
  }
  displacement *= foreground;
  let displacedUV = clamp(uv - displacement, vec2<f32>(0.0), vec2<f32>(1.0));
  let base = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
  let history = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv + displacement * 0.3, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let thickness = clamp(0.15 + length(displacement) * 18.0 + wobbleEnergy * 0.08, 0.0, 1.5);
  let normal = normalize(vec3<f32>(-displacement * 24.0, 1.0)); let rim = fresnel(normal.z);
  let warm = vec3<f32>(1.0, 0.45, 0.22); let cool = vec3<f32>(0.18, 0.58, 1.0);
  let scatterTint = mix(warm, cool, tintShift);
  let absorption = exp(-thickness * vec3<f32>(1.5, 1.0, 0.65));
  var rgb = mix(scatterTint, base.rgb, absorption) + scatterTint * edgeEnergy * (0.1 + audio.y * 0.3) + rim * vec3<f32>(0.12, 0.18, 0.24);
  let trailMix = clamp(0.08 + u.zoom_params.x * 0.22, 0.08, 0.3) * history.a;
  rgb = aces(mix(rgb, history.rgb, trailMix));
  let alpha = clamp(base.a * foreground * (0.72 + thickness * 0.18) + edgeEnergy * 0.14 + history.a * trailMix * 0.1, 0.0, 1.0);
  let outputColor = vec4<f32>(rgb, alpha);
  textureStore(writeTexture, coord, outputColor); textureStore(dataTextureA, coord, outputColor);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, displacedUV, 0.0).r;
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
