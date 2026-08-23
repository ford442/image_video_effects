// Luma Flow Field — iso-luminance advection with curl ribbons.
// A/C: HDR trail RGB plus semantic trail coverage in alpha.

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
fn luma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722)); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453); }
fn noise(p: vec2<f32>) -> f32 { let i = floor(p); let f = fract(p); let q = f * f * (3.0 - 2.0 * f); return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), q.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0)), q.x), q.y); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w)); if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1); let res = vec2<f32>(size);
  let uv = (vec2<f32>(p) + 0.5) / res; let aspect = res.x / max(res.y, 1.0); let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let px = 1.0 / res; let left = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(px.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let right = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(px.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let top = textureSampleLevel(readTexture, u_sampler, clamp(uv - vec2<f32>(0.0, px.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let bottom = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(0.0, px.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let grad = vec2<f32>(luma(right.rgb) - luma(left.rgb), luma(bottom.rgb) - luma(top.rgb));
  let isoFlow = normalize(vec2<f32>(-grad.y, grad.x) + vec2<f32>(0.0001));
  let flowScale = mix(1.5, 12.0, u.zoom_params.x); let decay = mix(0.80, 0.985, u.zoom_params.y);
  let curlStrength = mix(0.05, 1.3, u.zoom_params.z); let audioSensitivity = u.zoom_params.w;
  let np = uv * flowScale + vec2<f32>(time * (0.13 + audio.x * 0.18), -time * (0.09 + audio.y * 0.12));
  let eps = 0.025; let curl = normalize(vec2<f32>(noise(np + vec2<f32>(0.0, eps)) - noise(np - vec2<f32>(0.0, eps)), noise(np - vec2<f32>(eps, 0.0)) - noise(np + vec2<f32>(eps, 0.0))) + vec2<f32>(0.0001));
  var flow = isoFlow * (0.8 + length(grad) * 3.0) + curl * curlStrength * (0.7 + audio.y * audioSensitivity);
  let mq = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0); let md = length(mq) + 0.0001;
  flow += vec2<f32>(-mq.y, mq.x) / md * exp(-md * 12.0) * (0.25 + select(0.0, 1.1, u.zoom_config.w > 0.5));
  var fronts = 0.0; let count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < count; i = i + 1u) { let e = u.ripples[i]; let age = time - e.z; if (age >= 0.0 && age < 1.5) { let d = length((uv - e.xy) * vec2<f32>(aspect, 1.0)); let ring = exp(-age * 2.1) * exp(-abs(d - age * 0.34) * 70.0); flow += normalize(uv - e.xy + vec2<f32>(0.0001)) * ring * 1.6; fronts += ring; } }
  let velocity = flow * px * (1.5 + 6.0 * u.zoom_params.x + audio.x * audioSensitivity * 4.0);
  let histPx = clamp(vec2<i32>((uv - velocity) * res), vec2<i32>(0), hi); let history = textureLoad(dataTextureC, histPx, 0);
  let src = textureSampleLevel(readTexture, u_sampler, clamp(uv + velocity * 0.4, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
  let phase = atan2(flow.y, flow.x) + time * (0.7 + audio.z);
  let ribbon = 0.5 + 0.5 * cos(vec3<f32>(phase, phase - 2.094, phase + 2.094));
  let edge = clamp(length(grad) * 4.0, 0.0, 1.0); let fresh = src.rgb * (0.7 + ribbon * (0.35 + audio * audioSensitivity * 0.25));
  let hdr = mix(fresh, history.rgb * decay, 0.52 + u.zoom_params.y * 0.30) + ribbon * (edge * 0.25 + fronts * 0.4);
  let alpha = clamp(src.a * 0.35 + edge * 0.5 + history.a * decay * 0.45 + fronts * 0.35, 0.0, 1.0);
  let state = vec4<f32>(clamp(hdr, vec3<f32>(0.0), vec3<f32>(8.0)), alpha); textureStore(dataTextureA, p, state);
  let mapped = aces(state.rgb); let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha)); textureStore(writeDepthTexture, p, vec4<f32>(clamp(mix(depth, 1.0 - edge, 0.45), 0.0, 1.0), 0.0, 0.0, 0.0));
}
