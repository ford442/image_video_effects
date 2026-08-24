// Interference Moire Field — crossed analytic line waves and circular pulses
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
const TAU: f32 = 6.28318530718;

fn rotate2(p: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a); let s = sin(a);
  return vec2<f32>(c * p.x - s * p.y, s * p.x + c * p.y);
}
fn palette(t: f32) -> vec3<f32> {
  return vec3<f32>(0.52) + vec3<f32>(0.48) * cos(TAU * (vec3<f32>(t) + vec3<f32>(0.0, 0.27, 0.61)));
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = u.config.zw;
  if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
  let uv01 = (vec2<f32>(pixel) + vec2<f32>(0.5)) / res;
  let aspect = res.x / res.y;
  let p = (uv01 - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let density = mix(12.0, 72.0, clamp(u.zoom_params.x, 0.0, 1.0));
  let crossing = mix(0.08, 1.48, clamp(u.zoom_params.y, 0.0, 1.0));
  let warpStrength = mix(0.0, 0.42, clamp(u.zoom_params.z, 0.0, 1.0));
  let colorPhase = u.zoom_params.w;
  let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
  let held = clamp(u.zoom_config.w, 0.0, 1.0);
  let pointerWarp = exp(-distance(p, mouse) * 7.0) * held;
  let phaseWarp = warpStrength * (sin(p.y * 7.0 + time * 0.7 + mids) + cos(p.x * 9.0 - time * 0.5 + bass));
  let q1 = rotate2(p, crossing * 0.5 + pointerWarp * 0.18);
  let q2 = rotate2(p, -crossing * 0.5 - pointerWarp * 0.18);
  let lineA = sin(q1.x * density + phaseWarp * density + time * (0.4 + bass * 0.25));
  let lineB = sin(q2.x * density - phaseWarp * density * 0.8 - time * (0.32 + mids * 0.2));
  let crossed = lineA * lineB;
  let ridges = pow(abs(crossed), mix(0.35, 1.4, clamp(u.zoom_params.x, 0.0, 1.0)));
  let beat = 0.5 + 0.5 * cos((lineA - lineB) * 4.0 + treble * 2.0);

  var pulse = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var ri = 0u; ri < rippleCount; ri++) {
    let ripple = u.ripples[ri];
    let age = time - ripple.z;
    if (age > 0.0 && age < 3.0) {
      let center = (ripple.xy - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
      pulse += exp(-abs(distance(p, center) - age * 0.28) * 74.0) * exp(-age * 1.25);
    }
  }
  let circular = sin(length(p - mouse * held) * density * 0.55 - time * 1.2) * pointerWarp;
  var raw = palette(crossed * 0.18 + colorPhase + time * 0.025 + pulse * 0.12) * (0.16 + ridges * 1.25);
  raw += palette(beat * 0.2 + colorPhase + 0.32) * beat * (0.18 + treble * 0.22);
  raw += vec3<f32>(1.3 + bass * 0.3, 0.55 + mids * 0.25, 1.6 + treble * 0.45) * (pulse + abs(circular) * 0.28);
  let prev = textureLoad(dataTextureC, pixel, 0);
  raw = clamp(mix(prev.rgb * 0.93, raw, 0.31 + warpStrength * 0.08), vec3<f32>(0.0), vec3<f32>(7.0));
  let alpha = clamp(0.04 + ridges * 0.62 + beat * 0.12 + pulse * 0.2, 0.04, 0.98);
  let depth = clamp(ridges * 0.58 + abs(lineA - lineB) * 0.12 + pulse * 0.2, 0.0, 1.0);
  textureStore(dataTextureA, pixel, vec4<f32>(raw, alpha));
  textureStore(writeTexture, pixel, vec4<f32>(acesToneMap(raw * 1.06), alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
