// CRT Phosphor Decay — Composer batch cyber/digital/glitch
// Per-channel phosphor persistence: spring cursor, held static, capped
// click blooms, exact C loads, three-band audio, ACES + semantic alpha.

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

fn hash12(p: vec2<f32>) -> f32 {
  let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  let p3d = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3d.x + p3d.y) * p3d.z);
}

fn halation(uv: vec2<f32>, spread: f32) -> vec3<f32> {
  let e = vec2<f32>(spread / u.config.z, 0.0);
  var c = textureSampleLevel(readTexture, u_sampler, clamp(uv - e * 2.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.08;
  c += textureSampleLevel(readTexture, u_sampler, clamp(uv - e, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.17;
  c += textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb * 0.50;
  c += textureSampleLevel(readTexture, u_sampler, clamp(uv + e, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.17;
  c += textureSampleLevel(readTexture, u_sampler, clamp(uv + e * 2.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.08;
  return c;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let resolution = u.config.zw;
  if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / resolution;
  let time = u.config.x;
  let aspect = resolution.x / max(resolution.y, 1.0);
  let held = u.zoom_config.w > 0.5;
  let mouse = u.zoom_config.yz;

  let audioSens = u.zoom_params.w;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0) * audioSens;
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0) * audioSens;
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0) * audioSens;
  let rowVoice = clamp(plasmaBuffer[(gid.y % 8u) + 1u].x, 0.0, 1.0) * audioSens;

  var smoothMouse = mouse;
  let hasSpring = arrayLength(&extraBuffer) > 138u;
  if (hasSpring && extraBuffer[138] > 0.5) {
    smoothMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }
  if (gid.x == 0u && gid.y == 0u && hasSpring) {
    var springPos = smoothMouse;
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[138] <= 0.5) {
      springPos = mouse;
      springVel = vec2<f32>(0.0);
    } else {
      let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
      let omega = 11.0;
      let accel = (mouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
      springVel += accel * dt;
      springPos += springVel * dt;
    }
    extraBuffer[133] = springPos.x;
    extraBuffer[134] = springPos.y;
    extraBuffer[135] = springVel.x;
    extraBuffer[136] = springVel.y;
    extraBuffer[137] = time;
    extraBuffer[138] = 1.0;
    smoothMouse = springPos;
  }

  let decayBase = 0.82 + u.zoom_params.x * 0.17;
  let scanlineStr = u.zoom_params.y * (1.0 + mids * 0.5);
  let haloSpread = u.zoom_params.z * 4.0 + 0.5;

  let depth = textureLoad(readDepthTexture, coord, 0).r;
  let fresh = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let halo = halation(uv, haloSpread);
  let luma = dot(fresh.rgb, vec3<f32>(0.299, 0.587, 0.114));
  let boosted = mix(fresh.rgb, halo, smoothstep(0.3, 0.9, luma) * 0.35 * (0.5 + depth * 0.5)) * (1.0 + bass * 0.3);

  let prev = textureLoad(dataTextureC, coord, 0).rgb;
  let decayed = vec3<f32>(prev.r * decayBase, prev.g * decayBase * 0.97, prev.b * decayBase * 0.94);
  var outCol = max(boosted, decayed);

  let scanFreq = resolution.y * 0.5 * (1.0 + treble * 0.08 + rowVoice * 0.025);
  let scanline = sin(uv.y * scanFreq) * 0.5 + 0.5;
  outCol *= mix(1.0, scanline, scanlineStr * 0.7);

  let pixX = fract(uv.x * resolution.x);
  let subMask = vec3<f32>(
    smoothstep(0.0, 0.33, pixX) * (1.0 - smoothstep(0.33, 0.66, pixX)),
    smoothstep(0.33, 0.66, pixX) * (1.0 - smoothstep(0.66, 1.0, pixX)),
    smoothstep(0.66, 1.0, pixX)
  ) * 0.4 + 0.6;
  outCol *= mix(vec3<f32>(1.0), subMask, scanlineStr * 0.5);

  let mDist = length((uv - smoothMouse) * vec2<f32>(aspect, 1.0));
  let mouseFalloff = 1.0 - smoothstep(0.0, 0.12, mDist);
  outCol += hash12(uv * time) * mouseFalloff * (0.25 + treble * 0.25) * select(0.5, 1.0, held);

  var clickBloom = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 2.2) {
      let radius = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
      clickBloom = max(clickBloom, (1.0 - smoothstep(0.0, 0.10, radius)) * exp(-age * 2.8) + exp(-abs(radius - age * 0.12) * 65.0) * exp(-age * 1.2) * 0.7);
    }
  }
  outCol += vec3<f32>(1.0, 0.55 + rowVoice * 0.25, 0.3 + treble * 0.3) * clickBloom * 0.65;

  outCol = acesToneMap(outCol * (0.95 + bass * 0.05));

  let alpha = clamp(fresh.a * 0.85 + clickBloom * 0.25 + mouseFalloff * 0.1 + bass * 0.05, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(outCol, alpha));
  textureStore(dataTextureA, coord, vec4<f32>(outCol, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
