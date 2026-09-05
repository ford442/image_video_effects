// Pixel Sand — granular density/velocity automaton with avalanche sheets.
// A/C: density, horizontal velocity, vertical velocity, kinetic energy.
// This pass intentionally migrates the legacy B-state to authoritative A.

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
fn grainAt(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> { return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w)); if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1); let res = vec2<f32>(size); let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0); let time = u.config.x; let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0)); var s = grainAt(p, hi);
  if (time < 0.12 || dot(s, s) < 0.000001) { let src0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0); let seed = hash21(vec2<f32>(p)); let density = step(seed, clamp(u.zoom_params.y * (0.35 + uv.y * 0.65) + dot(src0.rgb, vec3<f32>(0.08)), 0.0, 1.0)); s = vec4<f32>(density, 0.0, 0.0, density * 0.05); }
  let l = grainAt(p + vec2<i32>(-1, 0), hi); let r = grainAt(p + vec2<i32>(1, 0), hi); let t = grainAt(p + vec2<i32>(0, -1), hi); let b = grainAt(p + vec2<i32>(0, 1), hi);
  let gravity = mix(0.015, 0.16, u.zoom_params.x) * (1.0 + audio.x * 0.35); let curlForce = mix(0.0, 0.18, u.zoom_params.z) * (1.0 + audio.y * 0.4); let bounce = mix(0.05, 0.82, u.zoom_params.w);
  let densityGrad = vec2<f32>(r.r - l.r, b.r - t.r) * 0.5; let sheet = max(s.r - b.r, 0.0); let avalanche = max(abs(densityGrad.x) - 0.08, 0.0);
  let noiseAngle = time * (0.35 + audio.y) + uv.x * 19.0 - uv.y * 13.0; let curl = vec2<f32>(cos(noiseAngle), sin(noiseAngle));
  var velocity = s.gb * 0.91 + vec2<f32>(-densityGrad.x * avalanche, gravity * (1.0 - b.r)) + curl * curlForce * (0.15 + s.r);
  if (b.r > 0.82) { velocity.y = -abs(velocity.y) * bounce; velocity.x += sign(hash21(vec2<f32>(p) + time) - 0.5) * avalanche * bounce; }
  let mq = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0); let md = length(mq) + 0.0001; let hover = exp(-md * 18.0); let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  velocity += normalize(vec2<f32>(-mq.y, mq.x) + vec2<f32>(0.0001)) * hover * (0.015 + held * (0.16 + audio.x * 0.06));
  velocity.y -= hover * held * (0.08 + bounce * 0.08);
  var shelves = 0.0; let count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < count; i = i + 1u) { let e = u.ripples[i]; let age = time - e.z; if (age >= 0.0 && age < 1.5) { let q = (uv - e.xy) * vec2<f32>(aspect, 1.0); let d = length(q); let ring = exp(-age * 2.0) * exp(-abs(d - age * 0.32) * 78.0); velocity += normalize(q + vec2<f32>(0.0001)) * ring * 0.18; shelves += ring; } }
  let inflow = t.r * clamp(t.b, 0.0, 1.0) + l.r * max(l.g, 0.0) + r.r * max(-r.g, 0.0); let outflow = s.r * clamp(length(velocity), 0.0, 0.65);
  let density = clamp(s.r + (inflow - outflow) * 0.11 + sheet * 0.04 - shelves * 0.025, 0.0, 1.0); let energy = clamp(mix(s.a, length(velocity) + shelves + audio.z * density * 0.15, 0.16), 0.0, 1.0);
  let next = vec4<f32>(density, clamp(velocity.x, -1.0, 1.0), clamp(velocity.y, -1.0, 1.0), energy); textureStore(dataTextureA, p, next);
  let grain = step(hash21(vec2<f32>(p) + floor(time * 0.2)), density); let speed = length(velocity); let warm = vec3<f32>(1.45, 0.50, 0.07); let hot = vec3<f32>(2.2, 0.16, 0.03); let cool = vec3<f32>(0.08, 0.45, 1.55);
  var hdr = mix(warm, hot, clamp(speed * 2.0 + audio.x * 0.25, 0.0, 1.0)); hdr = mix(hdr, cool, clamp(audio.z * 0.35 + curlForce * 1.5, 0.0, 0.7)); hdr *= grain * (0.45 + density * 0.9 + energy * 0.7);
  hdr += shelves * vec3<f32>(1.6, 0.65, 0.12); let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0); hdr = mix(src.rgb, hdr, clamp(density * 0.82 + grain * 0.12, 0.0, 0.95));
  let alpha = clamp(src.a * 0.18 + density * 0.78 + energy * 0.20 + shelves * 0.25, 0.0, 1.0); let mapped = aces(max(hdr, vec3<f32>(0.0)));
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha)); textureStore(writeDepthTexture, p, vec4<f32>(clamp(1.0 - density * 0.70 - energy * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
