// Sim Sand Dunes RGBA — four interacting grain populations.
// A/C: fine sand, coarse sand, moist clumps, airborne dust.

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
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(171.7, 319.3))) * 43758.5453); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w)); if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1); let res = vec2<f32>(size); let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0); let time = u.config.x; let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0)); var s = grainAt(p, hi);
  if (time < 0.12 || dot(s, s) < 0.000001) { let h = hash21(floor(uv * 140.0)); let bed = smoothstep(0.25, 1.0, uv.y); s = vec4<f32>(bed * (0.28 + h * 0.15), bed * (0.18 + (1.0 - h) * 0.12), bed * 0.08, 0.01); }
  let l = grainAt(p + vec2<i32>(-1, 0), hi); let r = grainAt(p + vec2<i32>(1, 0), hi); let t = grainAt(p + vec2<i32>(0, -1), hi); let b = grainAt(p + vec2<i32>(0, 1), hi);
  let lap = l + r + t + b - 4.0 * s; let gravity = mix(0.01, 0.12, u.zoom_params.x) * (1.0 + audio.x * 0.25);
  let wind = (u.zoom_params.y * 2.0 - 1.0) * (0.05 + audio.y * 0.08); let moisture = u.zoom_params.z; let dustiness = u.zoom_params.w;
  let fineGradient = l.r - r.r; let coarseGradient = t.g - b.g; var next = s;
  next.r += lap.r * (0.05 + abs(wind) * 0.05) + fineGradient * wind * 0.08 + (t.r - s.r) * gravity * 0.04;
  next.g += lap.g * 0.018 + coarseGradient * gravity * 0.025;
  let clump = min(next.r, 0.02 + moisture * 0.04); next.r -= clump * moisture * 0.12; next.b += clump * moisture * 0.12 + lap.b * 0.012;
  next.a += (abs(wind) * next.r * dustiness * 0.035 + audio.z * dustiness * 0.012) - next.a * (0.025 + moisture * 0.03) + (b.a - t.a) * 0.03;
  let q = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0); let md = length(q); let hover = exp(-md * 15.0); let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  next.r += hover * held * 0.06; next.g += hover * held * 0.035; next.a += hover * (0.004 + held * 0.045);
  var impacts = 0.0; let count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < count; i = i + 1u) { let e = u.ripples[i]; let age = time - e.z; if (age >= 0.0 && age < 1.6) { let d = length((uv - e.xy) * vec2<f32>(aspect, 1.0)); impacts += exp(-age * 2.0) * exp(-abs(d - age * 0.31) * 72.0); } }
  next.a += impacts * (0.16 + dustiness * 0.24); next.r -= impacts * 0.035; next.g += impacts * 0.02; next = clamp(next, vec4<f32>(0.0), vec4<f32>(1.0)); textureStore(dataTextureA, p, next);
  let total = clamp(next.r + next.g + next.b, 0.0, 1.0); let ridges = abs((l.r + l.g) - (r.r + r.g)) + abs((t.r + t.g) - (b.r + b.g));
  let fineColor = vec3<f32>(1.45, 0.75, 0.18); let coarseColor = vec3<f32>(0.80, 0.31, 0.08); let moistColor = vec3<f32>(0.25, 0.12, 0.07); let dustColor = vec3<f32>(1.35, 1.05, 0.62);
  var hdr = next.r * fineColor + next.g * coarseColor + next.b * moistColor + next.a * dustColor * (0.8 + audio.z);
  hdr *= 0.45 + 0.75 * clamp(1.0 - ridges * 2.0, 0.0, 1.0); hdr += impacts * vec3<f32>(1.8, 0.8, 0.2);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0); hdr = mix(src.rgb, hdr, clamp(total + next.a * 0.6, 0.0, 0.94));
  let alpha = clamp(src.a * 0.18 + total * 0.78 + next.a * 0.45, 0.0, 1.0); let mapped = aces(max(hdr, vec3<f32>(0.0)));
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha)); textureStore(writeDepthTexture, p, vec4<f32>(clamp(1.0 - total * 0.72 + next.a * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
