// Alpha Reaction Diffusion RGBA — four-species ecological Gray-Scott field.
// A/C: warm activator/inhibitor in RG, cool activator/inhibitor in BA.
// Upgraded 2026-08-23: exact C stencil, spectral kinetics, held inoculation,
// bounded click fronts, ACES display, and semantic activity alpha.

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

fn stateAt(p: vec2<i32>, hi: vec2<i32>) -> vec4<f32> { return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), hi), 0); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1);
  let res = vec2<f32>(size); let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0); let time = u.config.x;
  let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  var s = stateAt(p, hi);
  if (time < 0.12 || dot(s, s) < 0.000001) {
    let seed = step(0.82, hash21(floor(uv * 41.0)));
    s = vec4<f32>(1.0, seed * 0.62, 1.0, seed * 0.38);
  }
  let l = stateAt(p + vec2<i32>(-1, 0), hi); let r = stateAt(p + vec2<i32>(1, 0), hi);
  let t = stateAt(p + vec2<i32>(0, -1), hi); let btm = stateAt(p + vec2<i32>(0, 1), hi);
  let lap = l + r + t + btm - 4.0 * s;
  let feed = mix(0.018, 0.064, u.zoom_params.x) + audio.y * 0.004;
  let kill = mix(0.041, 0.071, u.zoom_params.y) + audio.x * 0.005;
  let cross = mix(0.01, 0.24, u.zoom_params.z) * (1.0 + audio.y * 0.25);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let nutrient = dot(src.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let reactAB = s.r * s.g * s.g; let reactCD = s.b * s.a * s.a;
  let ds = vec4<f32>(
    (0.84 + audio.y * 0.08) * lap.r - reactAB + feed * (1.0 - s.r) - cross * s.r * s.a,
    (0.31 + audio.x * 0.05) * lap.g + reactAB - (feed + kill) * s.g,
    (0.76 + audio.z * 0.10) * lap.b - reactCD + feed * (1.0 - s.b) - cross * s.b * s.g,
    (0.27 + audio.x * 0.04) * lap.a + reactCD - (feed + kill * 0.97) * s.a
  );
  s = clamp(s + ds * 0.78, vec4<f32>(0.0), vec4<f32>(1.0));
  s.r += nutrient * u.zoom_params.w * 0.012; s.b += (1.0 - nutrient) * u.zoom_params.w * 0.009;
  let md = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0));
  let hover = exp(-md * 18.0); let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
  s.g += hover * (0.008 + held * (0.24 + audio.x * 0.12));
  s.a += hover * held * (0.17 + audio.z * 0.10);
  var clickEnergy = 0.0; let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let event = u.ripples[i]; let age = time - event.z;
    if (age >= 0.0 && age < 1.8) {
      let dist = length((uv - event.xy) * vec2<f32>(aspect, 1.0));
      clickEnergy += exp(-age * 1.8) * exp(-abs(dist - age * (0.20 + audio.x * 0.05)) * 70.0);
    }
  }
  s.g += clickEnergy * 0.22; s.a += clickEnergy * 0.14;
  s = clamp(s, vec4<f32>(0.0), vec4<f32>(1.0));
  textureStore(dataTextureA, p, s);
  let boundary = abs(s.r - s.g) + abs(s.b - s.a);
  let instability = clamp(length(ds) * 5.0 + clickEnergy, 0.0, 1.0);
  var hdr = s.r * vec3<f32>(0.08, 0.42, 1.35) + s.g * vec3<f32>(2.10, 0.20, 0.04)
          + s.b * vec3<f32>(0.05, 1.25, 0.40) + s.a * vec3<f32>(1.65, 0.70, 0.05);
  hdr += boundary * boundary * vec3<f32>(0.45, 0.12 + audio.y * 0.15, 0.55);
  hdr = mix(src.rgb, hdr, 0.72 + u.zoom_params.w * 0.20);
  let alpha = clamp(src.a * 0.20 + boundary * 0.55 + instability * 0.35 + max(s.g, s.a) * 0.45, 0.0, 1.0);
  let mapped = aces(max(hdr, vec3<f32>(0.0)));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha));
  textureStore(writeDepthTexture, p, vec4<f32>(clamp(mix(depth, 1.0 - boundary * 0.7, alpha * 0.55), 0.0, 1.0), 0.0, 0.0, 0.0));
}
