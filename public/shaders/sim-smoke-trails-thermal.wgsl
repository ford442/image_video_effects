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

fn aces(x: vec3f) -> vec3f {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + vec3f(b))) / (x * (c * x + vec3f(d)) + vec3f(e)), vec3f(0.0), vec3f(1.0));
}
fn stateAt(p: vec2i, dims: vec2i) -> vec4f {
  return textureLoad(dataTextureC, clamp(p, vec2i(0), dims - vec2i(1)), 0);
}
fn hash21(p: vec2f) -> f32 { return fract(sin(dot(p, vec2f(41.13, 289.7))) * 43758.5453); }

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3u) {
  let dimsU = textureDimensions(dataTextureC);
  if (gid.x >= dimsU.x || gid.y >= dimsU.y) { return; }
  let p = vec2i(gid.xy); let dims = vec2i(dimsU);
  let uv = (vec2f(gid.xy) + vec2f(0.5)) / vec2f(dimsU);
  let densityScale = 0.35 + u.zoom_params.x * 1.8;
  let turbulence = u.zoom_params.y;
  let riseSpeed = 0.15 + u.zoom_params.z * 1.4;
  let thermal = 0.4 + u.zoom_params.w * 2.4;
  let dt = clamp((1.0 / 60.0), 0.0, 0.033);
  let c = stateAt(p, dims);
  let travel = c.zw * vec2f(dimsU) * dt * 0.8 - vec2f(0.0, riseSpeed * (0.5 + c.y) * dt * f32(dimsU.y));
  let adv = stateAt(p - vec2i(round(travel)), dims);
  let n = stateAt(p + vec2i(0, 1), dims); let s = stateAt(p + vec2i(0, -1), dims);
  let e = stateAt(p + vec2i(1, 0), dims); let w = stateAt(p + vec2i(-1, 0), dims);
  let avg = (n + s + e + w) * 0.25;
  var density = mix(adv.x, avg.x, 0.028 + 0.055 * turbulence);
  var temp = mix(adv.y, avg.y, 0.04);
  var velocity = mix(adv.zw, avg.zw, 0.035);
  let curl = vec2f(n.x - s.x, w.x - e.x) * (0.3 + 1.4 * turbulence);
  let jitter = vec2f(hash21(vec2f(p) + u.config.x) - 0.5, hash21(vec2f(p.yx) - u.config.x) - 0.5);
  velocity += curl + jitter * 0.025 * turbulence + vec2f(0.0, riseSpeed * temp * 0.035);

  let aspect = u.config.zw.x / max(u.config.zw.y, 1.0);
  let pointer = u.zoom_config.yz;
  let q = (uv - pointer) * vec2f(aspect, 1.0);
  let source = exp(-dot(q, q) * 260.0) * step(0.5, u.zoom_config.w);
  let audio = plasmaBuffer[0].xyz;
  density += source * (0.025 + 0.07 * audio.x) * densityScale;
  temp += source * (0.045 + 0.09 * audio.z) * thermal;
  velocity += source * vec2f((audio.y - audio.z) * 0.08, 0.08 + audio.x * 0.12);
  let clickCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < clickCount; i = i + 1u) {
    let event = u.ripples[i]; let age = u.config.x - event.z;
    if (age >= 0.0 && age < 2.0) {
      let cp = event.xy;
      let cq = (uv - cp) * vec2f(aspect, 1.0);
      let radius = 0.025 + age * 0.18;
      let ring = exp(-pow((length(cq) - radius) * 58.0, 2.0)) * exp(-age * 1.8);
      density += ring * (0.012 + audio.y * 0.04);
      temp += ring * (0.018 + audio.z * 0.05);
      velocity += normalize(cq + vec2f(0.0001)) * ring * 0.09;
    }
  }
  density = clamp(density * exp(-dt * (0.22 + 0.22 / densityScale)), 0.0, 2.0);
  temp = clamp(temp * exp(-dt * (0.7 + 0.3 / thermal)), 0.0, 2.0);
  velocity = clamp(velocity * exp(-dt * 1.6), vec2f(-1.5), vec2f(1.5));
  textureStore(dataTextureA, p, vec4f(density, temp, velocity));

  let warped = clamp(uv + velocity / vec2f(dimsU) * (2.0 + 7.0 * temp), vec2f(0.0), vec2f(1.0));
  let scene = textureSampleLevel(readTexture, u_sampler, warped, 0.0).rgb;
  let blackbody = mix(vec3f(0.12, 0.14, 0.18), vec3f(4.2, 1.25, 0.2), smoothstep(0.08, 1.2, temp));
  let transmittance = exp(-density * densityScale);
  let smoke = blackbody * density * (0.15 + 0.55 * temp) + vec3f(audio.x, audio.y * 0.45, audio.z) * density * 0.12;
  textureStore(writeTexture, p, vec4f(aces(scene * transmittance + smoke), clamp(1.0 - transmittance, 0.0, 1.0)));
}
