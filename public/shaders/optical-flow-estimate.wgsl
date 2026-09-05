// Optical Flow Dream — canonical single-pass dream-field estimator.
// A/C: HDR dream RGB and semantic trail coverage. No history-ring binding.

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
fn hist(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> { return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w)); if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1); let res = vec2<f32>(size);
  let uv = (vec2<f32>(p) + 0.5) / res; let aspect = res.x / max(res.y, 1.0); let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0)); let cur = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let center = hist(p, hi); let hx = hist(p + vec2<i32>(1, 0), hi); let hy = hist(p + vec2<i32>(0, 1), hi);
  let gx = luma(hx.rgb) - luma(center.rgb); let gy = luma(hy.rgb) - luma(center.rgb); let temporal = luma(cur.rgb) - luma(center.rgb);
  let denom = gx * gx + gy * gy + 0.001; let flowScale = mix(0.25, 3.5, u.zoom_params.x);
  var flow = -vec2<f32>(gx, gy) * temporal / denom * flowScale * (0.018 + audio.x * 0.008);
  let mq = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0); let md = length(mq) + 0.0001;
  let swirl = vec2<f32>(-mq.y, mq.x) / md * exp(-md * 10.0);
  flow += swirl * (0.003 + select(0.0, 0.028 + audio.y * 0.010, u.zoom_config.w > 0.5));
  var fronts = 0.0; let count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < count; i = i + 1u) { let e = u.ripples[i]; let age = time - e.z; if (age >= 0.0 && age < 1.4) { let q = (uv - e.xy) * vec2<f32>(aspect, 1.0); let d = length(q); let ring = exp(-age * 2.0) * exp(-abs(d - age * 0.38) * 62.0); flow += normalize(q + vec2<f32>(0.0001)) * ring * 0.035; fronts += ring; } }
  flow = clamp(flow, vec2<f32>(-0.08), vec2<f32>(0.08));
  let advPx = clamp(vec2<i32>((uv - flow) * res), vec2<i32>(0), hi); let adv = hist(advPx, hi);
  let chroma = mix(0.0, 1.8, u.zoom_params.z) * (1.0 + audio.z * 0.5); let split = normalize(flow + vec2<f32>(0.0001)) * chroma * 3.0;
  let rPx = clamp(advPx + vec2<i32>(split), vec2<i32>(0), hi); let bPx = clamp(advPx - vec2<i32>(split), vec2<i32>(0), hi);
  let dreamSample = vec3<f32>(hist(rPx, hi).r, adv.g, hist(bPx, hi).b);
  let decay = clamp(mix(0.80, 0.987, u.zoom_params.y) + audio.x * 0.01, 0.75, 0.995);
  let dreamMix = mix(0.25, 0.94, u.zoom_params.w); let hue = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + atan2(flow.y, flow.x) * 2.0 + time * (0.3 + audio.y));
  var hdr = mix(cur.rgb, dreamSample * decay, dreamMix); hdr += hue * (length(flow) * 9.0 + fronts * 0.38);
  let alpha = clamp(cur.a * (1.0 - dreamMix * 0.25) + adv.a * decay * dreamMix + length(flow) * 3.0 + fronts * 0.25, 0.0, 1.0);
  let state = vec4<f32>(clamp(hdr, vec3<f32>(0.0), vec3<f32>(8.0)), alpha); textureStore(dataTextureA, p, state);
  let mapped = aces(state.rgb); let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha)); textureStore(writeDepthTexture, p, vec4<f32>(clamp(mix(depth, 1.0 - clamp(length(flow) * 10.0, 0.0, 1.0), 0.35), 0.0, 1.0), 0.0, 0.0, 0.0));
}
