// Rorschach Inkblot — mirrored advected ink with chromatic diffusion memory.
// A/C stores tone-mapped display RGBA. B and extraBuffer are unused.
// Premium mixed-eight upgrade: 2026-08-27.

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

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530718;

fn aces(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) /
               (x * (2.43 * x + 0.59) + 0.14),
               vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let w = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2<f32>(1.0, 0.0)), w.x),
             mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0)), w.x), w.y);
}

fn fbm(p: vec2<f32>) -> f32 {
  var q = p;
  var value = 0.0;
  var amplitude = 0.5;
  for (var i = 0; i < 5; i = i + 1) {
    value += noise(q) * amplitude;
    q = mat2x2<f32>(0.8, 0.6, -0.6, 0.8) * q * 2.03 + vec2<f32>(7.1, 3.7);
    amplitude *= 0.5;
  }
  return value;
}

fn safeCoord(uv: vec2<f32>, resolution: vec2<f32>) -> vec2<i32> {
  return clamp(vec2<i32>(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)) * resolution),
               vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
}

fn historyAt(uv: vec2<f32>, resolution: vec2<f32>) -> vec4<f32> {
  return textureLoad(dataTextureC, safeCoord(uv, resolution), 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = vec2<f32>(gid.xy) / resolution;
  let aspectVec = vec2<f32>(resolution.x / max(resolution.y, 1.0), 1.0);
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let held = u.zoom_config.w > 0.5;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

  let threshold = mix(0.08, 0.9, u.zoom_params.x);
  let distortion = mix(0.015, 0.34, u.zoom_params.y) * (1.0 + mids * 0.35);
  let softness = mix(0.008, 0.22, u.zoom_params.z);
  let invertMode = u.zoom_params.w;
  let axis = mix(0.5, mouse.x, 0.42 + select(0.08, 0.42, held));
  var mirroredUV = uv;
  mirroredUV.x = axis - abs(uv.x - axis);

  let pointerDelta = (mirroredUV - mouse) * aspectVec;
  let pointerDist = length(pointerDelta);
  let pointerVortex = vec2<f32>(-pointerDelta.y, pointerDelta.x) / max(pointerDist, 0.001) / aspectVec;
  let pointerInfluence = exp(-pointerDist * 9.0) * select(0.16, 1.0, held);
  var clickFlow = vec2<f32>(0.0);
  var clickInk = 0.0;
  let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.2) {
      let delta = (mirroredUV - ripple.xy) * aspectVec;
      let rd = length(delta);
      let front = age * (0.19 + bass * 0.09);
      let shell = exp(-abs(rd - front) * 46.0) * exp(-age * 0.85);
      clickFlow += vec2<f32>(-delta.y, delta.x) / max(rd, 0.001) / aspectVec * shell;
      clickInk += shell;
    }
  }

  let fieldP = mirroredUV * vec2<f32>(4.2, 5.6) + vec2<f32>(time * (0.05 + mids * 0.08), -time * (0.11 + bass * 0.04));
  let n0 = fbm(fieldP);
  let nX = fbm(fieldP + vec2<f32>(0.031, 0.0));
  let nY = fbm(fieldP + vec2<f32>(0.0, 0.031));
  let curl = vec2<f32>(nY - n0, -(nX - n0)) * 12.0;
  let advection = curl * distortion * 0.026 + pointerVortex * pointerInfluence * distortion * 0.12 + clickFlow * distortion * 0.05;
  let advectedUV = clamp(mirroredUV - advection, vec2<f32>(0.0), vec2<f32>(1.0));
  let history = historyAt(advectedUV, resolution);

  let rUV = clamp(advectedUV + vec2<f32>(treble * 0.004, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(advectedUV - vec2<f32>(treble * 0.004, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
  let sampleR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
  let sampleG = textureSampleLevel(readTexture, u_sampler, advectedUV, 0.0).g;
  let sampleB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
  let sourceColor = vec3<f32>(sampleR, sampleG, sampleB);
  let sourceLuma = dot(sourceColor, vec3<f32>(0.2126, 0.7152, 0.0722));
  let organic = fbm(fieldP * 1.7 + n0 * 3.0);
  var ink = 1.0 - smoothstep(threshold - softness, threshold + softness, sourceLuma + (organic - 0.5) * distortion);
  ink = clamp(max(ink, history.a * (0.79 + bass * 0.055)) + clickInk * 0.22 + pointerInfluence * 0.08, 0.0, 1.0);

  let inkHue = 0.5 + 0.5 * cos(TAU * (vec3<f32>(0.03, 0.36, 0.69) + organic * 0.16 + time * 0.018 + treble * 0.04));
  let darkInk = mix(vec3<f32>(0.008, 0.006, 0.014), inkHue * (0.15 + mids * 0.09), 0.32 + treble * 0.16);
  let paper = vec3<f32>(0.92, 0.88, 0.78) * (0.88 + n0 * 0.12);
  let normalColor = mix(paper, darkInk, ink);
  let invertedColor = mix(vec3<f32>(0.025, 0.018, 0.045), inkHue * (0.82 + bass * 0.35), 1.0 - ink);
  var hdr = mix(normalColor, invertedColor, smoothstep(0.35, 0.65, invertMode));
  hdr = mix(hdr, history.rgb, clamp(0.025 + softness * 0.24 + mids * 0.015, 0.0, 0.11));
  let depth = textureLoad(readDepthTexture, coord, 0).r;
  hdr *= mix(1.08, 0.76, clamp(depth, 0.0, 1.0) * ink);
  let display = aces(max(hdr, vec3<f32>(0.0)));
  let alpha = clamp(0.12 + ink * 0.88, 0.0, 1.0);
  let result = vec4<f32>(display, alpha);

  textureStore(dataTextureA, coord, result);
  textureStore(writeTexture, coord, result);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
