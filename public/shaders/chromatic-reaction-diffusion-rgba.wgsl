// Chromatic Reaction Diffusion RGBA — cross-coupled warm/cool Turing systems.
// A/C: warm U/V in RG, cool U/V in BA. Raw chemistry is never tone mapped.

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
fn loadState(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> { return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(41.23, 289.17))) * 43758.5453); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1);
  let res = vec2<f32>(size); let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0); let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  var s = loadState(p, hi);
  if (time < 0.12 || dot(s, s) < 0.000001) {
    let cell = floor(uv * vec2<f32>(37.0, 29.0));
    s = vec4<f32>(1.0, step(0.86, hash21(cell)) * 0.65, 1.0, step(0.86, hash21(cell + 19.7)) * 0.65);
  }
  let l = loadState(p + vec2<i32>(-1, 0), hi); let r = loadState(p + vec2<i32>(1, 0), hi);
  let t = loadState(p + vec2<i32>(0, -1), hi); let btm = loadState(p + vec2<i32>(0, 1), hi);
  let lap = l + r + t + btm - 4.0 * s;
  let feed = mix(0.020, 0.061, u.zoom_params.x) + audio.y * 0.004;
  let kill = mix(0.043, 0.070, u.zoom_params.y) + audio.x * 0.004;
  let separation = mix(0.02, 0.34, u.zoom_params.z);
  let coupling = mix(0.0, 0.22, u.zoom_params.w) * (1.0 + audio.z * 0.35);
  let warmReaction = s.r * s.g * s.g; let coolReaction = s.b * s.a * s.a;
  let phase = sin((uv.x - uv.y) * 18.0 + time * (0.35 + audio.y));
  let delta = vec4<f32>(
    (0.82 + separation * 0.08) * lap.r - warmReaction + feed * (1.0 - s.r) - coupling * s.r * s.a,
    0.30 * lap.g + warmReaction - (feed + kill + phase * separation * 0.002) * s.g,
    (0.76 - separation * 0.06) * lap.b - coolReaction + feed * (1.0 - s.b) - coupling * s.b * s.g,
    0.27 * lap.a + coolReaction - (feed + kill - phase * separation * 0.002) * s.a
  );
  s = clamp(s + delta * 0.80, vec4<f32>(0.0), vec4<f32>(1.0));
  let q = (uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0);
  let radius = length(q); let angle = atan2(q.y, q.x);
  let hoverSpiral = exp(-radius * 14.0) * (0.5 + 0.5 * sin(angle * 5.0 - radius * 70.0 + time * 2.0));
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  s.g += hoverSpiral * (0.006 + held * (0.30 + audio.x * 0.10));
  s.a += hoverSpiral * held * (0.22 + audio.z * 0.12);
  var fronts = 0.0; let count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < count; i = i + 1u) {
    let event = u.ripples[i]; let age = time - event.z;
    if (age >= 0.0 && age < 1.6) {
      let d = length((uv - event.xy) * vec2<f32>(aspect, 1.0));
      fronts += exp(-age * 2.0) * exp(-abs(d - age * 0.27) * 78.0);
    }
  }
  s.g += fronts * 0.24; s.a += fronts * 0.20; s = clamp(s, vec4<f32>(0.0), vec4<f32>(1.0));
  textureStore(dataTextureA, p, s);
  let warmEdge = abs(l.g - r.g) + abs(t.g - btm.g); let coolEdge = abs(l.a - r.a) + abs(t.a - btm.a);
  let pigment = s.r * vec3<f32>(1.25, 0.10, 0.02) + s.g * vec3<f32>(2.3, 0.75, 0.04)
              + s.b * vec3<f32>(0.02, 0.28, 1.55) + s.a * vec3<f32>(0.58, 0.04, 1.80);
  let fringe = warmEdge * vec3<f32>(1.8, 0.25, 0.05) + coolEdge * vec3<f32>(0.05, 0.55, 2.2);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let hdr = mix(src.rgb, pigment + fringe * separation * 2.0, 0.68 + coupling * 0.65);
  let boundary = clamp((warmEdge + coolEdge) * 2.2 + fronts, 0.0, 1.0);
  let alpha = clamp(src.a * 0.18 + boundary * 0.62 + max(s.g, s.a) * 0.52, 0.0, 1.0);
  let mapped = aces(max(hdr, vec3<f32>(0.0)));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha));
  textureStore(writeDepthTexture, p, vec4<f32>(clamp(mix(depth, 0.20 + 0.68 * (1.0 - boundary), alpha * 0.6), 0.0, 1.0), 0.0, 0.0, 0.0));
}
