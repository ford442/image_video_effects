// Photonic Caustics — refractive height-field convergence accumulator.
// A/C: HDR irradiance RGB and caustic coverage. B is never written.

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
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453); }
fn noise(p: vec2<f32>) -> f32 { let i = floor(p); let f = fract(p); let q = f * f * (3.0 - 2.0 * f); return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), q.x), mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0)), q.x), q.y); }
fn aces(x: vec3<f32>) -> vec3<f32> { return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0)); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let size = vec2<u32>(u32(u.config.z), u32(u.config.w)); if (gid.x >= size.x || gid.y >= size.y) { return; }
  let p = vec2<i32>(gid.xy); let hi = vec2<i32>(size) - vec2<i32>(1); let res = vec2<f32>(size); let uv = (vec2<f32>(p) + 0.5) / res;
  let aspect = res.x / max(res.y, 1.0); let texel = 1.0 / res; let time = u.config.x; let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
  let ior = mix(1.05, 1.82, u.zoom_params.x); let lightSize = mix(0.025, 0.34, u.zoom_params.y); let dispersion = mix(0.0, 0.16, u.zoom_params.z); let intensity = mix(0.35, 4.2, u.zoom_params.w);
  let hL = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let hR = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let hT = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let hB = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let rippleHeight = noise(uv * (9.0 + audio.y * 4.0) + vec2<f32>(time * 0.11, -time * 0.08));
  let normal = normalize(vec3<f32>((hL - hR) * 8.0 + sin(uv.y * 42.0 + time) * 0.08, (hT - hB) * 8.0 + cos(uv.x * 37.0 - time * 0.8) * 0.08, 1.0));
  let lightPos = u.zoom_config.yz; let toLight = (lightPos - uv) * vec2<f32>(aspect, 1.0); let lightDist = length(toLight) + 0.001;
  let held = select(0.0, 1.0, u.zoom_config.w > 0.5); let aperture = exp(-lightDist * (3.0 + 10.0 * (1.0 - lightSize))) * (1.0 + held * 1.4);
  let bend = normal.xy * (ior - 1.0) * (0.018 + lightSize * 0.025); let focus = 1.0 / (0.035 + abs(dot(normalize(toLight), normalize(bend + vec2<f32>(0.0001))))) ;
  let wavePhase = (uv.x + normal.x * 0.08) * 74.0 + (uv.y + normal.y * 0.08) * 61.0 + rippleHeight * 8.0 - time * (1.4 + audio.y * 2.0);
  let bands = pow(0.5 + 0.5 * cos(vec3<f32>(wavePhase - dispersion * 18.0, wavePhase, wavePhase + dispersion * 18.0)), vec3<f32>(6.0));
  var clickLight = 0.0; let count = min(u32(u.config.y), 50u);
  for (var i = 0u; i < count; i = i + 1u) { let e = u.ripples[i]; let age = time - e.z; if (age >= 0.0 && age < 2.2) { let d = length((uv - e.xy) * vec2<f32>(aspect, 1.0)); clickLight += exp(-age * 1.5) * exp(-abs(d - age * (0.22 + audio.x * 0.08)) * 82.0); } }
  let spectral = vec3<f32>(1.15 + audio.x * 0.25, 0.95 + audio.y * 0.20, 1.25 + audio.z * 0.35);
  let fresh = bands * spectral * intensity * (0.08 + aperture * 0.55 + clamp(focus * 0.025, 0.0, 0.8)) + clickLight * vec3<f32>(0.45, 0.95, 2.1) * intensity;
  let drift = normalize(toLight + vec2<f32>(0.0001)) * (1.0 + ior * 2.0); let histP = clamp(p - vec2<i32>(drift), vec2<i32>(0), hi); let history = textureLoad(dataTextureC, histP, 0);
  let persistence = clamp(0.86 + lightSize * 0.10 - audio.z * 0.015, 0.78, 0.98); let irradiance = mix(fresh, history.rgb * persistence, 0.72);
  let coverage = clamp(max(max(irradiance.r, irradiance.g), irradiance.b) * 0.45 + clickLight * 0.35 + aperture * 0.15, 0.0, 1.0);
  let state = vec4<f32>(clamp(irradiance, vec3<f32>(0.0), vec3<f32>(12.0)), coverage); textureStore(dataTextureA, p, state);
  let refractUV = clamp(uv + bend + normalize(toLight + vec2<f32>(0.0001)) * clickLight * 0.006, vec2<f32>(0.0), vec2<f32>(1.0)); let src = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0);
  let fresnel = pow(1.0 - clamp(normal.z, 0.0, 1.0), 5.0); let hdr = src.rgb * (0.72 + fresnel * 0.28) + irradiance;
  let alpha = clamp(src.a * 0.58 + coverage * 0.62 + fresnel * 0.12, 0.0, 1.0); let mapped = aces(max(hdr, vec3<f32>(0.0)));
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r; textureStore(writeTexture, p, vec4<f32>(mapped * alpha, alpha)); textureStore(writeDepthTexture, p, vec4<f32>(clamp(depth - coverage * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
}
