// Sand Dunes — height-field saltation, avalanching, and wind erosion.
// A/C: height, loose grains, downslope velocity, moisture/cohesion.

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
fn sandAt(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> { return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w)); if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1); let res = vec2<f32>(size);
  let uv = (vec2<f32>(p) + 0.5) / res; let aspect = res.x / max(res.y, 1.0); let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0)); var s = sandAt(p, hi);
  if (time < 0.12 || dot(s, s) < 0.000001) { let src0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0); let seed = hash21(floor(uv * 180.0)); s = vec4<f32>(clamp(uv.y * 0.72 + dot(src0.rgb, vec3<f32>(0.18)) * 0.22 + seed * 0.08, 0.0, 1.0), 0.18 + seed * 0.12, 0.0, 0.08); }
  let l = sandAt(p + vec2<i32>(-1, 0), hi); let r = sandAt(p + vec2<i32>(1, 0), hi); let t = sandAt(p + vec2<i32>(0, -1), hi); let b = sandAt(p + vec2<i32>(0, 1), hi);
  let lap = l.r + r.r + t.r + b.r - 4.0 * s.r; let slope = vec2<f32>(r.r - l.r, b.r - t.r) * 0.5;
  let gravity = mix(0.02, 0.18, u.zoom_params.x) * (1.0 + audio.x * 0.25);
  let wind = (u.zoom_params.y * 2.0 - 1.0) * (0.02 + audio.y * 0.05); let viscosity = mix(0.96, 0.55, u.zoom_params.z);
  let erosion = mix(0.002, 0.045, u.zoom_params.w) * (1.0 + audio.z * 0.5); let repose = mix(0.035, 0.16, u.zoom_params.z);
  let avalanche = max(length(slope) - repose, 0.0); var velocity = s.b * viscosity + slope.y * gravity + wind * slope.x;
  var loose = clamp(s.g + erosion * (abs(slope.x) + audio.z * 0.15) - avalanche * 0.22, 0.0, 1.0);
  var height = s.r + lap * (0.018 + avalanche * gravity) - velocity * 0.018 + loose * wind * (l.g - r.g);
  let mq = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0); let md = length(mq); let hover = exp(-md * 16.0); let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  height += hover * held * (0.035 + audio.x * 0.02); loose += hover * (0.002 + held * 0.08); velocity += hover * held * 0.04;
  var impacts = 0.0; let count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < count; i = i + 1u) { let e = u.ripples[i]; let age = time - e.z; if (age >= 0.0 && age < 1.8) { let d = length((uv - e.xy) * vec2<f32>(aspect, 1.0)); impacts += exp(-age * 1.8) * exp(-abs(d - age * 0.26) * 76.0); } }
  height += impacts * 0.028; loose += impacts * 0.10; velocity -= impacts * 0.06;
  let moisture = clamp(mix(s.a, 0.05 + audio.x * 0.08 + u.zoom_params.z * 0.28, 0.015) + hover * held * 0.01, 0.0, 1.0);
  let next = vec4<f32>(clamp(height, 0.0, 1.2), clamp(loose, 0.0, 1.0), clamp(velocity, -1.0, 1.0), moisture); textureStore(dataTextureA, p, next);
  let normal = normalize(vec3<f32>(-slope.x * 8.0, -slope.y * 8.0, 1.0)); let sun = normalize(vec3<f32>(-0.45 + wind * 2.0, -0.55, 0.75));
  let light = 0.18 + 0.82 * max(dot(normal, sun), 0.0); let strata = 0.5 + 0.5 * sin((uv.x * 70.0 + next.r * 34.0) + time * wind * 7.0);
  let dry = vec3<f32>(1.35, 0.63, 0.14); let wet = vec3<f32>(0.38, 0.15, 0.05); var hdr = mix(dry, wet, moisture) * (light + strata * loose * 0.18);
  hdr += vec3<f32>(1.6, 0.9, 0.25) * impacts * (0.4 + audio.z); let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0); hdr = mix(src.rgb, hdr, clamp(next.r * 0.8 + loose * 0.3, 0.0, 0.95));
  let alpha = clamp(src.a * 0.20 + next.r * 0.68 + loose * 0.25 + impacts * 0.25, 0.0, 1.0); let mapped = aces(max(hdr, vec3<f32>(0.0)));
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha)); textureStore(writeDepthTexture, p, vec4<f32>(clamp(1.0 - next.r * 0.78, 0.0, 1.0), 0.0, 0.0, 0.0));
}
