// Cymatic Sand — damped Chladni plate with persistent grain transport.
// A/C: sand density, radial velocity, resonant energy, strike memory.

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
fn chladni(p: vec2<f32>, n: f32, m: f32) -> f32 { return cos(n * 3.14159265 * p.x) * cos(m * 3.14159265 * p.y) - cos(m * 3.14159265 * p.x) * cos(n * 3.14159265 * p.y); }
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(91.7, 313.9))) * 43758.5453); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w)); if (gid.x >= size.x || gid.y >= size.y) { return; }
  let px = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1); let res = vec2<f32>(size); let uv = (vec2<f32>(px) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0); let time = u.config.x; let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0)); var s = stateAt(px, hi);
  if (time < 0.12 || dot(s, s) < 0.000001) { let seed = hash21(vec2<f32>(px)); s = vec4<f32>(0.22 + seed * 0.18, 0.0, 0.0, 0.0); }
  let mode = 2.0 + floor(u.zoom_params.x * 15.0); let harmonic = u.zoom_params.y; let densityControl = u.zoom_params.z; let sensitivity = u.zoom_params.w;
  var plate = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0); let mouseOffset = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  plate -= mouseOffset * (0.12 + select(0.0, 0.32, u.zoom_config.w > 0.5));
  let w0 = chladni(plate, mode + audio.x * sensitivity * 3.0, mode + 2.0 + audio.y * sensitivity * 4.0);
  let w1 = chladni(plate.yx + vec2<f32>(time * 0.012, 0.0), mode + 3.0 + audio.z * 4.0, mode + 5.0);
  let w2 = sin(length(plate) * (18.0 + mode) - time * (1.0 + audio.x * 3.0)); let wave = mix(w0, w1, harmonic) + w2 * harmonic * 0.22;
  let node = 1.0 - smoothstep(0.015, 0.12 + audio.x * sensitivity * 0.04, abs(wave));
  let l = stateAt(px + vec2<i32>(-1, 0), hi); let r = stateAt(px + vec2<i32>(1, 0), hi); let t = stateAt(px + vec2<i32>(0, -1), hi); let b = stateAt(px + vec2<i32>(0, 1), hi);
  let lapDensity = l.r + r.r + t.r + b.r - 4.0 * s.r; let drive = (node - s.r) * (0.025 + audio.x * sensitivity * 0.035);
  var velocity = (s.g + drive + lapDensity * 0.035) * (0.91 - audio.y * 0.03); var strikes = 0.0; let count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < count; i = i + 1u) { let e = u.ripples[i]; let age = time - e.z; if (age >= 0.0 && age < 2.0) { let d = length((uv - e.xy) * vec2<f32>(aspect, 1.0)); strikes += exp(-age * 1.7) * exp(-abs(d - age * (0.24 + audio.x * 0.07)) * 72.0); } }
  velocity += strikes * 0.18; let held = select(0.0, 1.0, u.zoom_config.w > 0.5); let md = length((uv - u.zoom_config.yz) * vec2<f32>(aspect, 1.0)); let hover = exp(-md * 18.0);
  velocity += hover * (0.004 + held * 0.10); let newDensity = clamp(s.r + velocity * 0.08 + node * (0.008 + densityControl * 0.018) - abs(wave) * s.r * 0.008, 0.0, 1.0);
  let energy = clamp(mix(s.b, abs(wave) * (0.35 + audio.y * sensitivity) + strikes, 0.12), 0.0, 1.0); let memory = clamp(max(s.a * 0.94, strikes + hover * held * 0.5), 0.0, 1.0);
  let next = vec4<f32>(newDensity, clamp(velocity, -1.0, 1.0), energy, memory); textureStore(dataTextureA, px, next);
  let grain = step(hash21(vec2<f32>(px)), clamp(newDensity * (0.35 + densityControl), 0.0, 1.0)); let bronze = vec3<f32>(1.35, 0.58, 0.14); let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + wave * 4.0 + time * 0.15);
  var hdr = bronze * grain * (0.55 + newDensity + energy * 0.5) + spectral * (node * 0.28 + strikes * 0.65 + audio * sensitivity * 0.12);
  let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0); hdr = mix(src.rgb * 0.45, hdr, clamp(newDensity * 0.75 + node * 0.25, 0.25, 0.95));
  let alpha = clamp(src.a * 0.15 + newDensity * 0.75 + node * 0.25 + memory * 0.25, 0.0, 1.0); let mapped = aces(max(hdr, vec3<f32>(0.0)));
  textureStore(writeTexture, px, vec4<f32>(mapped * alpha, alpha)); textureStore(writeDepthTexture, px, vec4<f32>(clamp(1.0 - newDensity * 0.62 - node * 0.12, 0.0, 1.0), 0.0, 0.0, 0.0));
}
